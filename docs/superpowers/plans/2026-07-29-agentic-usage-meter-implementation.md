# Agentic Usage Meter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a distributable macOS 26 menu-bar application that displays aligned five-hour and weekly quota windows for multiple Claude, Codex, and Kimi accounts.

**Architecture:** A Swift package contains a non-UI `UsageMeterCore` library, a testable `UsageMeterUI` library, the SwiftUI menu-bar executable, and an internal provider qualification executable. Provider actors normalize observed API responses into one domain model; a per-account scheduler supplies cached state to both the menu-bar popover and floating panel.

**Tech Stack:** Swift 6.3, SwiftUI, AppKit, Swift Testing, Foundation `URLSession`, Network framework, CryptoKit, Security framework, Swift Package Manager, Developer ID signing and notarization tools.

## Global Constraints

- Target macOS 26 only; do not add backward-compatibility branches.
- Use Swift and SwiftUI. AppKit is limited to the floating panel, activation policy, and system integrations SwiftUI does not expose.
- Support multiple independent Claude, Codex, and Kimi accounts.
- Use regular-browser authentication; never embed a web view.
- Claude users run `claude setup-token` themselves and paste the token into a secure field.
- Do not use the Codex app-server.
- Enforce a hard ten-minute minimum between usage requests for each account, including manual refresh.
- Store credentials only in Keychain and normalized non-secret snapshots in Application Support.
- Send provider traffic directly from the Mac; do not add a relay, telemetry, analytics, or cloud sync.
- Stop provider work when its live qualification gate fails; do not replace the approved flow with credential scraping or a hidden CLI subprocess.
- Apply TDD to every production behavior: write one meaningful failing test, observe the expected failure, implement the minimum, then rerun the focused and full test suites.
- Do not test large rendered strings, generated scripts, or serialized requests. Assert structured models, request method/URL/header fields, and observable UI state.

---

## Planned File Structure

```text
Package.swift
Sources/
  UsageMeterCore/
    Domain/UsageModels.swift
    Presentation/TimelineLayout.swift
    Presentation/UsageSummary.swift
    Credentials/ProviderCredential.swift
    Credentials/CredentialStore.swift
    Credentials/KeychainCredentialStore.swift
    Persistence/PersistedAppState.swift
    Persistence/AppStateStore.swift
    Refresh/AccountRefresher.swift
    Networking/HTTPTransport.swift
    Providers/UsageProviderClient.swift
    Providers/ClaudeUsageClient.swift
    Providers/CodexUsageClient.swift
    Providers/KimiUsageClient.swift
    Auth/PKCE.swift
    Auth/LoopbackCallbackServer.swift
    Auth/CodexOAuthFlow.swift
    Auth/KimiDeviceFlow.swift
  UsageMeterProbe/
    UsageMeterProbe.swift
    ProbeOutput.swift
  UsageMeterUI/
    AppModel.swift
    MenuBar/MenuBarContentView.swift
    Timeline/UsageTimelineView.swift
    Timeline/UsageWindowRow.swift
    Widget/FloatingWidgetController.swift
    Widget/FloatingWidgetView.swift
    Settings/SettingsView.swift
    Settings/AccountListView.swift
    Settings/ClaudeConnectionView.swift
    Settings/CodexConnectionView.swift
    Settings/KimiConnectionView.swift
  AgenticUsageMeter/
    AgenticUsageMeterApp.swift
Tests/
  UsageMeterCoreTests/
    TestSupport.swift
    Fixtures/claude-usage.json
    Fixtures/codex-usage.json
    Fixtures/kimi-usage.json
    UsageModelsTests.swift
    TimelineLayoutTests.swift
    UsageSummaryTests.swift
    AppStateStoreTests.swift
    CredentialStoreContractTests.swift
    AccountRefresherTests.swift
    HTTPTransportTests.swift
    ClaudeUsageClientTests.swift
    CodexUsageClientTests.swift
    KimiUsageClientTests.swift
    PKCETests.swift
    LoopbackCallbackServerTests.swift
    CodexOAuthFlowTests.swift
    KimiDeviceFlowTests.swift
  UsageMeterUITests/
    TestSupport.swift
    AppModelTests.swift
    TimelinePresentationTests.swift
    AccountConnectionTests.swift
Resources/
  Info.plist
Scripts/
  assemble-app.sh
  sign-and-notarize.sh
  verify-release.sh
docs/provider-qualification.md
```

`UsageMeterCore` contains behavior and provider protocols. `AgenticUsageMeter`
contains presentation and lifecycle code. `UsageMeterProbe` reuses the shipping
provider code to perform real-account qualification without waiting for the
complete UI.

---

### Task 1: Swift Package, Domain Model, and Timeline Geometry

**Files:**
- Create: `Package.swift`
- Create: `Sources/UsageMeterCore/Domain/UsageModels.swift`
- Create: `Sources/UsageMeterCore/Presentation/TimelineLayout.swift`
- Create: `Sources/UsageMeterCore/Presentation/UsageSummary.swift`
- Create: `Tests/UsageMeterCoreTests/UsageModelsTests.swift`
- Create: `Tests/UsageMeterCoreTests/TimelineLayoutTests.swift`
- Create: `Tests/UsageMeterCoreTests/UsageSummaryTests.swift`

