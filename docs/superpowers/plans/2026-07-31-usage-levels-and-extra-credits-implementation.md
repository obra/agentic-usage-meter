# Usage Levels and Extra Credits Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render every authoritative active or inactive rolling usage level in aligned single-line timelines, show explicit provider extra-credit state in a separate compact section, and refresh healthy development accounts as often as once per minute without weakening release throttling.

**Architecture:** Extend the normalized core model with an optional provider reset and an explicit credit value enum, retaining the approved narrow persistence compatibility. Provider decoders map only authoritative response fields into that model; shared presentation resolves resetless zero-use windows against its injected render time, and one SwiftUI grid aligns all timed rows while a second grid renders Extra Credits. A shared `RefreshPolicy` is injected into `AppModel` and every `AccountRefresher`, with the executable choosing development or release policy at composition time.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Foundation, Swift Testing, SwiftPM, macOS 26

## Global Constraints

- Keep five-hour rows on a ten-hour axis and weekly rows on a fourteen-day axis, both with **Now** at 50%.
- Keep every usage and Extra Credits row on one line.
- Align timed columns as percentage, provider, account, timeline, and remaining time without a visible global column header.
- A zero-use window with no provider reset renders empty from **Now** for exactly its duration; a nonzero resetless window is invalid.
- Never persist the display-only endpoint as provider data.
- Show a credit amount only when the provider reports an authoritative balance; show **Unlimited** or **Off** only when explicitly reported; omit unknown or unsupported state.
- Existing numeric `UsageBalance` records decode as Available. This is the only balance-state backward compatibility authorized by Jesse.
- Development builds use a 60-second automatic cadence and provider-contact floor; release builds use 600 seconds.
- Manual refresh uses the same per-account floor, while transient-error backoff remains 600, 1,200, 2,400, then 3,600 seconds.
- Keep credentials local and account-isolated; do not log raw provider responses, tokens, cookies, authorization headers, or private balance data.
- Preserve natural-height menu-bar and widget behavior, with scrolling only when the active screen cannot fit the content.

---

## File Map

- `Sources/UsageMeterCore/Domain/UsageModels.swift`
  owns resetless-window invariants and the explicit Available, Unlimited, and
  Disabled credit value.
- `Sources/UsageMeterCore/Presentation/TimelineLayout.swift`
  places resetless inactive windows at the center **Now** coordinate without
  modifying provider data.
- `Sources/UsageMeterCore/Presentation/UsageSummary.swift`
  keeps menu-bar summary selection deterministic when a reset is absent.
- `Sources/UsageMeterProbe/ProbeOutput.swift` and
  `Sources/ClaudeWebProbe/ClaudeWebProbeModel.swift`
  keep sanitized probes capable of representing a missing provider reset.
- `Sources/UsageMeterCore/Providers/ClaudeUsageDecoder.swift`
  decodes nullable resets and Claude's explicit extra-usage state.
- `Sources/UsageMeterCore/Providers/CodexUsageClient.swift`
  decodes the Codex `credits` object without losing decimal-string precision.
- `Sources/UsageMeterCore/Providers/Factory/FactoryUsageDecoder.swift`
  retains zero-use windows without ends and maps explicit extra-usage allowance.
- `Sources/UsageMeterCore/Providers/OpenCode/OpenCodeZenUsageDecoder.swift`
  maps the existing Zen numeric balance into the new Available value.
- `Sources/UsageMeterUI/Timeline/UsageWindowPresentation.swift`
  derives display-only inactive geometry, credit labels and values, help, and
  accessibility text.
- `Sources/UsageMeterUI/Timeline/UsageWindowRow.swift`
  renders the five timed columns and Gantt marks as `GridRow` content.
- `Sources/UsageMeterUI/Timeline/UsageTimelineView.swift`
  owns the cross-section timed grid and separate Extra Credits grid.
- `Sources/UsageMeterCore/Refresh/RefreshPolicy.swift`
  defines injectable development and release cadence/floor pairs.
- `Sources/UsageMeterCore/Refresh/AccountRefresher.swift`
  uses the shared release floor as its default instead of a second literal.
- `Sources/UsageMeterUI/AppModel.swift`
  injects one policy into automatic cadence and every account refresher.
