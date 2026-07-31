# Compact Usage Timeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce the menu-bar and floating-widget footprint, distinguish Factory's active pools without displaying dormant Droid Core rows, shorten GitHub's provider label, and preserve provider-supplied Kimi window presence.

**Architecture:** Keep provider decoding lossless and make Factory Core visibility a timeline-presentation concern. Centralize the shared 460-point layout metrics in `UsageMeterUI`, then have the row, section, popover, widget, and widget controller consume those metrics so density cannot drift across surfaces.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Swift Testing, SwiftPM, macOS 26

## Global Constraints

- The menu-bar popover and naturally placed floating widget use a 460-point natural width.
- Rows are 23 points high, Gantt bars are 12 points high, and now lines are 18 points high.
- Columns remain percentage, provider, account or pool, Gantt timeline, and reset.
- Factory Standard always remains visible.
- Factory Droid Core remains hidden until any Core window has a positive consumed fraction; then every returned Core window is visible.
- Kimi renders only provider-supplied windows; never synthesize a five-hour row or reset.
- Existing user-editable account names and saved manual floating-widget placements remain unchanged.
- Tests assert domain and window behavior, not rendered SwiftUI source strings.

## File Structure

- `Sources/UsageMeterUI/Timeline/UsageWindowPresentation.swift` owns Factory window visibility, pool-label decisions, and accessibility copy.
- `Sources/UsageMeterUI/Timeline/UsageTimelineMetrics.swift` owns shared density and natural-width constants.
- `Sources/UsageMeterUI/Timeline/UsageWindowRow.swift` renders the compact aligned row and Gantt geometry.
- `Sources/UsageMeterUI/Timeline/UsageTimelineView.swift` renders compact section and Extra Credits spacing.
- `Sources/UsageMeterUI/MenuBar/MenuBarContentView.swift` owns compact popover padding and width.
- `Sources/UsageMeterUI/Widget/FloatingWidgetView.swift` owns compact floating-widget padding and width.
- `Sources/UsageMeterUI/Widget/FloatingWidgetController.swift` applies the natural widget size while preserving saved placements.
- `Sources/UsageMeterCore/Providers/ProviderCatalog.swift` supplies the short GitHub provider label.
- `Sources/AgenticUsageMeter/AgenticUsageMeterApp.swift` supplies representative inactive Factory sample pools.
- `Tests/UsageMeterUITests/TimelinePresentationTests.swift` covers dormant and active Factory presentation.
- `Tests/UsageMeterUITests/AppModelTests.swift` covers natural floating-widget sizing.
- `Tests/UsageMeterCoreTests/ProviderCatalogTests.swift` covers the GitHub catalog label.
- `docs/provider-qualification.md` records the verified Factory fallback semantics and Kimi response boundary.

---

### Task 1: Present Factory Core Only After Core Usage Begins

**Files:**
- Modify: `Sources/UsageMeterUI/Timeline/UsageWindowPresentation.swift`
- Modify: `Sources/AgenticUsageMeter/AgenticUsageMeterApp.swift`
- Modify: `Tests/UsageMeterUITests/TimelinePresentationTests.swift`
- Modify: `docs/provider-qualification.md`

**Interfaces:**
- Consumes: `AccountViewState.snapshot`, `UsageWindow.label`, and `UsageWindow.consumedFraction`.
- Produces: `UsageTimelineSectionPresentation.rows` with dormant Factory Core windows removed and active pool rows labeled.

- [ ] **Step 1: Write the failing dormant-Core presentation test**

Add a test that builds one Factory account with zero-use Standard and Droid Core weekly windows:

```swift
@Test
func dormantFactoryCoreWindowsStayHidden() throws {
  let account = SubscriptionAccount(
    provider: .factory,
    displayName: "Factory",
    displayOrder: 0,
  )
  let windows = try [
    UsageWindow(
      id: "factory-standard-weekly",
      kind: .weekly,
      duration: 604_800,
      resetAt: nil,
      consumedFraction: 0,
      label: "Standard",
    ),
    UsageWindow(
      id: "factory-core-weekly",
      kind: .weekly,
      duration: 604_800,
      resetAt: nil,
      consumedFraction: 0,
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
    kind: .weekly,
    accounts: [state],
    now: Date(timeIntervalSince1970: 2_000_000_000),
    timeZone: TimeZone(secondsFromGMT: 0)!,
  )

  #expect(section.rows.map(\.window.id) == ["factory-standard-weekly"])
  #expect(section.rows[0].windowPresentation.accountText == "Factory")
  #expect(
    section.rows[0].windowPresentation.accessibilityValue.contains(
      "Standard weekly window",
    ),
  )
}
```

- [ ] **Step 2: Strengthen the active-Core test**

Extend `repeatedAccountWindowsShowTheirPoolLabels()` so the snapshot contains
zero-use Core short and monthly windows in addition to a positive Core weekly
window. Assert that constructing short, weekly, and monthly sections exposes
all three Core IDs. This proves visibility is decided across the account's
whole snapshot rather than separately per section.