**Interfaces:**
- Produces: `Provider`, `SubscriptionAccount`, `UsageWindow`, `UsageSnapshot`, `TimelineLayout`, and `UsageSummary.tightestWindow(in:)`.
- Consumes: no prior production interfaces.

- [ ] **Step 1: Add the package test harness and failing domain tests**

Create a Swift 6 package with the macOS 26 `UsageMeterCore` library and its
test target. Later tasks add probe, UI, and app targets only when their source
directories exist. The first tests define the domain contract:

```swift
import Foundation
import Testing
@testable import UsageMeterCore

@Test func usageWindowDerivesStartAndRemainingCapacity() {
    let reset = Date(timeIntervalSince1970: 2_000_000_000)
    let window = UsageWindow(
        kind: .short,
        duration: 18_000,
        resetAt: reset,
        consumedFraction: 0.81
    )

    #expect(window.startAt == reset.addingTimeInterval(-18_000))
    #expect(abs(window.remainingFraction - 0.19) < 0.000_001)
}

@Test func fourteenDayLayoutCentersNowAndUsesSevenDayBars() {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let layout = TimelineLayout(duration: 604_800, now: now)
    let reset = now.addingTimeInterval(172_800)
    let window = UsageWindow(
        kind: .weekly,
        duration: 604_800,
        resetAt: reset,
        consumedFraction: 0.25
    )

    #expect(layout.start == now.addingTimeInterval(-604_800))
    #expect(layout.end == now.addingTimeInterval(604_800))
    #expect(layout.widthFraction(for: window) == 0.5)
    #expect(layout.xFraction(for: window) == 2.0 / 14.0)
}
```

- [ ] **Step 2: Run the focused tests and observe the expected compile failure**

Run: `swift test --filter 'UsageModelsTests|TimelineLayoutTests'`

Expected: FAIL because `UsageWindow` and `TimelineLayout` do not exist.

- [ ] **Step 3: Implement the minimal domain and geometry**

Use bounded fractions and explicit seconds:

```swift
public struct UsageWindow: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: UsageWindowKind
    public let duration: TimeInterval
    public let resetAt: Date
    public let consumedFraction: Double

    public var startAt: Date { resetAt.addingTimeInterval(-duration) }
    public var remainingFraction: Double { 1 - consumedFraction }
}

public struct TimelineLayout: Equatable, Sendable {
    public let start: Date
    public let end: Date

    public init(duration: TimeInterval, now: Date) {
        start = now.addingTimeInterval(-duration)
        end = now.addingTimeInterval(duration)
    }

    public func xFraction(for window: UsageWindow) -> Double
    public func widthFraction(for window: UsageWindow) -> Double
}
```

Require finite fractions in `0...1` and positive durations. Provider adapters
validate untrusted values before constructing a window. Make `UsageSummary`
choose the lowest remaining fraction, breaking ties by earliest reset.

- [ ] **Step 4: Run focused and full tests**

Run: `swift test --filter UsageMeterCoreTests`

Expected: PASS with domain, geometry, and summary tests all green.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/UsageMeterCore Tests/UsageMeterCoreTests
git commit -m "Build usage domain and timeline geometry"
```

---

### Task 2: Local State and Keychain Credentials

**Files:**
- Create: `Sources/UsageMeterCore/Credentials/ProviderCredential.swift`
- Create: `Sources/UsageMeterCore/Credentials/CredentialStore.swift`
- Create: `Sources/UsageMeterCore/Credentials/KeychainCredentialStore.swift`
- Create: `Sources/UsageMeterCore/Persistence/PersistedAppState.swift`
- Create: `Sources/UsageMeterCore/Persistence/AppStateStore.swift`
- Create: `Tests/UsageMeterCoreTests/CredentialStoreContractTests.swift`
- Create: `Tests/UsageMeterCoreTests/AppStateStoreTests.swift`

**Interfaces:**
- Consumes: `SubscriptionAccount`, `UsageSnapshot`.
- Produces: `ProviderCredential`, `CredentialStore`, `KeychainCredentialStore`, `PersistedAppState`, `AppStateStore`.

- [ ] **Step 1: Write failing persistence and credential contract tests**

```swift
@Test func stateStoreRoundTripsAccountAndSnapshot() async throws {
    let directory = try temporaryDirectory()
    let store = AppStateStore(fileURL: directory.appending(path: "state.json"))
    let state = PersistedAppState.sample

    try await store.save(state)

    #expect(try await store.load() == state)
}