- `Sources/AgenticUsageMeter/AgenticUsageMeterApp.swift`
  selects development or release policy and supplies representative sample rows.
- `README.md` and `docs/provider-qualification.md`
  document the shipped refresh and inactive-window behavior.
- Core and UI test files named in each task exercise the real normalized
  behavior with literal provider fixtures.

### Task 1: Resetless Windows and Explicit Credit Values

**Files:**
- Modify: `Sources/UsageMeterCore/Domain/UsageModels.swift`
- Modify: `Sources/UsageMeterCore/Presentation/TimelineLayout.swift`
- Modify: `Sources/UsageMeterCore/Presentation/UsageSummary.swift`
- Modify: `Sources/UsageMeterProbe/ProbeOutput.swift`
- Modify: `Sources/ClaudeWebProbe/ClaudeWebProbeModel.swift`
- Modify: `Tests/UsageMeterCoreTests/UsageModelsTests.swift`
- Modify: `Tests/UsageMeterCoreTests/TimelineLayoutTests.swift`
- Modify: `Tests/UsageMeterCoreTests/UsageSummaryTests.swift`
- Modify: `Tests/UsageMeterProbeTests/UsageMeterProbeCommandTests.swift`
- Modify: `Tests/ClaudeWebProbeTests/ClaudeWebProbeModelTests.swift`

**Interfaces:**
- Consumes: existing `UsageWindow`, `UsageBalance`, `UsageSnapshot`, and JSON snapshots.
- Produces: `UsageWindow.resetAt: Date?`, `UsageWindow.startAt: Date?`,
  `UsageBalanceValue`, and backward-compatible `UsageBalance` decoding.

- [ ] **Step 1: Add failing resetless-window domain and layout tests**

Add these focused tests before changing production code:

```swift
@Test
func zeroUseWindowAcceptsMissingProviderReset() throws {
    let window = try #require(
        UsageWindow(
            id: "inactive",
            kind: .short,
            duration: 18_000,
            resetAt: nil,
            consumedFraction: 0,
        ),
    )

    #expect(window.resetAt == nil)
    #expect(window.startAt == nil)
    let encoded = try JSONEncoder().encode(window)
    let decoded = try JSONDecoder().decode(UsageWindow.self, from: encoded)
    #expect(decoded == window)
}

@Test
func nonzeroWindowRejectsMissingProviderReset() {
    #expect(
        UsageWindow(
            id: "invalid",
            kind: .weekly,
            duration: 604_800,
            resetAt: nil,
            consumedFraction: 0.01,
        ) == nil,
    )
}

@Test
func resetlessWindowBeginsAtNowOnTheSharedAxis() throws {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let layout = try #require(TimelineLayout(duration: 18_000, now: now))
    let window = try #require(
        UsageWindow(
            id: "inactive",
            kind: .short,
            duration: 18_000,
            resetAt: nil,
            consumedFraction: 0,
        ),
    )

    #expect(layout.xFraction(for: window) == 0.5)
    #expect(layout.widthFraction(for: window) == 0.5)
}
```

- [ ] **Step 2: Add failing credit-state persistence tests**

Add literal tests for all new states and the authorized old representation:

```swift
@Test
func legacyNumericBalanceDecodesAsAvailable() throws {
    let data = Data(
        #"{"id":"credits","label":"Usage credits","remainingAmount":38.42,"unit":"USD"}"#.utf8,
    )

    let balance = try JSONDecoder().decode(UsageBalance.self, from: data)

    #expect(
        balance.value
            == .available(amount: Decimal(string: "38.42")!, unit: "USD"),
    )
}

@Test(arguments: [
    UsageBalanceValue.unlimited,
    UsageBalanceValue.disabled,
])
func nonnumericCreditStatesRoundTrip(_ value: UsageBalanceValue) throws {
    let balance = try #require(
        UsageBalance(id: "credits", label: "Usage credits", value: value),
    )
    let encoded = try JSONEncoder().encode(balance)
    #expect(try JSONDecoder().decode(UsageBalance.self, from: encoded) == balance)
}
```

- [ ] **Step 3: Run the new tests and verify RED**

Run:

```bash
swift test --filter zeroUseWindowAcceptsMissingProviderReset
swift test --filter legacyNumericBalanceDecodesAsAvailable
```

Expected: compilation fails because `resetAt` is not optional and
`UsageBalanceValue` does not exist.

