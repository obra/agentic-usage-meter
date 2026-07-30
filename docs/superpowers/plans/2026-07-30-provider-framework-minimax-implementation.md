# Provider Framework and MiniMax Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make provider metadata, credentials, refresh, and dashboards extensible, then prove the architecture with a working MiniMax Token Plan adapter.

**Architecture:** Preserve the existing raw-string `Provider` encoding and Keychain record addresses while moving display metadata into a compile-time `ProviderCatalog`. New adapters load their own typed credentials through a raw-data store and conform to one account adapter protocol; `AppModel` delegates refresh and cleanup without provider switches. The normalized model gains additive window metadata and balances, and account dashboards use account-scoped persistent WebKit stores.

**Tech Stack:** Swift 6.2, SwiftUI and WebKit for macOS 26, Security framework, Swift Testing, Swift Package Manager, fake HTTP transports.

## Global Constraints

- Existing `claude`, `codex`, and `kimi` provider encodings remain unchanged.
- Existing Keychain service and UUID account keys remain unchanged.
- Existing state and cache file locations remain unchanged.
- Do not add a legacy decoder or migration. If an existing account cannot decode after a change, stop and ask Jesse before adding compatibility code.
- Provider traffic is direct from the Mac. Credentials stay in Keychain.
- Provider contact, including manual refresh, observes the existing ten-minute per-account floor. Login and explicit reconnect are exempt.
- Successful authentication is persisted before the first usage fetch.
- Diagnostics never contain raw response bodies, credentials, cookies, or authorization headers.
- MiniMax remains experimental until real two-account qualification passes.
- Copied portions of OpenCode Bar commit `4c501b3d97f2f88ff5178ec20d4e45fe3108b3fe` retain MIT attribution.

---

### Task 1: Add a Stable Compile-Time Provider Catalog

**Files:**

- Modify: `Sources/UsageMeterCore/Domain/UsageModels.swift`
- Create: `Sources/UsageMeterCore/Providers/ProviderCatalog.swift`
- Modify: `Sources/UsageMeterUI/Settings/SettingsView.swift`
- Modify: `Sources/UsageMeterUI/Settings/AccountListView.swift`
- Modify: `Sources/UsageMeterUI/Timeline/UsageWindowPresentation.swift`
- Modify: `Sources/UsageMeterUI/Timeline/UsageWindowRow.swift`
- Modify: `Sources/UsageMeterUI/AppModel.swift`
- Test: `Tests/UsageMeterCoreTests/ProviderCatalogTests.swift`
- Test: `Tests/UsageMeterUITests/SettingsViewTests.swift`
- Test: `Tests/UsageMeterUITests/TimelinePresentationTests.swift`

**Interfaces:**

- Consumes: the existing `Provider: String, Codable, CaseIterable, Sendable`.
- Produces: `ProviderCatalog.live`, `ProviderDefinition`, `ProviderColor`,
  `ProviderReleaseState`, `ProviderConnectionStrategy`, and
  `ProviderDashboardStrategy`.

- [x] **Step 1: Write failing provider-encoding and catalog tests**

Create `ProviderCatalogTests.swift`:

```swift
import Foundation
import Testing
@testable import UsageMeterCore

@Suite
struct ProviderCatalogTests {
    @Test
    func existingProviderValuesKeepTheirStoredStrings() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let cases: [(Provider, String)] = [
            (.claude, "\"claude\""),
            (.codex, "\"codex\""),
            (.kimi, "\"kimi\""),
        ]

        for (provider, encoded) in cases {
            #expect(String(decoding: try encoder.encode(provider), as: UTF8.self) == encoded)
            #expect(try decoder.decode(Provider.self, from: Data(encoded.utf8)) == provider)
        }
    }

    @Test
    func liveCatalogHasUniqueProvidersInProductOrder() {
        let providers = ProviderCatalog.live.all.map(\.provider)

        #expect(providers == [
            .claude,
            .codex,
            .kimi,
            .minimax,
            .githubCopilot,
            .antigravity,
            .factory,
            .openCodeGo,
            .openCodeZen,
            .superGrok,
        ])
        #expect(Set(providers).count == providers.count)
    }

    @Test
    func releaseCatalogHidesUnqualifiedProviders() {
        #expect(
            ProviderCatalog.live
                .visibleDefinitions(isDevelopmentBuild: false)
                .map(\.provider)
                == [.claude, .codex, .kimi]
        )
        #expect(
            ProviderCatalog.live
                .visibleDefinitions(isDevelopmentBuild: true)
                .map(\.provider)
                == [.claude, .codex, .kimi]
        )
    }
}
```

The breaks caught are changed persisted IDs, duplicate catalog entries, wrong
product order, or accidental release exposure.

- [x] **Step 2: Run the tests and verify RED**

Run:

```bash
swift test --filter ProviderCatalogTests
```

Expected: compilation fails because the new provider cases and catalog types do
not exist.

- [x] **Step 3: Add stable cases and catalog value types**

Add these cases to `Provider` without changing existing raw values:

```swift
case minimax
case githubCopilot = "github-copilot"
case antigravity
case factory
case openCodeGo = "opencode-go"
case openCodeZen = "opencode-zen"
case superGrok = "supergrok"
```

Create `ProviderCatalog.swift` with:

