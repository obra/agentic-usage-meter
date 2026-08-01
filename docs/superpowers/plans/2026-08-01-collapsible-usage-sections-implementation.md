# Collapsible Usage Sections Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the menu-bar popover and floating widget share and remember per-section collapse choices, rendering collapsed timed quotas as remaining-capacity donut shelves and collapsed balances as neutral icon shelves.

**Architecture:** Add stable usage-section identifiers to the persisted app state and make `AppModel` the observable owner of the collapsed set. Keep `UsageTimelineView` stateless by passing the set and toggle callback from both compact surfaces, while dedicated shelf presentation values and SwiftUI components reuse the existing ordered timeline rows and dashboard routing.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Observation, Swift Testing, SwiftPM, macOS 26

## Global Constraints

- The menu-bar popover and floating widget share one collapse choice for each section.
- Every section defaults expanded, including when loading state saved before this feature.
- The account dashboard remains always expanded.
- Expanded Gantt rows, time axes, and consumed-fill behavior remain unchanged.
- A collapsed timed section renders one donut per visible quota pool; it never aggregates pools.
- Donut arcs represent percentage remaining and start at twelve o'clock.
- A collapsed Extra Credits section renders neutral rings and actual balance or status values, never invented percentages.
- Collapsed items continue to open the existing signed-in account dashboard.
- Provider marks use bundled SVG artwork when available and the current catalog symbol as a deterministic fallback; no icon request is added to provider refresh or rendering.
- Long visible labels truncate, but help and accessibility values retain provider, account, pool, quota, and reset or cycle-end details.
- Tests assert persisted state, presentation values, model behavior, geometry, and accessibility contracts rather than rendered Swift source strings.

## File Structure

- `Sources/UsageMeterCore/Persistence/UsageSectionID.swift` defines stable persisted section identifiers.
- `Sources/UsageMeterCore/Persistence/PersistedAppState.swift` stores the collapsed set and decodes older state with an empty default.
- `Sources/UsageMeterUI/AppModel.swift` owns, toggles, saves, and rolls back shared collapse state.
- `Sources/UsageMeterUI/Timeline/UsageShelfPresentation.swift` derives compact timed-pool and balance values from existing presentation rows.
- `Sources/UsageMeterUI/Resources/ProviderMarks/` contains pinned local SVG artwork and its source note.
- `Sources/UsageMeterUI/Timeline/ProviderMarkView.swift` resolves bundled provider artwork with a catalog-symbol fallback.
- `Sources/UsageMeterUI/Timeline/UsageSectionDisclosureHeader.swift` renders the full-width disclosure control while preserving timeline-column alignment.
- `Sources/UsageMeterUI/Timeline/CollapsedUsageShelf.swift` renders timed donuts and neutral balance cells.
- `Sources/UsageMeterUI/Timeline/UsageTimelineView.swift` switches each section between its existing expanded rows and its collapsed shelf.
- `Sources/UsageMeterUI/MenuBar/MenuBarContentView.swift` passes shared state and toggles into the popover timeline.
- `Sources/UsageMeterUI/Widget/FloatingWidgetView.swift` passes the same shared state and toggles into the floating timeline.
- `Tests/UsageMeterCoreTests/AppStateStoreTests.swift` covers persisted-state round trips and old-state decoding.
- `Tests/UsageMeterUITests/AppModelTests.swift` covers shared state load, persistence, rollback, and collapsed intrinsic height.
- `Tests/UsageMeterUITests/TestSupport.swift` provides a state store that can reject saves for rollback testing.
- `Tests/UsageMeterUITests/TimelinePresentationTests.swift` covers one-cell-per-pool semantics, remaining progress, labels, and balance values.

---

### Task 1: Persist and Own Collapsed Section State

**Files:**
- Create: `Sources/UsageMeterCore/Persistence/UsageSectionID.swift`
- Modify: `Sources/UsageMeterCore/Persistence/PersistedAppState.swift`
- Modify: `Sources/UsageMeterUI/AppModel.swift`
- Modify: `Tests/UsageMeterCoreTests/AppStateStoreTests.swift`
- Modify: `Tests/UsageMeterUITests/AppModelTests.swift`
- Modify: `Tests/UsageMeterUITests/TestSupport.swift`