- [ ] **Step 4: Implement the minimal normalized model**

Change the timed properties to:

```swift
public let resetAt: Date?

public init?(
    id: String,
    kind: UsageWindowKind,
    duration: TimeInterval,
    resetAt: Date?,
    consumedFraction: Double,
    label: String? = nil,
    reportedStartAt: Date? = nil
) {
    guard
        !id.isEmpty,
        duration.isFinite,
        duration > 0,
        consumedFraction.isFinite,
        (0 ... 1).contains(consumedFraction),
        resetAt != nil
            || (consumedFraction == 0 && reportedStartAt == nil)
    else {
        return nil
    }
    // Assign the validated values.
}

public var startAt: Date? {
    reportedStartAt ?? resetAt?.addingTimeInterval(-duration)
}
```

Decode `resetAt` with `decodeIfPresent`. In `TimelineLayout.xFraction`, use the
window's real start when present and otherwise use the layout midpoint:

```swift
let windowStart = window.startAt ?? start.addingTimeInterval(span / 2)
return clamped(windowStart.timeIntervalSince(start) / span)
```

Define the credit contract:

```swift
public enum UsageBalanceValue: Codable, Equatable, Sendable {
    case available(amount: Decimal, unit: String)
    case unlimited
    case disabled
}
```

`UsageBalance` stores `value: UsageBalanceValue`. Retain the existing numeric
initializer with `remainingAmount: Decimal` as a convenience that creates
`.available`. Its custom Codable representation uses `state`,
`remainingAmount`, and `unit`; a missing `state` decodes the old numeric keys as
Available, while Unlimited and Disabled require no numeric fields.

- [ ] **Step 5: Make summary and probes truthful for missing resets**

For equal remaining fractions, `UsageSummary` sorts concrete resets before a
missing reset, then uses window ID for deterministic ties. Change sanitized
probe output fields to `Date?`; do not synthesize a date in either probe.

- [ ] **Step 6: Run the focused and affected core tests**

Run:

```bash
swift test --filter UsageModels
swift test --filter TimelineLayout
swift test --filter UsageSummary
swift test --filter Probe
```

Expected: the new resetless and credit-state tests pass; existing concrete
reset and sanitized-output behavior remains green.

- [ ] **Step 7: Commit the normalized contract**

```bash
git add Sources/UsageMeterCore/Domain/UsageModels.swift \
    Sources/UsageMeterCore/Presentation/TimelineLayout.swift \
    Sources/UsageMeterCore/Presentation/UsageSummary.swift \
    Sources/UsageMeterProbe/ProbeOutput.swift \
    Sources/ClaudeWebProbe/ClaudeWebProbeModel.swift \
    Tests/UsageMeterCoreTests/UsageModelsTests.swift \
    Tests/UsageMeterCoreTests/TimelineLayoutTests.swift \
    Tests/UsageMeterCoreTests/UsageSummaryTests.swift \
    Tests/UsageMeterProbeTests/UsageMeterProbeCommandTests.swift \
    Tests/ClaudeWebProbeTests/ClaudeWebProbeModelTests.swift
git commit -m "Represent inactive usage and credit states"
```

### Task 2: Authoritative Provider Mappings

**Files:**
- Modify: `Sources/UsageMeterCore/Providers/ClaudeUsageDecoder.swift`
- Modify: `Sources/UsageMeterCore/Providers/CodexUsageClient.swift`
- Modify: `Sources/UsageMeterCore/Providers/Factory/FactoryUsageDecoder.swift`
- Modify: `Sources/UsageMeterCore/Providers/OpenCode/OpenCodeZenUsageDecoder.swift`
- Modify: `Tests/UsageMeterCoreTests/ClaudeUsageDecoderTests.swift`
- Modify: `Tests/UsageMeterCoreTests/CodexUsageClientTests.swift`
- Modify: `Tests/UsageMeterCoreTests/FactoryUsageDecoderTests.swift`
- Modify: `Tests/UsageMeterCoreTests/OpenCodeZenUsageDecoderTests.swift`
- Modify: `Tests/UsageMeterCoreTests/Fixtures/claude-usage.json`
- Modify: `Tests/UsageMeterCoreTests/Fixtures/codex-usage.json`
- Modify: `Tests/UsageMeterCoreTests/Fixtures/factory-limits.json`
- Modify: `Tests/UsageMeterClaudeWebTests/Fixtures/claude-usage.json`