```swift
import Foundation

public struct ProviderColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
}

public enum ProviderReleaseState: Equatable, Sendable {
    case qualified
    case experimental
    case unavailable
}

public enum ProviderConnectionStrategy: Equatable, Sendable {
    case isolatedWebSession
    case browserOAuth
    case deviceOAuth
    case apiKey
    case isolatedCLIProfile(executable: String)
}

public enum ProviderDashboardStrategy: Equatable, Sendable {
    case embedded(URL)
    case nativeDetail(externalURL: URL?)
    case external(URL)
}

public struct ProviderDefinition: Identifiable, Equatable, Sendable {
    public let provider: Provider
    public let displayName: String
    public let connectionDetail: String
    public let systemImage: String
    public let color: ProviderColor
    public let releaseState: ProviderReleaseState
    public let connectionStrategy: ProviderConnectionStrategy
    public let dashboardStrategy: ProviderDashboardStrategy

    public var id: Provider { provider }
}

public struct ProviderCatalog: Sendable {
    public static let live = ProviderCatalog(definitions: [
        ProviderDefinition(
            provider: .claude,
            displayName: "Claude",
            connectionDetail: "Isolated browser session",
            systemImage: "globe",
            color: ProviderColor(red: 0.86, green: 0.36, blue: 0.18),
            releaseState: .qualified,
            connectionStrategy: .isolatedWebSession,
            dashboardStrategy: .embedded(
                URL(string: "https://claude.ai/settings/usage")!
            )
        ),
        ProviderDefinition(
            provider: .codex,
            displayName: "Codex",
            connectionDetail: "ChatGPT OAuth in your browser",
            systemImage: "terminal",
            color: ProviderColor(red: 0.15, green: 0.68, blue: 0.55),
            releaseState: .qualified,
            connectionStrategy: .browserOAuth,
            dashboardStrategy: .nativeDetail(
                externalURL: URL(
                    string: "https://chatgpt.com/codex/settings/usage"
                )!
            )
        ),
        ProviderDefinition(
            provider: .kimi,
            displayName: "Kimi",
            connectionDetail: "Device authorization",
            systemImage: "moon.stars",
            color: ProviderColor(red: 0.33, green: 0.45, blue: 0.92),
            releaseState: .qualified,
            connectionStrategy: .deviceOAuth,
            dashboardStrategy: .nativeDetail(
                externalURL: URL(string: "https://www.kimi.com/code/console")!
            )
        ),
        ProviderDefinition(
            provider: .minimax,
            displayName: "MiniMax",
            connectionDetail: "Token Plan API key",
            systemImage: "waveform.path.ecg",
            color: ProviderColor(red: 0.91, green: 0.28, blue: 0.38),
            releaseState: .unavailable,
            connectionStrategy: .apiKey,
            dashboardStrategy: .nativeDetail(
                externalURL: URL(string: "https://www.minimax.io/platform")!
            )
        ),
        ProviderDefinition(
            provider: .githubCopilot,
            displayName: "GitHub Copilot",
            connectionDetail: "GitHub device OAuth",
            systemImage: "chevron.left.forwardslash.chevron.right",
            color: ProviderColor(red: 0.50, green: 0.36, blue: 0.88),
            releaseState: .unavailable,
            connectionStrategy: .deviceOAuth,
            dashboardStrategy: .nativeDetail(
                externalURL: URL(
                    string: "https://github.com/settings/billing/summary"
                )!
            )
        ),
        ProviderDefinition(
            provider: .antigravity,
            displayName: "Antigravity",
            connectionDetail: "Isolated AGY CLI profile",
            systemImage: "sparkles",
            color: ProviderColor(red: 0.25, green: 0.55, blue: 0.95),
            releaseState: .unavailable,
            connectionStrategy: .isolatedCLIProfile(executable: "agy"),
            dashboardStrategy: .nativeDetail(
                externalURL: URL(string: "https://antigravity.google/")!
            )
        ),
        ProviderDefinition(
            provider: .factory,
            displayName: "Factory",
            connectionDetail: "Isolated Droid profile",
            systemImage: "building.2",
            color: ProviderColor(red: 0.89, green: 0.55, blue: 0.18),
            releaseState: .unavailable,
            connectionStrategy: .isolatedCLIProfile(executable: "droid"),
            dashboardStrategy: .nativeDetail(
                externalURL: URL(string: "https://app.factory.ai/settings/usage")!
            )
        ),
        ProviderDefinition(
            provider: .openCodeGo,
            displayName: "OpenCode Go",
            connectionDetail: "Go API key and workspace",
            systemImage: "arrow.right.circle",
            color: ProviderColor(red: 0.18, green: 0.70, blue: 0.72),
            releaseState: .unavailable,
            connectionStrategy: .apiKey,
            dashboardStrategy: .embedded(
                URL(string: "https://opencode.ai/go")!
            )
        ),
        ProviderDefinition(
            provider: .openCodeZen,
            displayName: "OpenCode Zen",
            connectionDetail: "Zen API key and workspace",
            systemImage: "circle.hexagongrid",
            color: ProviderColor(red: 0.51, green: 0.61, blue: 0.29),
            releaseState: .unavailable,
            connectionStrategy: .apiKey,
            dashboardStrategy: .embedded(
                URL(string: "https://opencode.ai/zen")!
            )
        ),
        ProviderDefinition(
            provider: .superGrok,
            displayName: "SuperGrok",
            connectionDetail: "Grok device OAuth",
            systemImage: "xmark.circle",
            color: ProviderColor(red: 0.36, green: 0.36, blue: 0.38),
            releaseState: .unavailable,
            connectionStrategy: .deviceOAuth,
            dashboardStrategy: .embedded(
                URL(string: "https://grok.com/usage")!
            )
        ),
    ])

    public let all: [ProviderDefinition]

    public init(definitions: [ProviderDefinition]) {
        precondition(Set(definitions.map(\.provider)).count == definitions.count)
        all = definitions
    }

    public func definition(for provider: Provider) -> ProviderDefinition? {
        all.first { $0.provider == provider }
    }

    public func visibleDefinitions(
        isDevelopmentBuild: Bool
    ) -> [ProviderDefinition] {
        all.filter {
            $0.releaseState == .qualified
                || (isDevelopmentBuild && $0.releaseState == .experimental)
        }
    }

    public func sortIndex(for provider: Provider) -> Int {
        all.firstIndex { $0.provider == provider } ?? Int.max
    }
}
```

Use `.qualified` for Claude, Codex, and Kimi. Use `.experimental` for every new
provider. Define MiniMax as API-key connection with native detail and external
`https://www.minimax.io/platform` action. Use the display names from the
approved design.

- [x] **Step 4: Replace presentation switches with catalog lookups**

Change `ProviderPresentation` to wrap a `ProviderDefinition`. Change Settings
provider cards, account sections, timeline labels/colors, empty-state copy, and
`AppModel.accountComesBefore` to read `ProviderCatalog.live`.

Add a SwiftUI color conversion with no provider switch:

```swift
extension ProviderColor {
    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue)
    }
}
```

Keep the connection-content switch in `AddAccountView` for Claude, Codex, and
Kimi in this task. All new definitions are `.unavailable`, so Add Account
continues to show only the three providers that have connection
implementations. Task 7 changes MiniMax to `.experimental` in the same commit
that adds its real connection form.

- [x] **Step 5: Run focused and full tests and verify GREEN**

Run:

```bash
swift test --filter ProviderCatalogTests
swift test --filter SettingsViewTests
swift test --filter TimelinePresentationTests
swift test
```

Expected: all 150 existing tests plus the new catalog tests pass.

- [x] **Step 6: Commit the catalog**

Run `git status --short`, add only the files listed in this task, and commit:

```text
Catalog subscription providers without changing stored IDs

Add stable IDs and compile-time metadata for the approved provider set. Route
ordering, names, colors, and visibility through the catalog while preserving
the exact Claude, Codex, and Kimi JSON values and keeping unqualified adapters
out of release builds.
```

---

### Task 2: Add Timed Limit Metadata and Balances Additively

**Files:**

- Modify: `Sources/UsageMeterCore/Domain/UsageModels.swift`
- Modify: `Sources/UsageMeterCore/Presentation/UsageSummary.swift`
- Modify: `Sources/UsageMeterUI/Timeline/UsageTimelineView.swift`
- Modify: `Sources/UsageMeterUI/Timeline/UsageWindowPresentation.swift`
- Test: `Tests/UsageMeterCoreTests/UsageModelsTests.swift`
- Test: `Tests/UsageMeterCoreTests/UsageSummaryTests.swift`
- Test: `Tests/UsageMeterUITests/TimelinePresentationTests.swift`

**Interfaces:**