@Test func removingCredentialMakesItUnavailable() async throws {
    let store = InMemoryCredentialStore()
    let accountID = UUID()
    try await store.save(.claude(token: "secret"), for: accountID)

    try await store.delete(for: accountID)

    #expect(try await store.load(for: accountID) == nil)
}
```

The production change that makes these tests pass is atomic state persistence
and a credential-store contract with save/load/delete behavior.

- [ ] **Step 2: Run the tests and verify the missing-interface failures**

Run: `swift test --filter 'AppStateStoreTests|CredentialStoreContractTests'`

Expected: FAIL because the stores do not exist.

- [ ] **Step 3: Implement atomic state storage and Keychain-backed credentials**

Define:

```swift
public protocol CredentialStore: Sendable {
    func save(_ credential: ProviderCredential, for accountID: UUID) async throws
    func load(for accountID: UUID) async throws -> ProviderCredential?
    func delete(for accountID: UUID) async throws
}
```

`KeychainCredentialStore` uses generic-password items with service
`com.jesse.agentic-usage-meter.credentials` and the account UUID as the
Keychain account. Encode one credential envelope as JSON only immediately
before `SecItemAdd` or `SecItemUpdate`; decoded values are never logged.

`AppStateStore` writes encoded `PersistedAppState` to a sibling temporary file
and atomically replaces `state.json`. Missing files return `.empty`; corrupt
files throw `AppStateStoreError.corruptData` and are not overwritten.

- [ ] **Step 4: Run focused and full tests**

Run: `swift test`

Expected: PASS. Tests use a temporary directory and in-memory credential store;
they do not inspect serialized secret strings or require the user's login
Keychain.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageMeterCore/Credentials Sources/UsageMeterCore/Persistence Tests/UsageMeterCoreTests
git commit -m "Persist accounts and protect provider credentials"
```

---

### Task 3: Per-account Refresh Throttling and Coalescing

**Files:**
- Create: `Sources/UsageMeterCore/Refresh/AccountRefresher.swift`
- Create: `Tests/UsageMeterCoreTests/AccountRefresherTests.swift`

**Interfaces:**
- Consumes: `UsageSnapshot`.
- Produces: `AccountRefresher.refresh(using:)`, `RefreshOutcome`, `RefreshFailure`, and persisted `AccountRefreshState`.

- [ ] **Step 1: Write failing tests for the hard floor and coalescing**

```swift
@Test func secondRequestInsideTenMinutesUsesCachedSnapshot() async throws {
    let clock = TestDateSource(now: .reference)
    let fetcher = CountingUsageFetcher(result: .sample)
    let refresher = AccountRefresher(
        minimumInterval: 600,
        now: { await clock.now }
    )

    _ = try await refresher.refresh(using: fetcher.fetch)
    await clock.advance(by: 599)
    let result = try await refresher.refresh(using: fetcher.fetch)

    #expect(result == .throttled(snapshot: .sample, eligibleAt: .reference.addingTimeInterval(600)))
    #expect(await fetcher.callCount == 1)
}

@Test func concurrentDemandSharesOneInFlightRequest() async throws {
    let fetcher = SuspendingUsageFetcher()
    let refresher = AccountRefresher(now: { .reference })

    async let first = refresher.refresh(using: fetcher.fetch)
    async let second = refresher.refresh(using: fetcher.fetch)
    await fetcher.resume(with: .sample)
    _ = try await (first, second)

    #expect(await fetcher.callCount == 1)
}
```

- [ ] **Step 2: Run the tests and observe the missing scheduler failure**

Run: `swift test --filter AccountRefresherTests`

Expected: FAIL because `AccountRefresher` is undefined.

- [ ] **Step 3: Implement the actor**

`AccountRefresher` records request start time before calling the provider,
retains one `Task<UsageSnapshot, Error>`, and clears it after all waiters
receive the result. Eligibility is:

```swift
max(
    lastRequestStartedAt?.addingTimeInterval(600) ?? .distantPast,
    providerRetryAt ?? .distantPast,
    failureBackoffUntil ?? .distantPast
)
```

Manual and scheduled callers use the same method. Authentication failure
transitions to `.reauthenticationRequired`; transient failure retains the
last-good snapshot and increases backoff to 10, 20, 40, then 60 minutes.

- [ ] **Step 4: Run scheduler and full tests**

Run: `swift test --filter AccountRefresherTests`

Run: `swift test`

Expected: PASS with one provider call for concurrent demand and no request
before ten minutes.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageMeterCore/Refresh Tests/UsageMeterCoreTests/AccountRefresherTests.swift
git commit -m "Throttle and coalesce account refreshes"
```

---

### Task 4: HTTP Boundary and Qualification Probe

**Files:**
- Create: `Sources/UsageMeterCore/Networking/HTTPTransport.swift`
- Create: `Sources/UsageMeterCore/Providers/UsageProviderClient.swift`
- Create: `Sources/UsageMeterProbe/ProbeOutput.swift`
- Create: `Sources/UsageMeterProbe/UsageMeterProbe.swift`
- Modify: `Package.swift`
- Create: `Tests/UsageMeterCoreTests/HTTPTransportTests.swift`

**Interfaces:**
- Consumes: `Provider`, `ProviderCredential`, `UsageSnapshot`.
- Produces: `HTTPTransport`, `HTTPResponse`, `URLSessionHTTPTransport`, `UsageProviderClient`, and `ProbeOutput`.

- [ ] **Step 1: Write a failing structured-request test**

```swift
@Test func transportReturnsStatusHeadersAndData() async throws {
    let session = URLSession(configuration: .testProtocol)
    TestURLProtocol.respond(status: 200, headers: ["Retry-After": "900"], body: Data("{}".utf8))
    let transport = URLSessionHTTPTransport(session: session)

    let response = try await transport.send(URLRequest(url: URL(string: "https://example.test/usage")!))

    #expect(response.statusCode == 200)
    #expect(response.header(named: "Retry-After") == "900")
    #expect(response.data == Data("{}".utf8))
}
```

- [ ] **Step 2: Run the focused test and verify failure**

Run: `swift test --filter HTTPTransportTests`

Expected: FAIL because the transport types do not exist.

- [ ] **Step 3: Implement the transport and sanitized probe output**

`HTTPTransport.send(_:)` returns data, integer status, and normalized headers.
It never logs request headers or response bodies. `ProbeOutput` contains only:

```swift
struct ProbeOutput: Codable {
    let provider: Provider
    let identity: String?
    let windows: [ProbeWindow]
}