**Interfaces:**
- Consumes: Task 1's optional reset and `UsageBalanceValue`.
- Produces: normalized resetless windows and explicit credit values for Claude,
  Codex, Factory, and OpenCode Zen.

- [ ] **Step 1: Add failing Claude inactive-window and credit tests**

Use complete response literals rather than partial decoder mocks:

```swift
@Test
func inactiveClaudeWindowAndDisabledCreditsArePreserved() throws {
    let data = Data(
        """
        {
          "five_hour": {"utilization": 0, "resets_at": null},
          "seven_day": {"utilization": 12, "resets_at": "2026-08-03T21:40:00Z"},
          "extra_usage": {
            "is_enabled": false,
            "user_disabled": true,
            "currency": "USD",
            "decimal_places": 2
          },
          "spend": {"enabled": false, "balance": null}
        }
        """.utf8,
    )

    let snapshot = try ClaudeUsageDecoder().decode(
        data,
        accountID: UUID(),
        fetchedAt: Date(timeIntervalSince1970: 2_000_000_000),
    )

    #expect(snapshot.windows[0].resetAt == nil)
    #expect(snapshot.windows[0].consumedFraction == 0)
    #expect(snapshot.balances.map(\.value) == [.disabled])
}
```

Add a second Claude case where `spend.balance` contains
`amount_minor`, `currency`, and `exponent`; assert the exact Decimal available
amount. Add malformed cases for nonzero/null reset and malformed present
balance.

- [ ] **Step 2: Add failing Codex credit tests**

Cover the real top-level object:

```swift
"credits": {
  "has_credits": true,
  "unlimited": false,
  "balance": "1240.50",
  "overage_limit_reached": false
}
```

Assert `.available(amount: Decimal(string: "1240.50")!, unit: "credits")` and
label `ChatGPT credits`. Add separate response literals for Unlimited,
`has_credits: false` mapping to Disabled, absent `credits` mapping to no row,
and `has_credits: true` with an invalid balance mapping to
`ProviderClientError.unsupportedResponse`.

- [ ] **Step 3: Add failing Factory resetless and allowance tests**

Replace the existing expectation that zero-use/no-end windows stay absent:

```swift
#expect(snapshot.windows.count == 6)
#expect(snapshot.windows.allSatisfy { $0.resetAt == nil })
#expect(snapshot.windows.allSatisfy { $0.consumedFraction == 0 })
#expect(
    snapshot.balances.map(\.value)
        == [.available(amount: Decimal(string: "0")!, unit: "USD")],
)
```

Add `extraUsageAllowed: false` with no balance and assert one Disabled row.
Keep the existing active-without-end rejection test.

- [ ] **Step 4: Run provider tests and verify RED**

Run:

```bash
swift test --filter ClaudeUsageDecoderTests
swift test --filter CodexUsageClientTests
swift test --filter FactoryUsageDecoderTests
swift test --filter OpenCodeZenUsageDecoderTests
```

Expected: the resetless and credit assertions fail against the current
decoders.

- [ ] **Step 5: Implement Claude and Codex mappings**

Make Claude `WindowPayload.resetsAt` optional and pass it unchanged into
`UsageWindow`. Add optional payloads for `extra_usage` and `spend`. Map explicit
disablement first; otherwise map only a structured balance containing:

```swift
struct MoneyPayload: Decodable {
    let amountMinor: Decimal
    let currency: String
    let exponent: Int
}
```

Normalize using Decimal arithmetic:

```swift
let divisor = (0 ..< exponent).reduce(Decimal(1)) { value, _ in
    value * 10
}
let amount = amountMinor / divisor
```

Reject invalid negative exponents, empty currency, or malformed present money.

Extend `CodexUsageResponse` with optional `credits`:

```swift
struct Credits: Decodable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?
}
```

Map Unlimited first, then Disabled when `hasCredits` is false, then parse an
enabled finite Decimal balance. Do not derive balance from `spend_control`.

- [ ] **Step 6: Implement Factory and OpenCode mappings**