- Consumes: existing `UsageWindow` and `UsageSnapshot` persisted JSON.
- Produces: additive `.daily`, `.monthly`, `.custom` window kinds,
  `UsageWindow.label`, `UsageWindow.reportedStartAt`, `UsageBalance`, and
  `UsageSnapshot.balances`.

- [x] **Step 1: Write failing additive-decoding and validation tests**

Add to `UsageModelsTests.swift`:

```swift
@Test
func legacySnapshotDecodesWithoutNewOptionalFields() throws {
    let accountID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let data = Data("""
    {
      "accountID":"\(accountID.uuidString)",
      "fetchedAt":0,
      "windows":[{
        "id":"weekly",
        "kind":"weekly",
        "duration":604800,
        "resetAt":604800,
        "consumedFraction":0.25
      }]
    }
    """.utf8)

    let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: data)

    #expect(snapshot.windows.count == 1)
    #expect(snapshot.windows[0].label == nil)
    #expect(snapshot.balances.isEmpty)
}

@Test
func explicitWindowStartWinsOverDurationDerivedStart() throws {
    let reset = Date(timeIntervalSince1970: 10_000)
    let reportedStart = Date(timeIntervalSince1970: 1_000)
    let window = try #require(UsageWindow(
        id: "month",
        kind: .monthly,
        label: "Standard",
        duration: 2_000,
        reportedStartAt: reportedStart,
        resetAt: reset,
        consumedFraction: 0.4
    ))

    #expect(window.startAt == reportedStart)
    #expect(window.remainingFraction == 0.6)
}

@Test
func balanceRejectsInvalidAmountsAndLabels() {
    #expect(UsageBalance(
        id: "credits",
        label: "",
        remainingAmount: 10,
        unit: "credits"
    ) == nil)
    #expect(UsageBalance(
        id: "credits",
        label: "Credits",
        remainingAmount: .infinity,
        unit: "credits"
    ) == nil)
}
```

Add a `UsageSummaryTests` case proving balances do not affect
`tightestWindow`. Add timeline presentation tests proving absent kinds produce
no section and present kinds sort short, daily, weekly, monthly, custom.

- [x] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter UsageModelsTests
swift test --filter TimelinePresentationTests
```

Expected: compilation fails for the new API.

- [x] **Step 3: Implement additive domain values**

Extend `UsageWindowKind`:

```swift
case daily
case monthly
case custom
```

Add `label: String?` and `reportedStartAt: Date?` to `UsageWindow`, with
defaulted initializer arguments. Decode both through `decodeIfPresent`. Keep
`startAt` as:

```swift
public var startAt: Date {
    reportedStartAt ?? resetAt.addingTimeInterval(-duration)
}
```

Add:

```swift
public struct UsageBalance: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let remainingAmount: Double
    public let unit: String
    public let cycleEndsAt: Date?

    public init?(
        id: String,
        label: String,
        remainingAmount: Double,
        unit: String,
        cycleEndsAt: Date? = nil
    ) {
        let id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !id.isEmpty,
            !label.isEmpty,
            remainingAmount.isFinite,
            !unit.isEmpty
        else {
            return nil
        }
        self.id = id
        self.label = label
        self.remainingAmount = remainingAmount
        self.unit = unit
        self.cycleEndsAt = cycleEndsAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let balance = UsageBalance(
            id: try container.decode(String.self, forKey: .id),
            label: try container.decode(String.self, forKey: .label),
            remainingAmount: try container.decode(
                Double.self,
                forKey: .remainingAmount
            ),
            unit: try container.decode(String.self, forKey: .unit),
            cycleEndsAt: try container.decodeIfPresent(
                Date.self,
                forKey: .cycleEndsAt
            )
        ) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Usage balance contains invalid values."
                )
            )
        }
        self = balance
    }
}
```

Add `balances: [UsageBalance] = []` to `UsageSnapshot` and a custom decoder:

```swift
balances = try container.decodeIfPresent(
    [UsageBalance].self,
    forKey: .balances
) ?? []
```

- [x] **Step 4: Generalize section discovery**

Replace the two fixed `shortAccounts`/`weeklyAccounts` branches with an ordered
array of present kinds. Keep the approved ten-hour short axis and fourteen-day
weekly axis. Give daily a two-day axis, monthly a sixty-two-day axis, and
custom an axis of twice the longest row duration. Add compact balance rows
after timed sections; they show label and formatted amount and never use a
timeline axis.

- [x] **Step 5: Run focused and full tests and verify GREEN**

```bash
swift test --filter UsageModelsTests
swift test --filter UsageSummaryTests
swift test --filter TimelinePresentationTests
swift test
```

- [x] **Step 6: Commit normalized limits**

Commit only the files in this task with:

```text
Normalize additional windows and provider balances

Extend persisted snapshots additively with optional labels, reported starts,
new duration groups, and validated balances. Keep legacy snapshots decodable
and preserve the approved aligned axes for five-hour and weekly windows.
```

---

### Task 3: Let Adapters Own Typed Credential Payloads

**Files:**

- Modify: `Sources/UsageMeterCore/Credentials/CredentialStore.swift`
- Modify: `Sources/UsageMeterCore/Credentials/KeychainCredentialStore.swift`
- Test: `Tests/UsageMeterCoreTests/CredentialStoreContractTests.swift`
- Modify: `Tests/UsageMeterUITests/TestSupport.swift`

**Interfaces:**

- Consumes: existing `ProviderCredential` JSON values and Keychain addressing.
- Produces: raw `CredentialStore` requirements plus
  `save(_:for:)`, `load(_:for:)`, and legacy `load(for:)` typed conveniences.

- [x] **Step 1: Write failing raw-store compatibility tests**

In `CredentialStoreContractTests.swift`, change the test in-memory store to
capture raw `Data`, then add:

```swift
private struct ExampleAPIKey: Codable, Equatable, Sendable {
    let value: String
}

@Test
func legacyCredentialKeepsItsExistingJSONPayload() async throws {
    let accountID = UUID()
    let store = TestRawCredentialStore()
    let credential = ProviderCredential.codex(
        OAuthCredential(
            accessToken: "access",
            refreshToken: "refresh",
            accountID: "provider-user"
        )
    )

    try await store.save(credential, for: accountID)

    let raw = try #require(await store.loadData(for: accountID))
    #expect(raw == JSONEncoder().encode(credential))
    #expect(try await store.load(for: accountID) == credential)
}

@Test
func providerOwnedCredentialRoundTripsWithoutNewEnumCase() async throws {
    let accountID = UUID()
    let store = TestRawCredentialStore()
    let credential = ExampleAPIKey(value: "secret")

    try await store.save(credential, for: accountID)

    #expect(
        try await store.load(ExampleAPIKey.self, for: accountID)
            == credential
    )
}
```

The production breaks caught are changed legacy bytes or a store API that
forces every provider secret into `ProviderCredential`.

- [x] **Step 2: Run tests and verify RED**

```bash
swift test --filter CredentialStoreContractTests
```

Expected: compilation fails because raw methods and generic typed methods do
not exist.

- [x] **Step 3: Change the store protocol to raw data**

Replace requirements with:

```swift
public protocol CredentialStore: Sendable {
    func saveData(_ data: Data, for accountID: UUID) async throws
    func loadData(for accountID: UUID) async throws -> Data?
    func delete(for accountID: UUID) async throws
}
```

Add:

```swift
public extension CredentialStore {
    func save<Value: Encodable & Sendable>(
        _ value: Value,
        for accountID: UUID
    ) async throws {
        try await saveData(JSONEncoder().encode(value), for: accountID)
    }