struct ProbeWindow: Codable {
    let kind: UsageWindowKind
    let durationSeconds: Int
    let consumedPercent: Int
    let resetAt: Date
}
```

The probe selects `claude`, `codex`, or `kimi` from arguments, obtains
credential material only from the provider-specific flow or process
environment, calls shipping adapter code, and prints `ProbeOutput`. It never
prints token data or a raw response.

Add the `UsageMeterProbe` executable target and product to `Package.swift`
only in this task.

- [ ] **Step 4: Run tests and compile both executables**

Run: `swift test`

Run: `swift build --product UsageMeterProbe`

Expected: all commands exit successfully.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageMeterCore/Networking Sources/UsageMeterCore/Providers Sources/UsageMeterProbe Tests/UsageMeterCoreTests/HTTPTransportTests.swift
git commit -m "Add provider transport and qualification probe"
```

---

### Task 5: Claude Usage Adapter and Live Gate

**Files:**
- Create: `Sources/UsageMeterCore/Providers/ClaudeUsageClient.swift`
- Create: `Tests/UsageMeterCoreTests/Fixtures/claude-usage.json`
- Create: `Tests/UsageMeterCoreTests/ClaudeUsageClientTests.swift`
- Modify: `Sources/UsageMeterProbe/UsageMeterProbe.swift`
- Create: `docs/provider-qualification.md`

**Interfaces:**
- Consumes: `HTTPTransport`, `.claude(token:)`, `UsageSnapshot`.
- Produces: `ClaudeUsageClient.fetchUsage(accountID:credential:now:)`.

- [ ] **Step 1: Write failing decoder and request tests**

Use a sanitized fixture shaped like the observed Claude Code response:

```json
{
  "five_hour": {
    "utilization": 81.0,
    "resets_at": "2026-07-29T20:23:00Z"
  },
  "seven_day": {
    "utilization": 66.0,
    "resets_at": "2026-08-03T21:40:00Z"
  }
}
```

Tests assert two normalized windows with durations 18,000 and 604,800 seconds,
consumed fractions `0.81` and `0.66`, and the exact reset dates. A structured
request test asserts `GET https://api.anthropic.com/api/oauth/usage`, bearer
authorization, and `anthropic-beta: oauth-2025-04-20`.

- [ ] **Step 2: Run and verify the adapter tests fail**

Run: `swift test --filter ClaudeUsageClientTests`

Expected: FAIL because `ClaudeUsageClient` is missing.

- [ ] **Step 3: Implement strict required-window decoding**

Decode `five_hour` and `seven_day`; tolerate unknown siblings. Reject a missing
required object, non-finite utilization, absent reset, or utilization outside
`0...100` as `ProviderClientError.unsupportedResponse`. Map HTTP 401/403 to
`.reauthenticationRequired`, 429 to `.retryAfter`, and other non-2xx responses
to `.temporaryFailure`.

- [ ] **Step 4: Run automated tests and the real Claude gate**

Run: `swift test --filter ClaudeUsageClientTests`

Run:

```bash
read -s CLAUDE_CODE_OAUTH_TOKEN
export CLAUDE_CODE_OAUTH_TOKEN
swift run UsageMeterProbe claude
unset CLAUDE_CODE_OAUTH_TOKEN
```

Expected: sanitized output contains one 18,000-second window and one
604,800-second window. Append the date, Claude Code version used to create the
token, HTTP outcome, and sanitized window shape to
`docs/provider-qualification.md`. Never record the token or account identity.