When a Factory window has zero use and no end, create a `UsageWindow` with
`resetAt: nil` instead of continuing. Decode `extraUsageAllowed`; explicit false
creates Disabled, and an authoritative cents balance creates Available using
Decimal cents divided by 100. An allowed state without balance remains unknown
and produces no row.

Change OpenCode Zen's existing numeric balance construction to the Decimal
Available initializer. Do not add a status that Zen does not report.

- [ ] **Step 7: Run all provider decoder tests**

Run:

```bash
swift test --filter ClaudeUsageDecoderTests
swift test --filter ClaudeWebUsageClientTests
swift test --filter CodexUsageClientTests
swift test --filter FactoryUsageDecoderTests
swift test --filter OpenCodeZenUsageDecoderTests
```

Expected: every available, unlimited, disabled, absent, resetless, and malformed
case passes without contacting a provider.

- [ ] **Step 8: Commit provider normalization**

```bash
git add Sources/UsageMeterCore/Providers/ClaudeUsageDecoder.swift \
    Sources/UsageMeterCore/Providers/CodexUsageClient.swift \
    Sources/UsageMeterCore/Providers/Factory/FactoryUsageDecoder.swift \
    Sources/UsageMeterCore/Providers/OpenCode/OpenCodeZenUsageDecoder.swift \
    Tests/UsageMeterCoreTests/ClaudeUsageDecoderTests.swift \
    Tests/UsageMeterCoreTests/CodexUsageClientTests.swift \
    Tests/UsageMeterCoreTests/FactoryUsageDecoderTests.swift \
    Tests/UsageMeterCoreTests/OpenCodeZenUsageDecoderTests.swift \
    Tests/UsageMeterCoreTests/Fixtures/claude-usage.json \
    Tests/UsageMeterCoreTests/Fixtures/codex-usage.json \
    Tests/UsageMeterCoreTests/Fixtures/factory-limits.json \
    Tests/UsageMeterClaudeWebTests/Fixtures/claude-usage.json
git commit -m "Decode provider usage credits and inactive windows"
```

### Task 3: Resetless and Extra-Credit Presentation

**Files:**
- Modify: `Sources/UsageMeterUI/Timeline/UsageWindowPresentation.swift`
- Modify: `Tests/UsageMeterUITests/TimelinePresentationTests.swift`

**Interfaces:**
- Consumes: resetless `UsageWindow` and explicit `UsageBalanceValue`.
- Produces: truthful inactive geometry/text and
  `UsageBalanceRowPresentation.valueText` for the Extra Credits grid.

- [ ] **Step 1: Add failing inactive-window presentation tests**

```swift
@Test
func inactiveWindowRendersEmptyFromNowWithoutInventingAReset() throws {
    let account = SubscriptionAccount(
        provider: .factory,
        displayName: "Factory",
        displayOrder: 0,
    )
    let window = try #require(
        UsageWindow(
            id: "factory-standard-five-hour",
            kind: .short,
            duration: 18_000,
            resetAt: nil,
            consumedFraction: 0,
            label: "Standard",
        ),
    )

    let presentation = UsageWindowPresentation(
        account: account,
        window: window,
        now: Date(timeIntervalSince1970: 2_000_000_000),
        timeZone: TimeZone(secondsFromGMT: 0)!,
    )

    #expect(presentation.outerXFraction == 0.5)
    #expect(presentation.outerWidthFraction == 0.5)
    #expect(presentation.fillFraction == 0)
    #expect(presentation.remainingPercentageText == "100%")
    #expect(presentation.relativeResetText == "5h 0m")
    #expect(presentation.exactResetText == nil)
    #expect(presentation.helpText == "No provider reset reported")
    #expect(presentation.accessibilityValue.contains("displayed empty window starts now"))
}
```

- [ ] **Step 2: Add failing Extra Credits row tests**

Create Available USD, Available credits, Unlimited, and Disabled balances.
Assert literal values:

```swift
#expect(usd.valueText == "$38.42")
#expect(credits.valueText == "1,240.5 credits")
#expect(unlimited.valueText == "Unlimited")
#expect(disabled.valueText == "Off")
#expect(disabled.labelText == "Usage credits")
```

Also assert provider/account order and that a snapshot with no balances creates
no Extra Credits row.

- [ ] **Step 3: Run the presentation suite and verify RED**

Run:

```bash
swift test --filter TimelinePresentationTests
```