    func load<Value: Decodable & Sendable>(
        _ type: Value.Type,
        for accountID: UUID
    ) async throws -> Value? {
        guard let data = try await loadData(for: accountID) else {
            return nil
        }
        return try JSONDecoder().decode(type, from: data)
    }

    func load(for accountID: UUID) async throws -> ProviderCredential? {
        try await load(ProviderCredential.self, for: accountID)
    }
}
```

Implement `saveData` and `loadData` in `KeychainCredentialStore` without
changing `service`, `kSecAttrAccount`, accessibility, or synchronizability.
Update both test stores.

- [x] **Step 4: Run focused and full tests and verify GREEN**

```bash
swift test --filter CredentialStoreContractTests
swift test --filter AppModelTests
swift test
```

- [x] **Step 5: Commit typed credential storage**

Commit with:

```text
Let provider adapters own typed credential payloads

Store raw Keychain data behind generic Codable helpers so new provider
credentials do not expand the legacy central enum. Preserve the exact existing
JSON payloads, service name, and account UUID addressing.
```

---

### Task 4: Delegate Account Refresh and Cleanup to Adapters

**Files:**

- Create: `Sources/UsageMeterCore/Providers/ProviderAccountAdapter.swift`
- Create: `Sources/UsageMeterCore/Providers/CredentialUsageAdapter.swift`
- Modify: `Sources/UsageMeterUI/Settings/ClaudeWebAccountUsageClient.swift`
- Modify: `Sources/UsageMeterUI/AppModel.swift`
- Modify: `Sources/AgenticUsageMeter/AgenticUsageMeterApp.swift`
- Modify: `Tests/UsageMeterUITests/TestSupport.swift`
- Test: `Tests/UsageMeterUITests/AppModelTests.swift`
- Test: `Tests/UsageMeterUITests/AccountConnectionTests.swift`

**Interfaces:**

- Consumes: `CredentialStore`, `UsageProviderClient`,
  `ClaudeAccountUsageFetching`, and `AccountRefresher`.
- Produces: `ProviderAccountAdapter`, `CredentialUsageAdapter`,
  adapter-driven `AppModel`, and persisted-before-validation connection
  behavior.

- [ ] **Step 1: Write failing adapter-delegation tests**

Add this test adapter to `TestSupport.swift`:

```swift
actor TestProviderAccountAdapter: ProviderAccountAdapter {
    let provider: Provider
    private let result: Result<UsageSnapshot, any Error>
    private(set) var fetchedAccountIDs: [UUID] = []
    private(set) var removedAccountIDs: [UUID] = []

    init(
        provider: Provider,
        result: Result<UsageSnapshot, any Error> = .failure(
            ProviderClientError.temporaryFailure
        )
    ) {
        self.provider = provider
        self.result = result
    }

    func fetchUsage(
        for account: SubscriptionAccount,
        now _: Date
    ) throws -> UsageSnapshot {
        fetchedAccountIDs.append(account.id)
        return try result.get()
    }

    func removeAuthentication(
        for account: SubscriptionAccount
    ) {
        removedAccountIDs.append(account.id)
    }
}
```

Then add:

```swift
@Test
func refreshUsesTheAccountsAdapterWithoutProviderBranch() async throws {
    let account = SubscriptionAccount(
        provider: .minimax,
        displayName: "MiniMax",
        displayOrder: 0
    )
    let snapshot = UsageSnapshot(
        accountID: account.id,
        fetchedAt: Date(timeIntervalSince1970: 2_000_000_000),
        windows: []
    )
    let adapter = TestProviderAccountAdapter(
        provider: .minimax,
        result: .success(snapshot)
    )
    let model = makeAppModel(
        state: state(containing: account),
        adapters: [adapter]
    )

    await model.start()

    #expect(await adapter.fetchedAccountIDs == [account.id])
    #expect(model.accounts.first?.snapshot == snapshot)
}

@Test
func removingAccountDelegatesAuthenticationCleanup() async throws {
    let account = SubscriptionAccount(
        provider: .minimax,
        displayName: "MiniMax",
        displayOrder: 0
    )
    let adapter = TestProviderAccountAdapter(provider: .minimax)
    let model = makeAppModel(
        state: state(containing: account),
        adapters: [adapter]
    )
    await model.start()

    try await model.removeAccount(id: account.id)

    #expect(await adapter.removedAccountIDs == [account.id])
}
```

Also replace the old `failedConnectionLeavesNoCredentialOrMetadata` assertion
with:

```swift
@Test
func failedFirstUsageKeepsSuccessfulAuthenticationAndAccount() async throws {
    let reference = Date(timeIntervalSince1970: 2_000_000_000)
    let account = SubscriptionAccount(
        provider: .codex,
        displayName: "Work",
        displayOrder: 0
    )
    let stateStore = TestAppStateStore(state: .empty)
    let credentials = TestCredentialStore()
    let adapter = TestProviderAccountAdapter(
        provider: .codex,
        result: .failure(ProviderClientError.temporaryFailure)
    )
    let model = AppModel(
        stateStore: stateStore,
        credentialStore: credentials,
        adapters: [adapter],
        now: { reference }
    )
    await model.start()
    let credential = ProviderCredential.codex(
        OAuthCredential(
            accessToken: "access",
            accountID: "provider-account"
        )
    )

    try await model.connectAccount(account, credential: credential)

    #expect(model.accounts.map(\.account) == [account])
    #expect(model.accounts[0].snapshot == nil)
    #expect(model.accounts[0].error == .temporarilyUnavailable)
    #expect(await credentials.load(for: account.id) == credential)
    #expect(await stateStore.state.accounts == [account])
}
```

The break caught is the existing validate-before-save behavior.

- [ ] **Step 2: Run tests and verify RED**

```bash
swift test --filter AppModelTests
swift test --filter AccountConnectionTests
```

Expected: compilation fails because `ProviderAccountAdapter` and adapter-based
test construction do not exist; the connection behavior test fails against the
current all-or-nothing flow.

- [ ] **Step 3: Add the adapter interface**

Create:

```swift
public protocol ProviderAccountAdapter: Sendable {
    var provider: Provider { get }
    var canRecoverAuthenticationWithoutReconnect: Bool { get }

    func fetchUsage(
        for account: SubscriptionAccount,
        now: Date
    ) async throws -> UsageSnapshot

    func removeAuthentication(
        for account: SubscriptionAccount
    ) async throws
}