If the real request fails, stop Claude implementation and report the exact
sanitized HTTP/error result to Jesse before proceeding.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageMeterCore/Providers/ClaudeUsageClient.swift Sources/UsageMeterProbe Tests/UsageMeterCoreTests/ClaudeUsageClientTests.swift Tests/UsageMeterCoreTests/Fixtures/claude-usage.json docs/provider-qualification.md
git commit -m "Qualify Claude subscription usage"
```

---

### Task 6: Codex PKCE OAuth, Usage Adapter, and Multi-account Gate

**Files:**
- Create: `Sources/UsageMeterCore/Auth/PKCE.swift`
- Create: `Sources/UsageMeterCore/Auth/LoopbackCallbackServer.swift`
- Create: `Sources/UsageMeterCore/Auth/CodexOAuthFlow.swift`
- Create: `Sources/UsageMeterCore/Providers/CodexUsageClient.swift`
- Create: `Tests/UsageMeterCoreTests/Fixtures/codex-usage.json`
- Create: `Tests/UsageMeterCoreTests/PKCETests.swift`
- Create: `Tests/UsageMeterCoreTests/LoopbackCallbackServerTests.swift`
- Create: `Tests/UsageMeterCoreTests/CodexOAuthFlowTests.swift`
- Create: `Tests/UsageMeterCoreTests/CodexUsageClientTests.swift`
- Modify: `Sources/UsageMeterProbe/UsageMeterProbe.swift`
- Modify: `docs/provider-qualification.md`

**Interfaces:**
- Consumes: `HTTPTransport`, `.codex(...)`, `CredentialStore`, `UsageSnapshot`.
- Produces: `PKCECodes`, `LoopbackCallbackServer`, `CodexOAuthFlow.authenticate()`, `CodexUsageClient`.

- [ ] **Step 1: Write failing PKCE, callback, token-request, and usage tests**

Tests establish:

- A 32-byte random verifier is base64url without padding.
- The challenge is `BASE64URL(SHA256(verifier))`.
- Callback parsing requires `/auth/callback`, matching state, and a non-empty
  code; query values never appear in error descriptions.
- The authorize URL uses `https://auth.openai.com/oauth/authorize`, client
  `app_EMoamEEZ73f0CkXaXp7hrann`, localhost redirect port 1455 with fallback
  1457, S256 PKCE, scopes
  `openid profile email offline_access api.connectors.read api.connectors.invoke`,
  `id_token_add_organizations=true`, `codex_cli_simplified_flow=true`, and
  `originator=codex_cli_rs`.
- Token exchange uses form fields, not a JSON or rendered-string assertion.
- Usage requests use `GET https://chatgpt.com/backend-api/wham/usage` with
  bearer access token and `ChatGPT-Account-Id`.
- `primary_window` and `secondary_window` map
  `used_percent`, `limit_window_seconds`, and Unix `reset_at`.

- [ ] **Step 2: Run all Codex-focused tests and observe missing types**

Run: `swift test --filter 'PKCETests|LoopbackCallbackServerTests|CodexOAuthFlowTests|CodexUsageClientTests'`

Expected: FAIL because the Codex auth and client types are absent.

- [ ] **Step 3: Implement OAuth, JWT identity extraction, refresh, and usage**

Use CryptoKit for SHA-256 and Security random bytes. Use Network framework for
a loopback-only HTTP listener that serves one callback, validates state, writes
a small success page, closes the connection, and shuts down.

Open the authorize URL with `NSWorkspace.shared.open`. Exchange the code at
`https://auth.openai.com/oauth/token`. Parse the ID token payload without
claiming to verify its signature; it is identity metadata from a token received
over the authenticated token exchange. Extract email, plan, user, and ChatGPT
account/workspace identifiers defensively.

Refresh with `grant_type=refresh_token`, the public client ID, and the stored
refresh token. Save rotated tokens atomically. Decode only the primary Codex
rate-limit object for v1; ignore credits and additional metered features.

- [ ] **Step 4: Run automated tests and qualify two accounts**

Run: `swift test`

Run `swift run UsageMeterProbe codex` twice, completing the browser flow with
two different accounts and saving each probe credential under a distinct
temporary Keychain account. Then run `swift run UsageMeterProbe codex-refresh
<probe-id>` for both.

Expected: both identities remain distinct, each returns short and weekly
windows, and refreshing one does not mutate the other's credential. Delete the
temporary probe Keychain items after recording sanitized evidence in
`docs/provider-qualification.md`.

If the OAuth client is rejected, account selection cannot be made explicit, or
either credential stops working when the second is added, stop Codex
implementation and report the sanitized result.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageMeterCore/Auth Sources/UsageMeterCore/Providers/CodexUsageClient.swift Sources/UsageMeterProbe Tests/UsageMeterCoreTests docs/provider-qualification.md
git commit -m "Qualify native multi-account Codex usage"
```

---

### Task 7: Kimi Device OAuth, Usage Adapter, and Live Gate

**Files:**
- Create: `Sources/UsageMeterCore/Auth/KimiDeviceFlow.swift`
- Create: `Sources/UsageMeterCore/Providers/KimiUsageClient.swift`
- Create: `Tests/UsageMeterCoreTests/Fixtures/kimi-usage.json`
- Create: `Tests/UsageMeterCoreTests/KimiDeviceFlowTests.swift`
- Create: `Tests/UsageMeterCoreTests/KimiUsageClientTests.swift`
- Modify: `Sources/UsageMeterProbe/UsageMeterProbe.swift`
- Modify: `docs/provider-qualification.md`

**Interfaces:**
- Consumes: `HTTPTransport`, `.kimi(...)`, `CredentialStore`, `UsageSnapshot`.
- Produces: `KimiDeviceFlow.authorize()`, `KimiAuthorizationUpdate`, `KimiUsageClient`.

- [ ] **Step 1: Write failing device-flow and response tests**

Tests assert:

- Device authorization posts form client ID
  `17e5f671-d194-4dfb-9706-5516cb48c098` to
  `https://auth.kimi.com/api/oauth/device_authorization`.
- Token polling posts the device code and standard device-code grant to
  `/api/oauth/token`.