Expected: compilation fails for optional reset help and `valueText`, then the
new assertions fail until the presentation is implemented.

- [ ] **Step 4: Implement resetless timed presentation**

Make `exactResetText` optional and add `helpText`. For a concrete reset, retain
the existing localized formatter and `Resets …` help. For no reset, derive the
relative text from `window.duration`, keep exact text nil, and use the literal
help `No provider reset reported`. Accessibility must say the allowance is
unused, no provider reset was reported, and the displayed empty window starts
now.

- [ ] **Step 5: Implement explicit credit presentation**

Rename `amountText` to `valueText` and expose `labelText`. Switch on
`balance.value`:

```swift
switch balance.value {
case let .available(amount, unit):
    valueText = Self.format(amount: amount, unit: unit)
case .unlimited:
    valueText = "Unlimited"
case .disabled:
    valueText = "Off"
}
```

Use currency formatting for three-letter ISO currency units and decimal plus
unit formatting otherwise. Format from `NSDecimalNumber(decimal:)`, not a
Double conversion. Keep cycle end in accessibility/help rather than adding a
sixth visible column.

- [ ] **Step 6: Run presentation tests and commit**

Run:

```bash
swift test --filter TimelinePresentationTests
```

Expected: all active, inactive, ordering, formatting, and accessibility tests
pass.

```bash
git add Sources/UsageMeterUI/Timeline/UsageWindowPresentation.swift \
    Tests/UsageMeterUITests/TimelinePresentationTests.swift
git commit -m "Present inactive windows and extra credits"
```

### Task 4: Aligned Timed Grid and Separate Extra Credits Grid

**Files:**
- Modify: `Sources/UsageMeterUI/Timeline/UsageWindowRow.swift`
- Modify: `Sources/UsageMeterUI/Timeline/UsageTimelineView.swift`
- Modify: `Sources/AgenticUsageMeter/AgenticUsageMeterApp.swift`
- Modify: `Tests/UsageMeterUITests/TimelinePresentationTests.swift`

**Interfaces:**
- Consumes: Task 3 presentation rows.
- Produces: one five-column timed grid spanning all sections and one compact
  Extra Credits grid with aligned provider/account/label/value columns.

- [ ] **Step 1: Add a structured presentation assertion for grid identities**

Extend the ordering test to assert provider and account remain independent:

```swift
#expect(timeline.sections[0].rows.map(\.windowPresentation.providerText) == ["Claude", "Codex"])
#expect(timeline.sections[0].rows.map(\.windowPresentation.accountText) == ["Prime", "Personal"])
```

The mutation caught is recombining identity into one string; the test does not
inspect rendered SwiftUI source or layout strings.

- [ ] **Step 2: Run the focused test and verify it fails if the separate account contract is absent**

Run:

```bash
swift test --filter TimelinePresentationTests
```

Expected: any newly introduced independent-label assertion fails until its
literal fixture and presentation values are complete.

- [ ] **Step 3: Render all timed sections in one SwiftUI `Grid`**

Replace each section's independent `VStack`/`HStack` with one parent grid:

```swift
Grid(
    alignment: .leading,
    horizontalSpacing: UsageWindowRow.columnSpacing,
    verticalSpacing: 7,
) {
    ForEach(timeline.sections, id: \.kind) { section in
        timelineHeader(section)
        ForEach(section.rows) { row in
            UsageWindowRow(
                row: row,
                onOpenDashboard: { openAccount(id: row.account.id) },
            )
        }
    }
}
```

`UsageWindowRow` returns a `GridRow` containing:

1. 38-point trailing percentage;
2. 104-point leading provider with the colored dot;
3. 88-point leading account name;
4. flexible timeline;
5. 58-point trailing remaining time.

Keep row height 29 and horizontal spacing 8. The section header uses
`gridCellColumns(3)` for its title, centers **Now** in column four, and leaves
column five empty. Do not render a global column header.

- [ ] **Step 4: Render Extra Credits in its own grid**

After timed sections and a divider, render **Extra Credits** only when rows
exist. Use the same leading dot/provider/account widths, a flexible credit
label, and a 76-point trailing value. The visible columns are provider,
account, credit label, and value; **Available** is not shown as redundant text.
Rows remain tappable through the existing account dashboard callback.