public extension ProviderAccountAdapter {
    var canRecoverAuthenticationWithoutReconnect: Bool { false }
}
```

Define:

```swift
public typealias ProviderCredentialRefresh =
    @Sendable (
        UUID,
        ProviderCredential
    ) async throws -> ProviderCredential

public struct CredentialUsageAdapter: ProviderAccountAdapter {
    public let provider: Provider
    private let credentialStore: any CredentialStore
    private let client: any UsageProviderClient
    private let refreshCredential: ProviderCredentialRefresh?

    public init(
        provider: Provider,
        credentialStore: any CredentialStore,
        client: any UsageProviderClient,
        refreshCredential: ProviderCredentialRefresh? = nil
    ) {
        precondition(client.provider == provider)
        self.provider = provider
        self.credentialStore = credentialStore
        self.client = client
        self.refreshCredential = refreshCredential
    }

    public func fetchUsage(
        for account: SubscriptionAccount,
        now: Date
    ) async throws -> UsageSnapshot {
        guard account.provider == provider else {
            throw ProviderClientError.credentialMismatch
        }
        guard var credential = try await credentialStore.load(
            for: account.id
        ) else {
            throw ProviderClientError.reauthenticationRequired
        }

        var didRefreshCredential = false
        if
            let refreshCredential,
            credential.isExpired(at: now)
        {
            credential = try await refreshCredential(
                account.id,
                credential
            )
            try await credentialStore.save(
                credential,
                for: account.id
            )
            didRefreshCredential = true
        }

        do {
            return try await client.fetchUsage(
                accountID: account.id,
                credential: credential,
                now: now
            )
        } catch let error as ProviderClientError {
            guard
                error == .reauthenticationRequired,
                !didRefreshCredential,
                let refreshCredential
            else {
                throw error
            }

            credential = try await refreshCredential(
                account.id,
                credential
            )
            try await credentialStore.save(
                credential,
                for: account.id
            )
            return try await client.fetchUsage(
                accountID: account.id,
                credential: credential,
                now: now
            )
        }
    }

    public func removeAuthentication(
        for account: SubscriptionAccount
    ) async throws {
        try await credentialStore.delete(for: account.id)
    }
}
```

Move the existing private credential-expiry helper into this file unchanged.
The adapter loads legacy `ProviderCredential`, refreshes expired tokens,
retries one authentication failure after refresh, saves token rotation, and
deletes the account's Keychain record.

Make `ClaudeWebAccountUsageClient` conform. It reads profile and organization
IDs from `SubscriptionAccount`, delegates to `ClaudeWebUsageClient`, and
deletes the profile. Set its recovery flag to `true` to retain the already
qualified transient-cookie recovery behavior.

- [ ] **Step 4: Refactor `AppModel` to the adapter map**

Change initialization to:

```swift
public init(
    stateStore: any AppStatePersisting,
    credentialStore: any CredentialStore,
    adapters: [any ProviderAccountAdapter],
    isSampleData: Bool = false,
    now: @escaping @Sendable () -> Date = { Date() }
)
```

Build `adaptersByProvider`. In `refreshAccount`, look up one adapter and call:

```swift
outcome = try await refresher.refresh(
    retryingAuthentication:
        adapter.canRecoverAuthenticationWithoutReconnect
) {
    do {
        return try await adapter.fetchUsage(for: account, now: now())
    } catch let error as ProviderClientError {
        throw refreshFailure(for: error)
    }
}
```

In `removeAccount`, call `adapter.removeAuthentication(for:)`. Delete
`clientsByProvider`, `credentialRefreshers`, `claudeClient`,
`claudeProfileRemover`, and their provider branches.

- [ ] **Step 5: Persist connection state before fetching usage**

Change generic connection to:

```swift
public func connectAccount<Credential: Codable & Sendable>(
    _ account: SubscriptionAccount,
    credential: Credential
) async throws {
    guard !accounts.contains(where: { $0.id == account.id }) else {
        throw AppModelError.accountAlreadyExists
    }
    guard adaptersByProvider[account.provider] != nil else {
        throw AppModelError.providerUnavailable
    }

    try await credentialStore.save(credential, for: account.id)
    var nextState = persistedState
    nextState.accounts.append(account)
    nextState.refreshStates[account.id] = .initial
    do {
        try await stateStore.save(nextState)
    } catch {
        try? await credentialStore.delete(for: account.id)
        throw error
    }

    let now = now
    persistedState = nextState
    refreshers[account.id] = AccountRefresher(now: { now() })
    accounts.append(
        AccountViewState(account: account, snapshot: nil)
    )
    accounts.sort(by: viewStateComesBefore)
    await refreshAccount(id: account.id)
}
```

If state persistence fails after the credential save, delete that credential
because no account exists to own it. For reconnect, retain the old raw
credential long enough to restore it only if local state persistence fails;
then clear the refresher authentication stop and fetch, retaining last-good
usage on provider failure.

Change Claude connection to persist the profile/account when organization
identity has been discovered. Accept an optional already-fetched snapshot so a
successful validation avoids a duplicate contact, while a failed validation
still leaves a reconnectable account.

- [ ] **Step 6: Rewire the live environment**

Construct:

```swift
let credentialStore = KeychainCredentialStore()
let adapters: [any ProviderAccountAdapter] = [
    ClaudeWebAccountUsageClient(),
    CredentialUsageAdapter(
        provider: .codex,
        credentialStore: credentialStore,
        client: CodexUsageClient()
    ),
    CredentialUsageAdapter(
        provider: .kimi,
        credentialStore: credentialStore,
        client: KimiUsageClient(),
        refreshCredential: refreshKimiCredential
    ),
]
```

Pass the same store and adapters to `AppModel`.

- [ ] **Step 7: Run focused and full tests and verify GREEN**

```bash
swift test --filter AppModelTests
swift test --filter AccountConnectionTests
swift test --filter ClaudeConnectionQualificationTests
swift test
```

- [ ] **Step 8: Commit adapter delegation**

Commit with:

```text
Delegate account lifecycle to provider adapters