- `authorization_pending` waits the provider interval; `slow_down` increases
  it; expiry stops polling; cancellation stops without saving.
- Refresh-token rotation replaces both access and refresh tokens.
- Usage requests use bearer auth at
  `https://api.kimi.com/coding/v1/usages`.
- A fixture with `usage` and `limits[].detail/window` maps the observed
  five-hour and weekly durations, used/limit ratios, and reset fields.

- [ ] **Step 2: Run Kimi-focused tests and observe missing types**

Run: `swift test --filter 'KimiDeviceFlowTests|KimiUsageClientTests'`

Expected: FAIL because the Kimi flow and client are absent.

- [ ] **Step 3: Implement device authorization and permissive observed-shape decoding**

Emit structured authorization updates containing verification URL, user code,
expiry, and state. Open `verification_uri_complete` in the regular browser.
Poll at the supplied interval without using the ten-minute usage scheduler;
the ten-minute floor begins only after account validation.

Decode integer `used`, `limit`, `remaining`, duration/time unit, and ISO or Unix
reset variants observed in Kimi CLI. Require one 18,000-second and one
604,800-second normalized window for v1 account validation.

- [ ] **Step 4: Run automated tests and the real Kimi gate**

Run: `swift test`

Run: `swift run UsageMeterProbe kimi`

Expected: the browser/device flow completes and sanitized output contains both
required windows. Record the sanitized result and token-refresh outcome in
`docs/provider-qualification.md`, then delete the temporary probe credential.

If either required window cannot be established, stop Kimi implementation and
report the sanitized response shape.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageMeterCore/Auth/KimiDeviceFlow.swift Sources/UsageMeterCore/Providers/KimiUsageClient.swift Sources/UsageMeterProbe Tests/UsageMeterCoreTests docs/provider-qualification.md
git commit -m "Qualify Kimi device-authenticated usage"
```

---

### Task 8: Application Model and Account Lifecycle

**Files:**
- Create: `Sources/UsageMeterUI/AppModel.swift`
- Create: `Tests/UsageMeterUITests/TestSupport.swift`
- Create: `Tests/UsageMeterUITests/AppModelTests.swift`
- Create: `Tests/UsageMeterUITests/AccountConnectionTests.swift`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: all qualified provider clients, `CredentialStore`, `AppStateStore`, `AccountRefresher`, and domain models.
- Produces: `@MainActor @Observable AppModel`, `AccountViewState`, add/rename/remove/reconnect/refresh operations.

- [ ] **Step 1: Write failing journey-level model tests**

```swift
@Test @MainActor func launchShowsCacheThenRefreshesEligibleAccounts() async throws {
    let fixture = AppFixture.withCachedAccount(lastRequest: .reference.addingTimeInterval(-601))
    let model = fixture.makeModel(now: .reference)

    await model.start()

    #expect(model.accounts[0].snapshot == .cachedSample)
    #expect(await fixture.provider.callCount == 1)
    #expect(model.accounts[0].snapshot == .freshSample)
}

@Test @MainActor func removingAccountDeletesStateAndCredential() async throws {
    let fixture = AppFixture.connected()
    let model = fixture.makeModel()

    try await model.removeAccount(id: fixture.accountID)

    #expect(model.accounts.isEmpty)
    #expect(try await fixture.credentials.load(for: fixture.accountID) == nil)
}
```

- [ ] **Step 2: Run the app-model tests and verify failure**

Run: `swift test --filter 'AppModelTests|AccountConnectionTests'`

Expected: FAIL because `AppModel` does not exist.

- [ ] **Step 3: Implement the main-actor model**

Load cached state before scheduling refresh. Create one refresher per account.
Publish stable provider/account ordering, current snapshot, age, eligibility,
error, and reconnect state. Mutating an account persists state after the
in-memory change; destructive removal deletes the Keychain item first and only
then removes local state.

Account addition validates a provider credential through the qualified client
before persisting either metadata or Keychain material.

Add the `UsageMeterUI` library target and `UsageMeterUITests` test target to
`Package.swift` in this task. The UI target depends on `UsageMeterCore`; the
test target depends on both libraries.

- [ ] **Step 4: Run model and full tests**

Run: `swift test`

Expected: PASS with cache-first launch, independent account failure, hard-floor
manual refresh, rename, reorder, reconnect, and removal coverage.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/UsageMeterUI/AppModel.swift Tests/UsageMeterUITests
git commit -m "Coordinate account state and refresh lifecycle"
```

---

### Task 9: Provider-stacked Gantt Timeline Views

**Files:**
- Create: `Sources/UsageMeterUI/Timeline/UsageTimelineView.swift`
- Create: `Sources/UsageMeterUI/Timeline/UsageWindowRow.swift`
- Create: `Tests/UsageMeterUITests/TimelinePresentationTests.swift`

**Interfaces:**
- Consumes: `AccountViewState`, `TimelineLayout`, `UsageWindow`.
- Produces: `UsageTimelineView`, `UsageWindowRow`, and testable `UsageWindowPresentation`.

- [ ] **Step 1: Write failing presentation tests**

Tests assert the structured presentation model, not rendered SwiftUI:

```swift
@Test func codexWorkWeeklyRowContainsApprovedGeometryAndPills() {
    let presentation = UsageWindowPresentation(
        account: .codexWork,
        window: .weeklySample,
        now: .reference
    )

    #expect(presentation.outerWidthFraction == 0.5)
    #expect(presentation.fillFraction == 0.66)
    #expect(presentation.remainingText == "34% left")
    #expect(presentation.expiryText == "Mon 2:40 PM")
    #expect(presentation.accessibilityValue.contains("34 percent remaining"))
}
```

- [ ] **Step 2: Run the focused test and observe missing presentation types**

Run: `swift test --filter TimelinePresentationTests`

Expected: FAIL because `UsageWindowPresentation` is absent.

- [ ] **Step 3: Implement the approved bars-inside-Gantt view**

Build separate weekly and five-hour sections. Each uses a shared axis centered
on now. Rows remain grouped Claude, Codex, Kimi and ordered by account order.

Each row draws:

1. a neutral full-duration outer bar with provider-colored outline;
2. a full-height consumed fill from the outer bar's leading edge;
3. a shared now line above the bar;
4. a left dark translucent `% left` capsule;
5. a right dark translucent reset capsule.

Use `GeometryReader` only inside the row, driven by precomputed clamped
fractions. Expose a combined accessibility label containing provider, account,
window duration, remaining percent, and reset time.

- [ ] **Step 4: Run focused and full UI tests**

Run: `swift test`

Expected: automated tests pass. The live visual gate runs after Task 10 adds
the executable app lifecycle.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageMeterUI/Timeline Tests/UsageMeterUITests/TimelinePresentationTests.swift
git commit -m "Render aligned quota burn timelines"
```

---

### Task 10: Menu Bar and Floating Widget

**Files:**
- Create: `Sources/AgenticUsageMeter/AgenticUsageMeterApp.swift`
- Create: `Sources/UsageMeterUI/MenuBar/MenuBarContentView.swift`
- Create: `Sources/UsageMeterUI/Widget/FloatingWidgetController.swift`
- Create: `Sources/UsageMeterUI/Widget/FloatingWidgetView.swift`
- Modify: `Sources/UsageMeterUI/AppModel.swift`
- Modify: `Tests/UsageMeterUITests/AppModelTests.swift`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: `AppModel`, `UsageTimelineView`, `UsageSummary`.
- Produces: application lifecycle, `MenuBarExtra`, tightest-limit label, and optional persistent `NSPanel`.

- [ ] **Step 1: Write failing state tests for label and widget preference**

Test that the menu label uses the lowest remaining percentage and earliest
reset tie-breaker, that no-data renders a neutral symbol, and that toggling the
widget persists visibility and placement without changing refresh ownership.

- [ ] **Step 2: Run focused tests and verify the missing behavior**

Run: `swift test --filter AppModelTests`

Expected: FAIL on the new menu-label and widget-preference expectations.

- [ ] **Step 3: Implement the app surfaces**

Set activation policy to `.accessory`. Use `MenuBarExtra` for the popover and a
single `FloatingWidgetController` that owns an `NSPanel` with
`NSHostingController(rootView:)`. The panel is non-activating, floats above
normal windows, can move between screens, and persists its frame after a move
ends.

Both surfaces render the same observable model and timeline components. They
never trigger provider calls directly; they only request refresh from
`AppModel`, which enforces the scheduler.

Add the `AgenticUsageMeter` executable target and product to `Package.swift`.
Its only source is the `@main` app lifecycle; it depends on `UsageMeterUI` and
`UsageMeterCore`.

- [ ] **Step 4: Run tests and live surface checks**

Run: `swift test`

Run: `swift run AgenticUsageMeter --sample-data`

Expected: no Dock icon, one menu-bar item, opening/closing the popover does not
duplicate refresh work, and the floating panel can be shown, moved, hidden,
and restored.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/AgenticUsageMeter Sources/UsageMeterUI/MenuBar Sources/UsageMeterUI/Widget Sources/UsageMeterUI/AppModel.swift Tests/UsageMeterUITests/AppModelTests.swift
git commit -m "Add menu-bar and floating usage surfaces"
```

---

### Task 11: Settings and Provider Connection Flows

**Files:**
- Create: `Sources/UsageMeterUI/Settings/SettingsView.swift`
- Create: `Sources/UsageMeterUI/Settings/AccountListView.swift`
- Create: `Sources/UsageMeterUI/Settings/ClaudeConnectionView.swift`
- Create: `Sources/UsageMeterUI/Settings/CodexConnectionView.swift`
- Create: `Sources/UsageMeterUI/Settings/KimiConnectionView.swift`
- Modify: `Sources/UsageMeterUI/MenuBar/MenuBarContentView.swift`
- Modify: `Tests/UsageMeterUITests/AccountConnectionTests.swift`

**Interfaces:**
- Consumes: `AppModel` connection, rename, reorder, reconnect, and removal operations.
- Produces: user-visible account management and secure connection journeys.

- [ ] **Step 1: Write failing connection-state tests**

Tests cover:

- Claude refuses an empty token, validates before saving, clears the submitted
  value, and never retains it in observable state.