- [ ] **Step 3: Run the focused tests and verify RED**

Run:

```bash
swift test --filter dormantFactoryCoreWindowsStayHidden
swift test --filter repeatedAccountWindowsShowTheirPoolLabels
```

Expected: the dormant test fails because both Standard and Droid Core rows are
currently returned. The active test may already pass its existing pool-label
assertions but fails its new cross-section assertions until account-wide Core
visibility is implemented.

- [ ] **Step 4: Implement account-wide Factory Core visibility**

In `UsageTimelineSectionPresentation.init`, inspect all snapshot windows before
filtering to the section kind:

```swift
let sourceWindows = state.snapshot?.windows ?? []
let showsFactoryCore =
  state.account.provider == .factory
  && sourceWindows.contains {
    $0.label == "Droid Core" && $0.consumedFraction > 0
  }

return sourceWindows
  .filter { $0.kind == kind }
  .filter {
    state.account.provider != .factory
      || $0.label != "Droid Core"
      || showsFactoryCore
  }
  .map { window in
    (account: state.account, window: window)
  }
```

Keep `showsWindowLabel` based on the number of visible windows for the account
and kind. In `UsageWindowPresentation`, prefix the visible account cell only
when `showsWindowLabel` is true, while always including `window.label` in the
accessibility window name.

- [ ] **Step 5: Keep sample data lossless and update qualification notes**

Keep Standard and Droid Core sample windows in the normalized snapshot with
zero Core consumption so the live sample demonstrates the dormant filtering.
Ensure Standard includes five-hour, weekly, and rolling 30-day rows. Update the
Factory qualification section to state that the API may return both pools but
Core is fallback capacity consumed only after Standard; document the UI's
dormant-Core rule. Leave Kimi's weekly-only live qualification unchanged.

- [ ] **Step 6: Run focused and presentation suites**

Run:

```bash
swift test --filter dormantFactoryCoreWindowsStayHidden
swift test --filter repeatedAccountWindowsShowTheirPoolLabels
swift test --filter TimelinePresentationTests
```

Expected: PASS.

- [ ] **Step 7: Commit Factory presentation behavior**

```bash
git add Sources/UsageMeterUI/Timeline/UsageWindowPresentation.swift Sources/AgenticUsageMeter/AgenticUsageMeterApp.swift Tests/UsageMeterUITests/TimelinePresentationTests.swift docs/provider-qualification.md
git commit -m "Hide dormant Factory Core usage windows" -m "Preserve both Factory pools in normalized snapshots while presenting Standard alone until Droid Core has positive usage. Once Core begins, show every returned Core interval and distinguish the pool labels visually and through accessibility."
```

---

### Task 2: Apply Shared Compact Metrics and GitHub Label

**Files:**
- Create: `Sources/UsageMeterUI/Timeline/UsageTimelineMetrics.swift`
- Modify: `Sources/UsageMeterUI/Timeline/UsageWindowRow.swift`
- Modify: `Sources/UsageMeterUI/Timeline/UsageTimelineView.swift`
- Modify: `Sources/UsageMeterUI/MenuBar/MenuBarContentView.swift`
- Modify: `Sources/UsageMeterUI/Widget/FloatingWidgetView.swift`
- Modify: `Sources/UsageMeterUI/Widget/FloatingWidgetController.swift`
- Modify: `Sources/UsageMeterCore/Providers/ProviderCatalog.swift`
- Modify: `Tests/UsageMeterUITests/AppModelTests.swift`
- Modify: `Tests/UsageMeterCoreTests/ProviderCatalogTests.swift`

**Interfaces:**
- Consumes: the existing `UsageTimelineView` and `FloatingWidgetPlacement` contracts.
- Produces: internal `UsageTimelineMetrics` constants shared by all usage surfaces.

- [ ] **Step 1: Write the failing natural-size and catalog tests**

In `floatingWidgetOpensAtItsIntendedSize()`, change the natural width assertion:

```swift
#expect(panel.frame.width == 460)
```

Add this catalog test:

```swift
@Test
func githubUsesItsCompactProviderLabel() throws {
  let definition = try #require(
    ProviderCatalog.live.definition(for: .githubCopilot),
  )

  #expect(definition.displayName == "GitHub")
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
swift test --filter floatingWidgetOpensAtItsIntendedSize
swift test --filter githubUsesItsCompactProviderLabel
```

Expected: the widget test fails with width 520 instead of 460. If the catalog
label change is already present from the preceding provider-label work, the
catalog test passes and becomes the regression lock for that accepted behavior.

- [ ] **Step 3: Create the shared metrics boundary**

Create `UsageTimelineMetrics.swift`:

```swift
import CoreGraphics

enum UsageTimelineMetrics {
  static let naturalWidth: CGFloat = 460
  static let percentageColumnWidth: CGFloat = 34
  static let providerColumnWidth: CGFloat = 78
  static let accountColumnWidth: CGFloat = 84
  static let resetColumnWidth: CGFloat = 52
  static let columnSpacing: CGFloat = 6
  static let rowHeight: CGFloat = 23
  static let barHeight: CGFloat = 12
  static let nowLineHeight: CGFloat = 18
  static let minimumTimelineWidth: CGFloat = 160
  static let outerHorizontalPadding: CGFloat = 12
  static let outerVerticalPadding: CGFloat = 10
  static let sectionSpacing: CGFloat = 9
  static let sectionContentSpacing: CGFloat = 4
}
```

- [ ] **Step 4: Apply metrics to rows and sections**

Replace `UsageWindowRow`'s local sizing constants with
`UsageTimelineMetrics`. Keep the provider dot at 7 points, set the bar and now
line heights from the metrics, and keep the timeline's minimum width at 160.

In `UsageTimelineView`, use 9-point section spacing, 4-point internal spacing,
6-point column gaps, and 23-point balance rows. Reduce the Extra Credits value
column from 110 to 88 points so the flexible label column remains useful at 460
points.

- [ ] **Step 5: Compact both container surfaces**

In `MenuBarContentView`:

- use 12-point horizontal and 10-point vertical padding for the header and
  footer;
- use the same padding around `UsageTimelineView`;
- apply `.controlSize(.small)` to header/footer controls;
- set the outer frame width to `UsageTimelineMetrics.naturalWidth`.

In `FloatingWidgetView`, apply the same timeline padding and natural width,
retain the existing material, and use small close-button control sizing.

In `FloatingWidgetController`, replace only the three natural `520` widths with
`UsageTimelineMetrics.naturalWidth`. Do not alter `applySavedPlacement`, its
validation, or the persisted placement structure.

- [ ] **Step 6: Apply the compact provider label**

Set `.githubCopilot`'s catalog `displayName` to `"GitHub"`. Do not rewrite
`SubscriptionAccount.displayName`, because account names are user-editable.

- [ ] **Step 7: Run focused UI and catalog suites**

Run:

```bash
swift test --filter AppModelTests
swift test --filter TimelinePresentationTests
swift test --filter ProviderCatalogTests
```

Expected: PASS, including a 460-point naturally placed widget and unchanged
saved-placement behavior.

- [ ] **Step 8: Commit the compact layout**

```bash
git add Sources/UsageMeterUI/Timeline/UsageTimelineMetrics.swift Sources/UsageMeterUI/Timeline/UsageWindowRow.swift Sources/UsageMeterUI/Timeline/UsageTimelineView.swift Sources/UsageMeterUI/MenuBar/MenuBarContentView.swift Sources/UsageMeterUI/Widget/FloatingWidgetView.swift Sources/UsageMeterUI/Widget/FloatingWidgetController.swift Sources/UsageMeterCore/Providers/ProviderCatalog.swift Tests/UsageMeterUITests/AppModelTests.swift Tests/UsageMeterCoreTests/ProviderCatalogTests.swift
git commit -m "Compact usage timeline surfaces" -m "Centralize the approved 460-point layout metrics, reduce row and section spacing, and share the compact geometry between the menu-bar popover and naturally placed floating widget. Shorten the GitHub provider label without changing user account names or saved widget placements."
```

---

### Task 3: Build and Verify the Complete Product

**Files:**
- Verify: all modified source, test, and documentation files

**Interfaces:**
- Consumes: the complete compact timeline implementation from Tasks 1 and 2.
- Produces: automated, assembled-app, and live visual acceptance evidence.

- [ ] **Step 1: Run the complete Swift package suite**

Run:

```bash
swift test
```

Expected: all suites PASS with no failures.

- [ ] **Step 2: Assemble the debug application**

Run:

```bash
CONFIGURATION=debug scripts/assemble-app.sh
```

Expected: `build/Agentic Usage Meter.app` is assembled successfully.

- [ ] **Step 3: Launch representative sample data**

Run:

```bash
open -n "build/Agentic Usage Meter.app" --args --sample-data --show-widget
```

Expected: both the menu-bar app and floating widget launch from the newly
assembled product.

- [ ] **Step 4: Perform live visual and accessibility acceptance**

Inspect the rendered widget and menu-bar popover. Verify:

- the natural width is visibly 460 points rather than 520;
- every row is one line and all five columns align;
- bars, outlines, fills, and shared now lines remain readable;
- dormant Droid Core rows are absent while Factory Standard shows once per
  returned interval;
- the provider column says `GitHub`;
- Kimi remains weekly-only when the sample has no five-hour window;
- headers, section gaps, timeline padding, and footer controls are compact;
- all sample rows fit without scrolling on the active screen;
- accessibility exposes complete provider, account, pool, quota, and reset
  descriptions.

- [ ] **Step 5: Inspect the final diff and working tree**

Run:

```bash
git diff --check
git status --short
git log -4 --oneline --decorate
```

Expected: no whitespace errors; only intentional changes remain; the design,
Factory behavior, and compact-layout commits are present.