Route refresh and authentication cleanup through one account adapter boundary,
including existing Claude, Codex, and Kimi behavior. Persist successful
authentication before first usage validation and retain last-good data across
reconnect failures.
```

---

### Task 5: Bound Refresh Concurrency and Refresh After Wake

**Files:**

- Create: `Sources/UsageMeterCore/Refresh/RefreshCoordinator.swift`
- Modify: `Sources/UsageMeterUI/AppModel.swift`
- Modify: `Sources/AgenticUsageMeter/AgenticUsageMeterApp.swift`
- Test: `Tests/UsageMeterCoreTests/RefreshCoordinatorTests.swift`
- Test: `Tests/UsageMeterUITests/AppModelTests.swift`

**Interfaces:**

- Consumes: per-account `AccountRefresher`, which remains authoritative for the
  ten-minute floor and in-flight coalescing.
- Produces: `RefreshCoordinator.run(accountIDs:operation:)` and
  `AppModel.refreshAfterWake()`.

- [ ] **Step 1: Write failing bounded-concurrency tests**

Create `RefreshCoordinatorTests.swift` with an actor counter whose operation
suspends on a continuation. Start five account operations with a coordinator
limit of two. Assert the counter observes exactly two active operations before
resuming either, then resume all and assert all five complete.

Add an AppModel test that sets an account's last attempt nine minutes ago,
calls `refreshAfterWake`, and sees no adapter contact; move the clock to exactly
ten minutes, call again, and see one contact.

- [ ] **Step 2: Run tests and verify RED**

```bash
swift test --filter RefreshCoordinatorTests
swift test --filter AppModelTests
```

Expected: compilation fails because the coordinator and wake method do not
exist.

- [ ] **Step 3: Implement the coordinator**

Create an actor with an internal permit count and FIFO checked continuations:

```swift
public actor RefreshCoordinator {
    public typealias Operation =
        @Sendable (UUID) async -> Void

    private let maximumConcurrentRefreshes: Int
    private var activeRefreshes = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(maximumConcurrentRefreshes: Int = 3) {
        precondition(maximumConcurrentRefreshes > 0)
        self.maximumConcurrentRefreshes = maximumConcurrentRefreshes
    }

    public func run(
        accountIDs: [UUID],
        operation: @escaping Operation
    ) async {
        await withTaskGroup(of: Void.self) { group in
            for accountID in accountIDs {
                group.addTask {
                    await self.acquire()
                    await operation(accountID)
                    await self.release()
                }
            }
        }
    }
}
```

Implement `acquire` and `release` so a released permit resumes the oldest
waiter without allowing the active count to exceed the limit.

- [ ] **Step 4: Use one coordinator for automatic, manual-all, and wake demand**

Give `AppModel` one injected coordinator. Make `refreshAllAccounts` call
`coordinator.run` with current account IDs. `refreshAccount` still goes through
the account's `AccountRefresher`, so every demand observes the ten-minute floor.
`refreshAfterWake` calls `refreshAllAccounts`.

In `AgenticUsageMeterApp`, subscribe to
`NSWorkspace.didWakeNotification` with `NotificationCenter.notifications` in a
scene task and call `model.refreshAfterWake()`. Cancel naturally with the
SwiftUI task.

- [ ] **Step 5: Run focused and full tests and verify GREEN**

```bash
swift test --filter RefreshCoordinatorTests
swift test --filter AccountRefresherTests
swift test --filter AppModelTests
swift test
```

- [ ] **Step 6: Commit refresh coordination**

Commit with:

```text
Bound account refreshes and recheck after wake

Keep the existing per-account ten-minute gate and coalescing while limiting
parallel provider contacts across accounts. Reuse the same path for timer,
manual-all, and macOS wake demand.
```

---

### Task 6: Add Account-Scoped Dashboard Windows

**Files:**

- Modify: `Package.swift`
- Create: `Sources/UsageMeterWeb/AccountWebProfileStore.swift`
- Modify: `Sources/UsageMeterClaudeWeb/ClaudeWebProfileStore.swift`
- Create: `Sources/UsageMeterUI/Dashboard/AccountDashboardPresenter.swift`
- Create: `Sources/UsageMeterUI/Dashboard/AccountDashboardView.swift`
- Modify: `Sources/UsageMeterUI/Settings/AccountListView.swift`
- Modify: `Sources/UsageMeterUI/Settings/SettingsView.swift`
- Test: `Tests/UsageMeterWebTests/AccountWebProfileStoreTests.swift`
- Test: `Tests/UsageMeterUITests/AccountDashboardTests.swift`
- Modify: `Tests/UsageMeterUITests/SettingsWindowPresenterTests.swift`

**Interfaces:**

- Consumes: catalog dashboard strategies and the lifecycle-safe
  `ClaudeWebProfileStore` implementation.
- Produces: `AccountWebProfileStore`, `AccountDashboardPresenter.open(_:)`,
  native/embedded dashboard views, and row-background dashboard actions.

- [ ] **Step 1: Write failing shared WebKit profile tests**

Add a `UsageMeterWebTests` target and:

```swift
@MainActor
@Test
func accountStoresRemainIndependentWhenOneIsRemoved() async throws {
    let firstID = UUID()
    let secondID = UUID()
    var first: AccountWebProfileStore? = .init(accountID: firstID)
    var second: AccountWebProfileStore? = .init(accountID: secondID)

    #expect(first?.identifier == firstID)
    #expect(second?.identifier == secondID)
    first = nil
    try await AccountWebProfileStore.remove(accountID: firstID)
    #expect(second?.identifier == secondID)
    second = nil
    try await AccountWebProfileStore.remove(accountID: secondID)
}
```

The break caught is shared cookies or deletion of a sibling account profile.

- [ ] **Step 2: Run tests and verify RED**

```bash
swift test --filter AccountWebProfileStoreTests
```

Expected: the target and type do not exist.

- [ ] **Step 3: Extract the shared profile store**

Add `UsageMeterWeb` and `UsageMeterWebTests` targets. Move the current
identifier construction and asynchronous-release wait to:

```swift
@MainActor
public final class AccountWebProfileStore {
    public let dataStore: WKWebsiteDataStore
    public var identifier: UUID? { dataStore.identifier }

    public init(accountID: UUID) {
        dataStore = WKWebsiteDataStore(forIdentifier: accountID)
    }