- Codex exposes browser-waiting, callback, identity-confirmation, and failure
  states; saving requires an explicit account label.
- Kimi exposes verification URL, user code, expiry, waiting, success, and
  cancellation states.
- Removing an account requires confirmation and invokes the model's atomic
  removal path.

- [ ] **Step 2: Run focused tests and observe missing connection states**

Run: `swift test --filter AccountConnectionTests`

Expected: FAIL for the absent settings flows.

- [ ] **Step 3: Implement focused SwiftUI forms**

Claude presents the exact terminal command in selectable text and a
`SecureField`. It does not add clipboard monitoring or a CLI launcher.

Codex starts the native flow and displays the returned email/workspace before
the user saves a label. Kimi shows the code in monospaced selectable text and
provides an explicit browser-open action in addition to automatic opening.

The account list shows provider, user label, authenticated identity when
available, last refresh, current error, reconnect, rename, reorder, and remove.

- [ ] **Step 4: Run automated and live connection checks**

Run: `swift test`

Run: `swift run AgenticUsageMeter`

Expected: the three connection journeys use shipping provider code and create
independent account rows. Cancelled or failed flows leave no Keychain or local
state behind.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageMeterUI/Settings Sources/UsageMeterUI/MenuBar/MenuBarContentView.swift Tests/UsageMeterUITests/AccountConnectionTests.swift
git commit -m "Add secure multi-provider account setup"
```

---

### Task 12: Application Bundle, Release Checks, and Acceptance Evidence

**Files:**
- Create: `Resources/Info.plist`
- Create: `Scripts/assemble-app.sh`
- Create: `Scripts/sign-and-notarize.sh`
- Create: `Scripts/verify-release.sh`
- Create: `Tests/UsageMeterCoreTests/ReleaseConfigurationTests.swift`
- Modify: `README.md`
- Modify: `docs/provider-qualification.md`

**Interfaces:**
- Consumes: release `AgenticUsageMeter` executable and all prior acceptance gates.
- Produces: `build/Agentic Usage Meter.app`, signed/notarized release workflow, operator documentation.

- [ ] **Step 1: Write failing structured release-configuration tests**

Load `Info.plist` with `PropertyListSerialization` and assert:

- `CFBundleIdentifier` is `com.jesse.agentic-usage-meter`.
- `CFBundleName` is `Agentic Usage Meter`.
- `LSUIElement` is true.
- `LSMinimumSystemVersion` is `26.0`.

The app is deliberately not App Sandbox enabled. Standard Keychain access,
outgoing requests, and the localhost OAuth listener therefore require no
sandbox entitlements. Do not add an entitlements file without a new
architecture decision. Tests do not assert shell-command text.

- [ ] **Step 2: Run the release tests and observe missing resources**

Run: `swift test --filter ReleaseConfigurationTests`

Expected: FAIL because release resources do not exist.

- [ ] **Step 3: Add deterministic assembly and signing workflows**

`assemble-app.sh` runs a release Swift build, creates the standard
`Contents/MacOS` and `Contents/Resources` layout, copies `Info.plist`, and
places the executable. `sign-and-notarize.sh` requires explicit
`DEVELOPER_ID_APPLICATION` and notarytool profile inputs; it never guesses an
identity or stores credentials. `verify-release.sh` runs `codesign --verify
--deep --strict`, `spctl --assess --type execute`, and `stapler validate`.

README documents development build, tests, provider connection, direct release
assembly, signing, notarization, and the ten-minute refresh rule.

- [ ] **Step 4: Run complete verification**

Run: `swift test`

Run: `swift build -c release`

Run: `Scripts/assemble-app.sh`

Run: `codesign --force --deep --sign - "build/Agentic Usage Meter.app"`

Run: `codesign --verify --deep --strict --verbose=2 "build/Agentic Usage Meter.app"`

Run: `open "build/Agentic Usage Meter.app"`

Expected: all automated tests pass, release build succeeds, the ad-hoc-signed
artifact launches as a menu-bar app, cached and live provider states render,
and the floating widget behaves as verified in Task 10.

Developer ID signing and notarization are run only when Jesse supplies the
existing signing identity and notarytool profile. Record that external
acceptance separately; do not claim notarization from an ad-hoc signature.

- [ ] **Step 5: Commit**

```bash
git add Resources Scripts Tests/UsageMeterCoreTests/ReleaseConfigurationTests.swift README.md docs/provider-qualification.md
git commit -m "Package and verify Agentic Usage Meter"
```

---

## Final Verification

- [ ] Run `swift test` and report exact test counts and failures.
- [ ] Run `swift build -c release` and report the exit result.
- [ ] Assemble and ad-hoc sign the application bundle.
- [ ] Launch the assembled bundle, not only `swift run`.
- [ ] Verify menu-bar, popover, widget, settings, and all three account
      connection journeys against the approved design.
- [ ] Confirm the provider qualification record contains current sanitized
      evidence for Claude, two Codex accounts, and Kimi.
- [ ] Confirm `git status --short` is clean.
- [ ] Run `git diff --check` against the implementation range.
- [ ] Report Developer ID/notarization as incomplete unless the real signed
      artifact has passed `codesign`, `spctl`, `notarytool`, and `stapler`.