- [ ] **Step 5: Expand sample data for visual acceptance**

Add an inactive Factory account and representative sample balances using the
new domain values. The sample must exercise a numeric USD value, numeric
credits, Off, and an inactive five-hour and weekly row. Keep the visible
`SAMPLE DATA` badge.

- [ ] **Step 6: Build and run focused UI tests**

Run:

```bash
swift test --filter TimelinePresentationTests
swift build --product AgenticUsageMeter
```

Expected: tests pass and the SwiftUI product compiles without layout warnings.

- [ ] **Step 7: Commit the approved rendering**

```bash
git add Sources/UsageMeterUI/Timeline/UsageWindowRow.swift \
    Sources/UsageMeterUI/Timeline/UsageTimelineView.swift \
    Sources/AgenticUsageMeter/AgenticUsageMeterApp.swift \
    Tests/UsageMeterUITests/TimelinePresentationTests.swift
git commit -m "Render aligned usage and extra credit grids"
```

### Task 5: Shared Development and Release Refresh Policy

**Files:**
- Create: `Sources/UsageMeterCore/Refresh/RefreshPolicy.swift`
- Modify: `Sources/UsageMeterCore/Refresh/AccountRefresher.swift`
- Modify: `Sources/UsageMeterUI/AppModel.swift`
- Modify: `Sources/AgenticUsageMeter/AgenticUsageMeterApp.swift`
- Modify: `Tests/UsageMeterCoreTests/AccountRefresherTests.swift`
- Modify: `Tests/UsageMeterUITests/AppModelTests.swift`

**Interfaces:**
- Produces: `RefreshPolicy.development`, `RefreshPolicy.release`, and one
  injected policy used by both automatic cadence and account contact floor.

- [ ] **Step 1: Add failing policy behavior tests**

Add a direct account-floor test using the development policy:

```swift
@Test
func developmentPolicyAllowsAHealthyRequestAtOneMinute() async throws {
    let reference = Date(timeIntervalSince1970: 2_000_000_000)
    let clock = TestDateSource(now: reference)
    let fetcher = SequencedUsageFetcher(outcomes: [
        .success(makeSnapshot(fetchedAt: reference)),
        .success(makeSnapshot(fetchedAt: reference.addingTimeInterval(60))),
    ])
    let refresher = AccountRefresher(
        minimumInterval: RefreshPolicy.development.minimumProviderInterval,
        now: { await clock.current() },
    )

    _ = try await refresher.refresh { try await fetcher.fetch() }
    await clock.advance(by: 60)
    _ = try await refresher.refresh { try await fetcher.fetch() }

    #expect(await fetcher.callCount == 2)
}
```

Change the AppModel automatic-refresh fixture to inject `.development`; assert
the sleeper receives 60 and the second provider request occurs. Keep a release
case asserting 600. Retain the existing transient 600/1200/2400/3600 backoff
test unchanged.

- [ ] **Step 2: Run refresh tests and verify RED**

Run:

```bash
swift test --filter AccountRefresher
swift test --filter automaticRefresh
```

Expected: compilation fails because `RefreshPolicy` and AppModel injection do
not exist.

- [ ] **Step 3: Implement the shared policy**

Create:

```swift
public struct RefreshPolicy: Equatable, Sendable {
    public let automaticInterval: TimeInterval
    public let minimumProviderInterval: TimeInterval

    public init(
        automaticInterval: TimeInterval,
        minimumProviderInterval: TimeInterval
    ) {
        precondition(automaticInterval.isFinite && automaticInterval > 0)
        precondition(minimumProviderInterval.isFinite && minimumProviderInterval > 0)
        self.automaticInterval = automaticInterval
        self.minimumProviderInterval = minimumProviderInterval
    }

    public static let development = RefreshPolicy(
        automaticInterval: 60,
        minimumProviderInterval: 60,
    )
    public static let release = RefreshPolicy(
        automaticInterval: 600,
        minimumProviderInterval: 600,
    )
}
```

Store `refreshPolicy` in `AppModel`, defaulting to `.release`. Every
`AccountRefresher` construction receives
`refreshPolicy.minimumProviderInterval`. `runAutomaticRefresh` sleeps for
`refreshPolicy.automaticInterval` and no longer accepts an independent interval
override.