    public static func remove(accountID: UUID) async throws {
        weak var initializedStore: WKWebsiteDataStore?
        autoreleasepool {
            let store = WKWebsiteDataStore(forIdentifier: accountID)
            initializedStore = store
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while initializedStore != nil {
            guard clock.now < deadline else {
                throw AccountWebProfileStoreError.releaseTimedOut
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        try await WKWebsiteDataStore.remove(forIdentifier: accountID)
    }
}

private enum AccountWebProfileStoreError: Error {
    case releaseTimedOut
}
```

Make `ClaudeWebProfileStore` a wrapper that passes its existing `profileID` as
`accountID`. Keep all Claude tests green.

- [ ] **Step 4: Write failing dashboard routing tests**

Define:

```swift
struct AccountDashboardRoute: Equatable {
    let accountID: UUID
    let strategy: ProviderDashboardStrategy

    init(
        account: SubscriptionAccount,
        strategy: ProviderDashboardStrategy
    ) {
        accountID = account.id
        self.strategy = strategy
    }
}

enum AccountRowAction: Equatable {
    case rename
    case refresh
    case reconnect
    case openDashboard

    static func resolved(
        clickedName: Bool,
        explicitControl: AccountRowAction?
    ) -> AccountRowAction {
        if let explicitControl {
            return explicitControl
        }
        return clickedName ? .rename : .openDashboard
    }
}
```

Test `AccountDashboardRoute`:

```swift
@Test
func embeddedDashboardUsesTheAccountAsItsProfileID() throws {
    let account = SubscriptionAccount(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        provider: .minimax,
        displayName: "MiniMax",
        displayOrder: 0
    )
    let definition = try #require(
        ProviderCatalog.live.definition(for: .minimax)
    )

    let route = AccountDashboardRoute(
        account: account,
        strategy: definition.dashboardStrategy
    )

    #expect(route.accountID == account.id)
}
```

Add interaction tests proving name click returns `.rename`, explicit control
clicks return their control action, and a background click returns
`.openDashboard`.

- [ ] **Step 5: Implement dashboard windows and row action**

`AccountDashboardPresenter` owns `[UUID: NSWindowController]`, reuses an
existing window for repeated opens, and builds:

- embedded: `WKWebViewConfiguration.websiteDataStore` from the account profile;
- native detail: latest timed limits, balances, refresh state, and external
  dashboard button;
- external: `NSWorkspace.open`.

Put dashboard click handling on the row's noninteractive background. Keep the
name as an explicit rename button and keep menu/reconnect/drag actions
unchanged.

Extend the existing window activation helper to reference-count visible
Settings/dashboard windows. Set `.regular` when the count changes from zero to
one and `.accessory` when it changes from one to zero, keeping the app in
Cmd-Tab while any regular window is open.

- [ ] **Step 6: Run focused and full tests and verify GREEN**

```bash
swift test --filter AccountWebProfileStoreTests
swift test --filter AccountDashboardTests
swift test --filter ClaudeWebProfileStoreTests
swift test --filter SettingsWindowPresenterTests
swift test
```

- [ ] **Step 7: Commit dashboard isolation**

Commit with:

```text
Open account dashboards in isolated web profiles

Generalize the proven Claude WebKit store lifecycle, route account rows to
embedded or native dashboards, and retain regular app activation while a
dashboard or Settings window is visible.
```

---

### Task 7: Implement the MiniMax Token Plan Adapter

**Files:**

- Create: `Sources/UsageMeterCore/Providers/MiniMax/MiniMaxCredential.swift`
- Create: `Sources/UsageMeterCore/Providers/MiniMax/MiniMaxUsageDecoder.swift`
- Create: `Sources/UsageMeterCore/Providers/MiniMax/MiniMaxUsageAdapter.swift`
- Create: `Sources/UsageMeterUI/Settings/APIKeyConnectionView.swift`
- Modify: `Sources/UsageMeterUI/Settings/SettingsView.swift`
- Modify: `Sources/AgenticUsageMeter/AgenticUsageMeterApp.swift`
- Create: `Tests/UsageMeterCoreTests/Fixtures/minimax-usage.json`
- Test: `Tests/UsageMeterCoreTests/MiniMaxUsageDecoderTests.swift`
- Test: `Tests/UsageMeterCoreTests/MiniMaxUsageAdapterTests.swift`
- Test: `Tests/UsageMeterUITests/SettingsViewTests.swift`
- Create: `THIRD_PARTY_NOTICES.md`
- Modify: `docs/provider-qualification.md`

**Interfaces:**

- Consumes: generic typed `CredentialStore`, `ProviderAccountAdapter`,
  `UsageWindow`, and catalog connection/dashboard metadata.
- Produces: `MiniMaxCredential`, `MiniMaxUsageDecoder`,
  `MiniMaxUsageAdapter`, and a working API-key Add Account form.

- [ ] **Step 1: Add the sanitized fixture and failing decoder tests**

Create a fixture with one zero-capacity modality row and this text row:

```json
{
  "start_time": 1774587600000,
  "end_time": 1774605600000,
  "current_interval_total_count": 1500,
  "current_interval_usage_count": 750,
  "model_name": "MiniMax-M*",
  "current_weekly_total_count": 15000,
  "current_weekly_usage_count": 6000,
  "weekly_start_time": 1774224000000,
  "weekly_end_time": 1774828800000
}
```

Wrap it in `model_remains` and a zero `base_resp.status_code`.

Add:

```swift
@Test
func remainingCountsBecomeConsumedFractions() throws {
    let accountID = UUID()
    let fetchedAt = Date(timeIntervalSince1970: 1_774_587_600)
    let snapshot = try MiniMaxUsageDecoder().decode(
        usageFixture(named: "minimax-usage"),
        accountID: accountID,
        fetchedAt: fetchedAt
    )

    #expect(snapshot.windows.map(\.kind) == [.short, .weekly])
    #expect(snapshot.windows[0].consumedFraction == 0.5)
    #expect(snapshot.windows[1].consumedFraction == 0.6)
    #expect(snapshot.windows[0].duration == 18_000)
    #expect(snapshot.windows[1].duration == 604_800)
    #expect(
        snapshot.windows[0].resetAt
            == Date(timeIntervalSince1970: 1_774_605_600)
    )
}

@Test
func subOnePercentConsumptionIsNotRoundedAway() throws {
    let data = Data("""
    {
      "model_remains": [{
        "end_time": 1774605600000,
        "current_interval_total_count": 1500,
        "current_interval_usage_count": 1494,
        "model_name": "MiniMax-M*"
      }],
      "base_resp": {"status_code": 0, "status_msg": "success"}
    }
    """.utf8)

    let snapshot = try MiniMaxUsageDecoder().decode(
        data,
        accountID: UUID(),
        fetchedAt: Date(timeIntervalSince1970: 1_774_587_600)
    )

    #expect(snapshot.windows.count == 1)
    #expect(snapshot.windows[0].consumedFraction == 0.004)
}

@Test
func nonzeroProviderStatusIsRejected() async {
    let data = Data("""
    {
      "model_remains": [],
      "base_resp": {"status_code": 1004, "status_msg": "invalid token"}
    }
    """.utf8)

    #expect(throws: ProviderClientError.unsupportedResponse) {
        _ = try MiniMaxUsageDecoder().decode(
            data,
            accountID: UUID(),
            fetchedAt: Date(timeIntervalSince1970: 1_774_587_600)
        )
    }
}
```

The production break caught is interpreting the misleading
`current_*_usage_count` fields as used instead of remaining.

- [ ] **Step 2: Run decoder tests and verify RED**

```bash
swift test --filter MiniMaxUsageDecoderTests
```

Expected: compilation fails because the decoder does not exist.

- [ ] **Step 3: Implement the MiniMax decoder**

Create:

```swift
public struct MiniMaxCredential: Codable, Equatable, Sendable {
    public let apiKey: String

    public init?(apiKey: String) {
        let value = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        self.apiKey = value
    }
}
```

Decode flexible integers from number or numeric string. Treat
`currentIntervalUsageCount` and `currentWeeklyUsageCount` as remaining counts.
Clamp remaining into `0...total` and calculate:

```swift
let consumedFraction =
    Double(total - clampedRemaining) / Double(total)