**Interfaces:**
- Consumes: `AppStatePersisting`, `PersistedAppState`, and the existing save-and-rollback pattern used by floating-widget preferences.
- Produces: `UsageSectionID`, `AppModel.collapsedUsageSections`, and `AppModel.toggleUsageSection(_:) async throws`.

- [x] **Step 1: Write the failing persisted-state compatibility tests**

Extend `AppStateStoreTests` with a round-trip assertion using a nonempty collapsed set and a direct decoder test for the previous JSON shape:

```swift
@Test
func persistedStateRoundTripsCollapsedUsageSections() throws {
  let state = PersistedAppState(
    accounts: [],
    snapshots: [:],
    collapsedUsageSections: [.short, .extraCredits],
  )

  let data = try JSONEncoder().encode(state)
  let decoded = try JSONDecoder().decode(PersistedAppState.self, from: data)

  #expect(decoded.collapsedUsageSections == [.short, .extraCredits])
}

@Test
func stateSavedBeforeCollapseSupportDefaultsExpanded() throws {
  let data = Data(
    #"{"accounts":[],"snapshots":{},"refreshStates":{},"isFloatingWidgetVisible":false,"floatingWidgetPlacement":null}"#.utf8,
  )

  let decoded = try JSONDecoder().decode(PersistedAppState.self, from: data)

  #expect(decoded.collapsedUsageSections.isEmpty)
}
```

- [x] **Step 2: Run the focused core tests and verify RED**

Run:

```bash
swift test --filter persistedStateRoundTripsCollapsedUsageSections
swift test --filter stateSavedBeforeCollapseSupportDefaultsExpanded
```

Expected: compilation fails because `UsageSectionID` and `collapsedUsageSections` do not exist.

- [x] **Step 3: Add stable section identifiers and compatible state coding**

Create `UsageSectionID.swift`:

```swift
public enum UsageSectionID: String, Codable, CaseIterable, Hashable, Sendable {
  case short
  case daily
  case weekly
  case monthly
  case custom
  case extraCredits = "extra-credits"
}
```

Add this initializer parameter and stored property to `PersistedAppState`:

```swift
public var collapsedUsageSections: Set<UsageSectionID>

public init(
  accounts: [SubscriptionAccount],
  snapshots: [UUID: UsageSnapshot],
  refreshStates: [UUID: AccountRefreshState] = [:],
  isFloatingWidgetVisible: Bool = false,
  floatingWidgetPlacement: FloatingWidgetPlacement? = nil,
  collapsedUsageSections: Set<UsageSectionID> = [],
) {
  self.accounts = accounts
  self.snapshots = snapshots
  self.refreshStates = refreshStates
  self.isFloatingWidgetVisible = isFloatingWidgetVisible
  self.floatingWidgetPlacement = floatingWidgetPlacement
  self.collapsedUsageSections = collapsedUsageSections
}
```

Implement `CodingKeys`, `init(from:)`, and `encode(to:)` explicitly. Decode the five existing fields with their current required/optional behavior and decode only the new field with:

```swift
collapsedUsageSections = try container.decodeIfPresent(
  Set<UsageSectionID>.self,
  forKey: .collapsedUsageSections,
) ?? []
```

Keep `.empty.collapsedUsageSections` empty.

- [x] **Step 4: Run the focused core tests and verify GREEN**

Run:

```bash
swift test --filter persistedStateRoundTripsCollapsedUsageSections
swift test --filter stateSavedBeforeCollapseSupportDefaultsExpanded
swift test --filter stateStore
```

Expected: PASS.

- [x] **Step 5: Write failing model persistence and rollback tests**

Extend `TestAppStateStore` with a default-nil `saveError: TestAppStateStoreError?` and throw it before assigning state. Define:

```swift
enum TestAppStateStoreError: Error, Equatable, Sendable {
  case saveRejected
}
```

Add these `AppModelTests`:

```swift
@Test
func collapsedUsageSectionsLoadAndPersist() async throws {
  let stateStore = TestAppStateStore(
    state: PersistedAppState(
      accounts: [],
      snapshots: [:],
      collapsedUsageSections: [.weekly],
    ),
  )
  let model = AppModel(
    stateStore: stateStore,
    credentialStore: TestCredentialStore(),
    adapters: [],
    now: { reference },
  )

  await model.start()
  #expect(model.collapsedUsageSections == [.weekly])

  try await model.toggleUsageSection(.short)

  #expect(model.collapsedUsageSections == [.short, .weekly])
  #expect(
    await stateStore.state.collapsedUsageSections == [.short, .weekly],
  )
}

@Test
func rejectedCollapseSaveRollsBackObservableState() async {
  let stateStore = TestAppStateStore(
    state: .empty,
    saveError: .saveRejected,
  )
  let model = AppModel(
    stateStore: stateStore,
    credentialStore: TestCredentialStore(),
    adapters: [],
    now: { reference },
  )
  await model.start()

  await #expect(throws: TestAppStateStoreError.saveRejected) {
    try await model.toggleUsageSection(.weekly)
  }

  #expect(model.collapsedUsageSections.isEmpty)
  #expect(await stateStore.state.collapsedUsageSections.isEmpty)
}
```

- [x] **Step 6: Run the model tests and verify RED**

Run:

```bash
swift test --filter collapsedUsageSectionsLoadAndPersist
swift test --filter rejectedCollapseSaveRollsBackObservableState
```

Expected: compilation fails because `AppModel` does not expose or toggle collapse state.

- [x] **Step 7: Implement shared AppModel ownership**

Add the observable state:

```swift
public private(set) var collapsedUsageSections: Set<UsageSectionID> = []
```

Load it beside the existing widget preferences in `start()`, and implement the existing optimistic-save/rollback pattern:

```swift
public func toggleUsageSection(_ section: UsageSectionID) async throws {
  let previous = collapsedUsageSections
  if collapsedUsageSections.contains(section) {
    collapsedUsageSections.remove(section)
  } else {
    collapsedUsageSections.insert(section)
  }
  persistedState.collapsedUsageSections = collapsedUsageSections
  do {
    try await stateStore.save(persistedState)
  } catch {
    collapsedUsageSections = previous
    persistedState.collapsedUsageSections = previous
    throw error
  }
}
```

- [x] **Step 8: Run focused and full model tests**

Run:

```bash
swift test --filter collapsedUsageSectionsLoadAndPersist
swift test --filter rejectedCollapseSaveRollsBackObservableState
swift test --filter AppModelTests
```

Expected: PASS.

- [x] **Step 9: Commit persisted collapse state**

```bash
git add Sources/UsageMeterCore/Persistence/UsageSectionID.swift Sources/UsageMeterCore/Persistence/PersistedAppState.swift Sources/UsageMeterUI/AppModel.swift Tests/UsageMeterCoreTests/AppStateStoreTests.swift Tests/UsageMeterUITests/AppModelTests.swift Tests/UsageMeterUITests/TestSupport.swift
git commit -m "Persist collapsed usage sections" -m "Add stable section identifiers and compatible state decoding so existing installations remain fully expanded. Make AppModel the shared observable owner and persist each toggle with rollback on save failure."
```

---

### Task 2: Derive Truthful Collapsed Shelf Values

**Files:**
- Create: `Sources/UsageMeterUI/Timeline/UsageShelfPresentation.swift`
- Modify: `Tests/UsageMeterUITests/TimelinePresentationTests.swift`

**Interfaces:**
- Consumes: `UsageTimelineRowPresentation`, `UsageBalanceRowPresentation`, `UsageWindow.remainingFraction`, and existing accessibility strings.
- Produces: `UsagePoolShelfItemPresentation` and `UsageBalanceShelfItemPresentation`, each preserving the source row ID and account routing information.

- [x] **Step 1: Write failing timed-pool shelf tests**

Add a test that constructs a Factory short section with active Standard and Droid Core pools, then maps every section row into a shelf item:

```swift
@Test
func collapsedShelfKeepsEachPoolAndUsesRemainingCapacity() throws {
  let account = SubscriptionAccount(
    provider: .factory,
    displayName: "Factory Work",
    displayOrder: 0,
  )
  let windows = try [
    UsageWindow(
      id: "standard",
      kind: .short,
      duration: 18_000,
      resetAt: Date(timeIntervalSince1970: 2_000_018_000),
      consumedFraction: 0.4,
      label: "Standard",
    ),
    UsageWindow(
      id: "core",
      kind: .short,
      duration: 18_000,
      resetAt: Date(timeIntervalSince1970: 2_000_018_000),
      consumedFraction: 0.2,
      label: "Droid Core",
    ),
  ].compactMap { $0 }
  let state = AccountViewState(
    account: account,
    snapshot: UsageSnapshot(
      accountID: account.id,
      fetchedAt: Date(timeIntervalSince1970: 2_000_000_000),
      windows: windows,
    ),
  )
  let section = UsageTimelineSectionPresentation(
    kind: .short,
    accounts: [state],
    now: Date(timeIntervalSince1970: 2_000_000_000),
    timeZone: TimeZone(secondsFromGMT: 0)!,
  )

  let items = section.rows.map(UsagePoolShelfItemPresentation.init)

  #expect(items.map(\.id) == section.rows.map(\.id))
  #expect(items.map(\.accountText) == ["Factory Work", "Factory Work"])
  #expect(items.map(\.detailText) == ["60% · Standard", "80% · Droid Core"])
  #expect(items.map(\.remainingFraction) == [0.6, 0.8])
  #expect(items[1].accessibilityValue.contains("Droid Core five-hour window"))
}
```

- [x] **Step 2: Write the failing Extra Credits shelf test**

Add this test using the real balance presentation:

```swift
@Test
func collapsedBalanceShelfUsesActualStatus() throws {
  let account = SubscriptionAccount(
    provider: .claude,
    displayName: "Prime",
    displayOrder: 0,
  )
  let balance = try #require(
    UsageBalance(
      id: "usage-credits",
      label: "Usage credits",
      value: .disabled,
    ),
  )
  let row = UsageBalanceRowPresentation(
    account: account,
    balance: balance,
    timeZone: TimeZone(secondsFromGMT: 0)!,
  )

  let item = UsageBalanceShelfItemPresentation(row)

  #expect(item.accountText == "Prime")
  #expect(item.detailText == "Off")
  #expect(item.accessibilityValue.contains("Usage credits"))
}
```

The balance presentation intentionally has no remaining-fraction property.

- [x] **Step 3: Run the presentation tests and verify RED**

Run:

```bash
swift test --filter collapsedShelfKeepsEachPoolAndUsesRemainingCapacity
swift test --filter collapsedBalanceShelfUsesActualStatus
```

Expected: compilation fails because the shelf presentation types do not exist.

- [x] **Step 4: Implement the focused shelf presentation values**

Create `UsageShelfPresentation.swift` with value types shaped as follows:

```swift
struct UsagePoolShelfItemPresentation: Equatable, Identifiable, Sendable {
  let id: String
  let account: SubscriptionAccount
  let accountText: String
  let detailText: String
  let remainingFraction: Double
  let accessibilityValue: String

  init(_ row: UsageTimelineRowPresentation) {
    id = row.id
    account = row.account
    accountText = row.account.displayName.trimmingCharacters(
      in: .whitespacesAndNewlines,
    )
    let percentage = row.windowPresentation.remainingPercentageText
    detailText = row.window.label.map { "\(percentage) · \($0)" }
      ?? percentage
    remainingFraction = row.window.remainingFraction
    accessibilityValue = row.windowPresentation.accessibilityValue
  }
}

struct UsageBalanceShelfItemPresentation: Equatable, Identifiable, Sendable {
  let id: String
  let account: SubscriptionAccount
  let accountText: String
  let detailText: String
  let accessibilityValue: String

  init(_ row: UsageBalanceRowPresentation) {
    id = row.id
    account = row.account
    accountText = row.accountText
    detailText = row.valueText
    accessibilityValue = row.helpText
  }
}
```

Do not regroup rows by account. Existing section and balance ordering remains authoritative.

- [x] **Step 5: Run the presentation suite and verify GREEN**

Run:

```bash
swift test --filter collapsedShelfKeepsEachPoolAndUsesRemainingCapacity
swift test --filter collapsedBalanceShelfUsesActualStatus
swift test --filter TimelinePresentationTests
```

Expected: PASS.

- [x] **Step 6: Commit collapsed shelf presentation**