Make `AccountRefresher`'s default use
`RefreshPolicy.release.minimumProviderInterval`, leaving transient backoff
literals unchanged.

- [ ] **Step 4: Select policy at the executable composition boundary**

In `AppEnvironment.makeModel()`:

```swift
#if DEBUG
let refreshPolicy = RefreshPolicy.development
#else
let refreshPolicy = RefreshPolicy.release
#endif
```

Pass that value into `AppModel`. Do not place compiler conditions inside the
core refresher or tests.

- [ ] **Step 5: Run refresh tests and commit**

Run:

```bash
swift test --filter AccountRefresher
swift test --filter AppModelTests
```

Expected: development cadence and floor are 60 seconds, release cadence and
floor are 600 seconds, manual/wake paths remain gated, and transient backoff is
unchanged.

```bash
git add Sources/UsageMeterCore/Refresh/RefreshPolicy.swift \
    Sources/UsageMeterCore/Refresh/AccountRefresher.swift \
    Sources/UsageMeterUI/AppModel.swift \
    Sources/AgenticUsageMeter/AgenticUsageMeterApp.swift \
    Tests/UsageMeterCoreTests/AccountRefresherTests.swift \
    Tests/UsageMeterUITests/AppModelTests.swift
git commit -m "Apply build-aware refresh policy"
```

### Task 6: Documentation, Full Build, and Live Acceptance

**Files:**
- Modify: `README.md`
- Modify: `docs/provider-qualification.md`

**Interfaces:**
- Consumes: the completed domain, provider, UI, and refresh behavior.
- Produces: current operator documentation and verified release artifact.

- [ ] **Step 1: Update user and qualification documentation**

Change README statements so development builds document the one-minute healthy
floor while release builds retain ten minutes. Document that a provider-returned
zero-use window without a reset is shown as an empty meter beginning at **Now**,
and Extra Credits contains only authoritative balance or explicit state.

Update Factory qualification to replace “omits” with the shipped resetless
representation, and add sanitized Claude/Codex schema qualification notes
without account IDs, balances, or raw payloads.

- [ ] **Step 2: Run formatting and the complete Swift package suite**

Run:

```bash
swift format --in-place --recursive Sources Tests
git diff --check
swift test
```

Expected: formatting changes only touched Swift files already in scope,
`git diff --check` is silent, and the complete suite passes with no failures.

- [ ] **Step 3: Build and assemble the production app**

Run:

```bash
swift build -c release --product AgenticUsageMeter
CONFIGURATION=release scripts/assemble-app.sh
```

Expected: `build/Agentic Usage Meter.app` is freshly assembled from the release
executable.

- [ ] **Step 4: Sign and strictly verify the local artifact**

Use the existing Developer ID Application identity already present in the local
Keychain, then run:

```bash
codesign --force --deep --options runtime --timestamp \
    --sign "Developer ID Application: Jesse Vincent (87WJ58S66M)" \
    "build/Agentic Usage Meter.app"
codesign --verify --deep --strict --verbose=2 \
    "build/Agentic Usage Meter.app"
```

Expected: strict signature verification succeeds. Do not claim notarization or
stapling unless those separate network gates are actually run and pass.

- [ ] **Step 5: Perform live sample-data visual acceptance**

Run:

```bash
open -n "build/Agentic Usage Meter.app" \
    --args --sample-data --show-widget
```

Inspect the real menu-bar popover and widget at 520 points. Verify all current
rows fit at natural height when the screen permits; percentage, provider,
account, timeline, and remaining columns align; inactive bars begin at **Now**;
there is no global header row; Extra Credits is separate and single-line; and
no text overlays a Gantt bar.

- [ ] **Step 6: Qualify current saved accounts without bypassing refresh floors**

Launch the production app normally. For accounts eligible under their persisted
request timestamps, verify Claude, Codex, Factory, and OpenCode results map to
the same values shown by their provider dashboards. Do not force a second
provider request inside the release ten-minute floor and do not print raw
credentials or responses.

- [ ] **Step 7: Commit documentation and any verification-only sample fixes**

```bash
git status --short
git add README.md docs/provider-qualification.md
git commit -m "Document usage levels and extra credits"
```

If live acceptance exposes a product bug, return to RED with a focused behavior
test before changing production code, then rerun the affected task and full
verification.