```

Ignore zero-capacity rows. Select the useful row with highest consumed
fraction, then highest capacity, then stable model name. Build a short window
only when interval quota is present and a weekly window only when weekly quota
is present. Convert millisecond times by dividing by 1,000. Reject responses
with no useful window or nonzero provider status as
`.unsupportedResponse`.

Adapt this narrow response behavior from the pinned OpenCode Bar source and add
its MIT copyright/license notice to `THIRD_PARTY_NOTICES.md`.

- [ ] **Step 4: Write failing HTTP adapter tests**

Use the existing recording transport pattern. Add:

```swift
@Test
func adapterLoadsItsTypedKeyAndRequestsCodingPlanRemains() async throws {
    let account = SubscriptionAccount(
        provider: .minimax,
        displayName: "MiniMax",
        displayOrder: 0
    )
    let store = TestRawCredentialStore()
    try await store.save(
        try #require(MiniMaxCredential(apiKey: "plan-key")),
        for: account.id
    )
    let transport = MiniMaxRecordingTransport(
        response: HTTPResponse(
            data: try usageFixture(named: "minimax-usage"),
            statusCode: 200,
            headers: [:]
        )
    )
    let adapter = MiniMaxUsageAdapter(
        credentialStore: store,
        transport: transport
    )

    let snapshot = try await adapter.fetchUsage(
        for: account,
        now: Date(timeIntervalSince1970: 1_774_587_600)
    )

    #expect(snapshot.accountID == account.id)
    let request = try #require(await transport.lastRequest)
    #expect(request.httpMethod == "GET")
    #expect(
        request.url?.absoluteString
            == "https://api.minimax.io/v1/api/openplatform/coding_plan/remains"
    )
    #expect(
        request.value(forHTTPHeaderField: "Authorization")
            == "Bearer plan-key"
    )
}
```

Add table cases for 401/403 -> `.reauthenticationRequired`, 429 with
`Retry-After` -> `.retryAfter`, and 500 -> `.temporaryFailure`. Add a missing or
wrong typed credential test that makes no request.

- [ ] **Step 5: Run adapter tests and verify RED**

```bash
swift test --filter MiniMaxUsageAdapterTests
```

Expected: compilation fails because the adapter does not exist.

- [ ] **Step 6: Implement the adapter**

`MiniMaxUsageAdapter` conforms to `ProviderAccountAdapter`, loads
`MiniMaxCredential.self`, validates provider equality, sends the GET request,
maps status codes identically to existing clients, decodes the snapshot, and
deletes only that account's credential.

- [ ] **Step 7: Write failing API-key form behavior tests**

Add Settings tests on a value-type `APIKeyConnectionForm`:

```swift
@Test
func apiKeyFormTrimsNameButPreservesSecretBytes() {
    let form = APIKeyConnectionForm(
        displayName: "  MiniMax Work  ",
        apiKey: " key-with-spaces "
    )

    #expect(form.validatedDisplayName == "MiniMax Work")
    #expect(form.apiKey == " key-with-spaces ")
    #expect(form.canConnect)
}
```

Define it in `APIKeyConnectionView.swift`:

```swift
struct APIKeyConnectionForm {
    var displayName: String
    var apiKey: String

    var validatedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canConnect: Bool {
        !validatedDisplayName.isEmpty
            && !apiKey.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
    }
}
```

The API-key field is a `SecureField`. Do not log, trim, or show the secret in an
error. `MiniMaxCredential` performs only its documented outer-whitespace
normalization when the user submits.

- [ ] **Step 8: Implement the form and wire the live adapter**

Replace MiniMax's temporary connection content with `APIKeyConnectionView`.
On Connect:

1. create a new account with provider `.minimax` and next provider-local order;
2. create `MiniMaxCredential`;
3. call the generic persisted-before-validation `connectAccount`;
4. dismiss even if the first usage fetch leaves a visible account error.

Add `MiniMaxUsageAdapter` to `AppEnvironment` and keep the catalog release
state `.experimental`.

- [ ] **Step 9: Run focused and full tests and verify GREEN**

```bash
swift test --filter MiniMaxUsageDecoderTests
swift test --filter MiniMaxUsageAdapterTests
swift test --filter SettingsViewTests
swift test
git diff --check
```

- [ ] **Step 10: Commit MiniMax**

Commit with:

```text
Add MiniMax Token Plan as the first extensible adapter

Decode five-hour and weekly Coding Plan remaining counts into normalized
consumption, store each API key in its account Keychain record, and expose the
provider through the catalog-driven Add Account flow. Retain experimental
release visibility pending real two-account qualification.
```

---

### Task 8: Build and Perform the MiniMax Qualification Boundary

**Files:**

- Modify: `Sources/UsageMeterProbe/UsageMeterProbe.swift`
- Modify: `Sources/UsageMeterProbe/UsageMeterProbeCommand.swift`
- Modify: `Tests/UsageMeterProbeTests/UsageMeterProbeCommandTests.swift`
- Modify: `docs/provider-qualification.md`

**Interfaces:**

- Consumes: `MiniMaxUsageAdapter` and generic Keychain credential storage.
- Produces: sanitized MiniMax probe commands and an evidence-backed
  qualification status.

- [ ] **Step 1: Write failing probe command tests**

Add parsing tests for:

```text
UsageMeterProbe minimax login --account-id 11111111-1111-1111-1111-111111111111
UsageMeterProbe minimax usage --account-id 11111111-1111-1111-1111-111111111111
UsageMeterProbe minimax delete --account-id 11111111-1111-1111-1111-111111111111
```

Assert output contains only local account UUID, normalized window kind,
remaining fraction, and reset time. It must not contain the API key,
authorization header, raw response, or authenticated email.

- [ ] **Step 2: Run tests and verify RED**

```bash
swift test --filter UsageMeterProbeCommandTests
```

- [ ] **Step 3: Implement sanitized probe commands**

`login` reads the API key from a secure terminal prompt, stores it under the
provided temporary account UUID, and performs one validation. `usage` uses the
adapter and existing Keychain record. `delete` removes the record. Errors print
only the normalized failure category.

- [ ] **Step 4: Run mechanical gates**

```bash
swift test
swift build -c release
./Scripts/assemble-app.sh
codesign --force --deep --sign - "build/Agentic Usage Meter.app"
codesign --verify --deep --strict --verbose=2 \
  "build/Agentic Usage Meter.app"
./Scripts/verify-release.sh "build/Agentic Usage Meter.app"
```

- [ ] **Step 5: Run real qualification**

Using two distinct MiniMax Token Plan accounts:

1. connect both in the signed app;
2. confirm different Keychain UUID records and independent display names;
3. confirm every offered five-hour/weekly window against the provider console;
4. quit and relaunch the signed app;
5. wait at least ten minutes from each initial request and refresh both;
6. reconnect one invalidated key while retaining its last-good snapshot;
7. open each dashboard and prove WebKit profiles are distinct;
8. delete one account and confirm the other still refreshes;
9. verify menu bar, Settings, and floating widget rendering.

Record sanitized dates, app/CLI versions, offered/missing windows, and outcomes
in `docs/provider-qualification.md`. Change MiniMax to `.qualified` only if
every item passes. If Jesse has only one MiniMax account, leave it
`.experimental` and record the outstanding second-account gate.

- [ ] **Step 6: Commit qualification evidence**

Commit only truthful evidence and any release-state change:

```text
Record MiniMax provider qualification

Document the signed-app, persistence, refresh-floor, dashboard-isolation, and
multi-account results. Expose MiniMax in release only when every qualification
gate has passed.
```