```bash
git add Sources/UsageMeterUI/Timeline/UsageShelfPresentation.swift Tests/UsageMeterUITests/TimelinePresentationTests.swift
git commit -m "Derive collapsed usage shelf values" -m "Preserve one summary item per visible quota pool, expose remaining rather than consumed capacity, keep provider labels, and carry existing reset and balance accessibility details into the compact shelf."
```

---

### Task 3: Render and Wire Collapsible Donut Shelves

**Files:**
- Modify: `Package.swift`
- Create: `Sources/UsageMeterUI/Resources/ProviderMarks/claude.svg`
- Create: `Sources/UsageMeterUI/Resources/ProviderMarks/kimi.svg`
- Create: `Sources/UsageMeterUI/Resources/ProviderMarks/minimax.svg`
- Create: `Sources/UsageMeterUI/Resources/ProviderMarks/github-copilot.svg`
- Create: `Sources/UsageMeterUI/Resources/ProviderMarks/google.svg`
- Create: `Sources/UsageMeterUI/Resources/ProviderMarks/opencode.svg`
- Create: `Sources/UsageMeterUI/Resources/ProviderMarks/factory.svg`
- Create: `Sources/UsageMeterUI/Resources/ProviderMarks/grok.svg`
- Create: `Sources/UsageMeterUI/Resources/ProviderMarks/ATTRIBUTION.md`
- Create: `Sources/UsageMeterUI/Timeline/ProviderMarkView.swift`
- Create: `Sources/UsageMeterUI/Timeline/UsageSectionDisclosureHeader.swift`
- Create: `Sources/UsageMeterUI/Timeline/CollapsedUsageShelf.swift`
- Modify: `Sources/UsageMeterUI/Timeline/UsageTimelineView.swift`
- Modify: `Sources/UsageMeterUI/MenuBar/MenuBarContentView.swift`
- Modify: `Sources/UsageMeterUI/Widget/FloatingWidgetView.swift`
- Modify: `Tests/UsageMeterUITests/AppModelTests.swift`
- Create: `Tests/UsageMeterUITests/ProviderMarkTests.swift`

**Interfaces:**
- Consumes: `UsageSectionID`, `AppModel.collapsedUsageSections`, `AppModel.toggleUsageSection(_:)`, the shelf presentation values from Task 2, bundled provider SVGs, and `ProviderCatalog.systemImage`.
- Produces: `UsageTimelineView.init(accounts:now:timeZone:collapsedSections:onToggleSection:onOpenAccount:)`, disclosure headers, timed donut shelves, and neutral balance shelves.

- [ ] **Step 1: Write the failing collapsed-height behavior test**

Add this `AppModelTests` behavior test. It creates five real presentation rows so a shelf is materially shorter than its expanded rows:

```swift
@Test
func collapsedTimelineHasSmallerIntrinsicHeight() throws {
  let accounts = try (0 ..< 5).map { index in
    let account = SubscriptionAccount(
      provider: .claude,
      displayName: "Account \(index + 1)",
      displayOrder: index,
    )
    let window = try #require(
      UsageWindow(
        id: "short-\(index)",
        kind: .short,
        duration: 18_000,
        resetAt: reference.addingTimeInterval(18_000),
        consumedFraction: Double(index) / 10,
      ),
    )
    return AccountViewState(
      account: account,
      snapshot: UsageSnapshot(
        accountID: account.id,
        fetchedAt: reference,
        windows: [window],
      ),
    )
  }
  let expanded = NSHostingView(
    rootView: UsageTimelineView(
      accounts: accounts,
      now: reference,
    )
    .frame(width: UsageTimelineMetrics.naturalWidth),
  )
  let collapsed = NSHostingView(
    rootView: UsageTimelineView(
      accounts: accounts,
      now: reference,
      collapsedSections: [.short],
      onToggleSection: { _ in },
    )
    .frame(width: UsageTimelineMetrics.naturalWidth),
  )

  #expect(collapsed.fittingSize.height < expanded.fittingSize.height)
}
```

This test catches a collapse implementation that merely hides content visually without removing expanded rows from intrinsic layout.

- [ ] **Step 2: Run the view behavior test and verify RED**

Run:

```bash
swift test --filter collapsedTimelineHasSmallerIntrinsicHeight
```

Expected: compilation fails because `UsageTimelineView` has no collapse inputs.

- [ ] **Step 3: Bundle and verify local provider marks**

Add `.process("Resources")` to the `UsageMeterUI` target in `Package.swift`. Save these exact sources under the resource filenames listed above:

```text
https://cdn.jsdelivr.net/npm/simple-icons@v16/icons/claude.svg
https://cdn.jsdelivr.net/npm/simple-icons@v16/icons/kimi.svg
https://cdn.jsdelivr.net/npm/simple-icons@v16/icons/minimax.svg
https://cdn.jsdelivr.net/npm/simple-icons@v16/icons/githubcopilot.svg
https://cdn.jsdelivr.net/npm/simple-icons@v16/icons/google.svg
https://cdn.jsdelivr.net/npm/simple-icons@v16/icons/opencode.svg
https://factory.ai/favicon.svg
https://grok.com/images/favicon.svg
```

`ATTRIBUTION.md` records those URLs, the 2026-08-01 retrieval date, Simple Icons v16's CC0 package license and trademark disclaimer, and that the Factory and Grok files came from their official favicon endpoints.

Create `ProviderMarkTests.swift` with this real resource-loading test. Codex intentionally exercises the deterministic catalog-symbol fallback because no vetted bundled artwork is introduced by this task:

```swift
import Testing
import UsageMeterCore

@testable import UsageMeterUI

@Test
func providerMarkResourcesLoad() {
  let bundledProviders: [Provider] = [
    .claude,
    .kimi,
    .minimax,
    .githubCopilot,
    .antigravity,
    .factory,
    .openCodeGo,
    .openCodeZen,
    .superGrok,
  ]

  for provider in bundledProviders {
    #expect(ProviderMarkImageLoader.image(for: provider) != nil)
  }
  #expect(ProviderMarkImageLoader.image(for: .codex) == nil)
}
```

Run `swift test --filter providerMarkResourcesLoad` before adding the loader and verify compilation fails because `ProviderMarkImageLoader` does not exist.

`ProviderMarkView` uses the bundled image when available and falls back to the catalog symbol:

```swift
extension Provider {
  fileprivate var markResourceName: String? {
    switch self {
    case .claude:
      "claude"
    case .codex:
      nil
    case .kimi:
      "kimi"
    case .minimax:
      "minimax"
    case .githubCopilot:
      "github-copilot"
    case .antigravity:
      "google"
    case .factory:
      "factory"
    case .openCodeGo, .openCodeZen:
      "opencode"
    case .superGrok:
      "grok"
    }
  }
}

enum ProviderMarkImageLoader {
  static func image(for provider: Provider) -> NSImage? {
    guard let resourceName = provider.markResourceName,
          let url = Bundle.module.url(
            forResource: resourceName,
            withExtension: "svg",
            subdirectory: "ProviderMarks",
          )
    else {
      return nil
    }
    return NSImage(contentsOf: url)
  }
}

struct ProviderMarkView: View {
  let provider: Provider

  var body: some View {
    if let image = ProviderMarkImageLoader.image(for: provider) {
      Image(nsImage: image)
        .resizable()
        .renderingMode(.template)
        .scaledToFit()
        .foregroundStyle(provider.timelineColor)
    } else if let definition = ProviderCatalog.live.definition(for: provider) {
      Image(systemName: definition.systemImage)
        .resizable()
        .scaledToFit()
        .foregroundStyle(provider.timelineColor)
    } else {
      Text(String(provider.rawValue.prefix(1)).uppercased())
        .font(.caption2.weight(.bold))
        .foregroundStyle(provider.timelineColor)
    }
  }
}
```

The template rendering keeps monochrome artwork provider-colored and adaptive. OpenCode Go and Zen share the OpenCode resource; Antigravity uses the Google resource.

- [ ] **Step 4: Implement the remaining-capacity and balance ring cells**

In `CollapsedUsageShelf`, use adaptive equal-width columns:

```swift
private let columns = [
  GridItem(.adaptive(minimum: 56, maximum: 72), spacing: 4),
]
```

Render a 28-point timed ring with a neutral full-circle track and a trimmed provider-colored arc:

```swift
ZStack {
  Circle()
    .stroke(.quaternary, lineWidth: 3)
  Circle()
    .trim(from: 0, to: item.remainingFraction)
    .stroke(
      item.account.provider.timelineColor,
      style: StrokeStyle(lineWidth: 3, lineCap: .round),
    )
    .rotationEffect(.degrees(-90))
  ProviderMarkView(provider: item.account.provider)
    .frame(width: 13, height: 13)
}
.frame(width: 28, height: 28)
```

Below it, render one-line account text and monospaced secondary detail text. The balance variant uses only the neutral circle around the same mark. Both cells are plain buttons that call the supplied account callback, expose the complete accessibility value, and use the same text for `.help`.

- [ ] **Step 5: Implement the disclosure header**

Build `UsageSectionDisclosureHeader` with explicit title, optional aligned `Now` label, expanded state, and optional toggle. When a toggle exists, wrap the full header content in a plain button and expose `"Collapse <title>"` or `"Expand <title>"`; otherwise render the content unchanged without a chevron. Keep the title region at the existing `identityColumnsWidth` so expanded axes remain aligned:

```swift
struct UsageSectionDisclosureHeader: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let title: String
  let identityColumnsWidth: CGFloat
  let showsTimelineColumns: Bool
  let isExpanded: Bool
  let onToggle: (() -> Void)?

  var body: some View {
    if let onToggle {
      Button(action: onToggle) {
        content
      }
      .buttonStyle(.plain)
      .contentShape(Rectangle())
      .accessibilityLabel(
        "\(isExpanded ? "Collapse" : "Expand") \(title)",
      )
    } else {
      content
    }
  }

  private var content: some View {
    HStack(spacing: UsageTimelineMetrics.columnSpacing) {
      HStack(spacing: 4) {
        if onToggle != nil {
          Image(systemName: "chevron.down")
            .font(.caption2.weight(.semibold))
            .rotationEffect(.degrees(isExpanded ? 0 : -90))
            .animation(
              reduceMotion ? nil : .easeInOut(duration: 0.15),
              value: isExpanded,
            )
        }
        Text(title)
          .font(.headline)
      }
      .frame(
        width: showsTimelineColumns ? identityColumnsWidth : nil,
        alignment: .leading,
      )

      if showsTimelineColumns {
        Text(isExpanded ? "Now" : "")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
        Color.clear
          .frame(width: UsageTimelineMetrics.resetColumnWidth)
      } else {
        Spacer()
      }
    }
  }
}
```

- [ ] **Step 6: Switch timeline sections between rows and shelves**

Extend `UsageTimelineView` with defaulted inputs so the account dashboard remains source-compatible:

```swift
public init(
  accounts: [AccountViewState],
  now: Date = Date(),
  timeZone: TimeZone = .autoupdatingCurrent,
  collapsedSections: Set<UsageSectionID> = [],
  onToggleSection: ((UsageSectionID) -> Void)? = nil,
  onOpenAccount: ((AccountViewState) -> Void)? = nil,
)
```

Map `UsageWindowKind` to its matching `UsageSectionID`. For each timed section, render the disclosure header and either its existing `UsageWindowRow` loop or `CollapsedUsagePoolShelf`. Apply the same choice to Extra Credits using `.extraCredits` and `CollapsedUsageBalanceShelf`. Keep the divider between timed sections and Extra Credits.

Add the complete mapping beside the timeline view:

```swift
extension UsageWindowKind {
  fileprivate var sectionID: UsageSectionID {
    switch self {
    case .short:
      .short
    case .daily:
      .daily
    case .weekly:
      .weekly
    case .monthly:
      .monthly
    case .custom:
      .custom
    }
  }
}
```

Use this branch shape so collapsed rows leave intrinsic layout rather than merely becoming invisible:

```swift
let sectionID = section.kind.sectionID
let isCollapsed =
  onToggleSection != nil
  && collapsedSections.contains(sectionID)

UsageSectionDisclosureHeader(
  title: section.title,
  identityColumnsWidth: identityColumnsWidth,
  showsTimelineColumns: true,
  isExpanded: !isCollapsed,
  onToggle: onToggleSection.map { toggle in
    { toggle(sectionID) }
  },
)

if isCollapsed {
  CollapsedUsagePoolShelf(
    rows: section.rows,
    onOpenAccount: openAccount,
  )
} else {
  ForEach(section.rows) { row in
    UsageWindowRow(
      row: row,
      onOpenDashboard: { openAccount(id: row.account.id) },
    )
  }
}
```

- [ ] **Step 7: Wire both compact surfaces to the same model state**

In both `MenuBarContentView.timeline` and `FloatingWidgetView.timeline`, pass:

```swift
collapsedSections: model.collapsedUsageSections,
onToggleSection: { section in
  Task {
    try? await model.toggleUsageSection(section)
  }
},
```

Leave `AccountDashboardView` unchanged so its default timeline remains expanded and has no disclosure controls.

- [ ] **Step 8: Run focused UI tests and verify GREEN**

Run:

```bash
swift test --filter collapsedTimelineHasSmallerIntrinsicHeight
swift test --filter providerMarkResourcesLoad
swift test --filter AppModelTests
swift test --filter TimelinePresentationTests
```

Expected: PASS, with the collapsed timeline reporting a smaller intrinsic height.

- [ ] **Step 9: Commit collapsible shelf rendering**

```bash
git add Package.swift Sources/UsageMeterUI/Resources/ProviderMarks Sources/UsageMeterUI/Timeline/ProviderMarkView.swift Sources/UsageMeterUI/Timeline/UsageSectionDisclosureHeader.swift Sources/UsageMeterUI/Timeline/CollapsedUsageShelf.swift Sources/UsageMeterUI/Timeline/UsageTimelineView.swift Sources/UsageMeterUI/MenuBar/MenuBarContentView.swift Sources/UsageMeterUI/Widget/FloatingWidgetView.swift Tests/UsageMeterUITests/AppModelTests.swift Tests/UsageMeterUITests/ProviderMarkTests.swift
git commit -m "Render collapsible usage donut shelves" -m "Turn compact-surface section headers into shared disclosure controls. Replace collapsed timed rows with remaining-capacity donuts, keep balances neutral, retain account dashboard routing and accessibility context, and let both surfaces follow AppModel's persisted state."
```

---

### Task 4: Build and Verify the Complete Application

**Files:**
- Verify: all modified source, test, and documentation files

**Interfaces:**
- Consumes: the complete persisted-state, presentation, and SwiftUI implementation from Tasks 1 through 3.
- Produces: automated, assembled-app, persistence, shared-surface, and live visual acceptance evidence.

- [ ] **Step 1: Run the complete Swift package test suite**

Run:

```bash
swift test
```

Expected: every suite passes with no failures.

- [ ] **Step 2: Build the executable product**

Run:

```bash
swift build --product AgenticUsageMeter
```

Expected: the debug executable builds successfully.

- [ ] **Step 3: Assemble and verify the application bundle**

Run:

```bash
CONFIGURATION=debug scripts/assemble-app.sh
codesign --force --deep --sign - "build/Agentic Usage Meter.app"
codesign --verify --deep --strict --verbose=2 "build/Agentic Usage Meter.app"
```

Expected: the current executable is copied into `build/Agentic Usage Meter.app` and strict ad-hoc signature verification succeeds.

- [ ] **Step 4: Launch representative sample data**

Run:

```bash
open -n "build/Agentic Usage Meter.app" --args --sample-data --show-widget
```

Expected: the newly assembled floating widget opens with representative timed and balance sections.

- [ ] **Step 5: Perform live interaction and visual acceptance**

Verify on the running product:

- all sections begin expanded with existing Gantt rows unchanged;
- the full section header toggles and its chevron follows state;
- a collapsed timed section shows one 28-point remaining-capacity donut per visible pool, account names, precise percentages, and pool labels when present;
- five shelf cells fit the current production width without horizontal scrolling;
- Extra Credits shows neutral rings and actual values;
- the floating widget shrinks after collapse without clipping;
- opening the menu-bar popover shows the same collapsed sections;
- toggling in one surface updates the other immediately;
- quitting and relaunching preserves the collapsed set;
- clicking a shelf cell opens the correct account dashboard;
- VoiceOver/help text includes the full provider, account, pool, percentage, and reset or balance-cycle context.

- [ ] **Step 6: Inspect the final diff and working tree**

Run:

```bash
git diff --check
git status --short
git log -6 --oneline --decorate
```

Expected: no whitespace errors, all nontrivial implementation is committed, and only intentional generated build artifacts remain outside version control.
