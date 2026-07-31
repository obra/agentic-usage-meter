# Narrow Usage Timeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce the shared usage timeline column by 30 percent and remove the reclaimed width from the menu-bar popover and naturally sized floating widget.

**Architecture:** Keep `UsageTimelineMetrics` as the single source of truth for the aligned row geometry. Introduce a named 115-point natural timeline target, reduce its minimum to 112 points, and derive the complete natural width from the existing fixed columns, spacing, padding, and target so the popover and floating widget remain synchronized.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Testing, Swift Package Manager

## Global Constraints

- The natural timeline target is exactly 115 points.
- The timeline minimum is exactly 112 points.
- The complete natural surface width is exactly 411 points.
- Percentage, provider, account, reset, padding, and spacing widths remain unchanged.
- Existing saved floating-widget placements remain unchanged.
- Five-hour, weekly, and monthly axis durations and quota calculations remain unchanged.
- Factory Standard, Droid Core, Kimi, Extra Credits, account dashboard, help text, and accessibility behavior remain unchanged.
- The complete sample-data surface must fit without scrolling.

---

### Task 1: Derive the narrower usage surface width

**Files:**
- Modify: `Tests/UsageMeterUITests/AppModelTests.swift:740-810`
- Modify: `Sources/UsageMeterUI/Timeline/UsageTimelineMetrics.swift:3-17`

**Interfaces:**
- Consumes: `UsageTimelineMetrics.naturalWidth`, which the floating widget controller and menu-bar content already use.
- Produces: `UsageTimelineMetrics.naturalTimelineWidth: CGFloat`, `UsageTimelineMetrics.minimumTimelineWidth: CGFloat`, and a derived `UsageTimelineMetrics.naturalWidth: CGFloat`.

- [ ] **Step 1: Write the failing natural-width expectations**

In `floatingWidgetOpensAtItsIntendedSize()`, replace the 460-point assertion with the approved width:

```swift
#expect(panel.frame.width == 411)
```

In `menuBarContentExpandsWhenAccountsFinishLoading()`, render the hosting view at the same natural width:

```swift
hostingView.frame = NSRect(
    x: 0,
    y: 0,
    width: 411,
    height: emptyHeight,
)
```

- [ ] **Step 2: Run the focused test to verify it fails for the old width**

Run:

```bash
swift test --filter floatingWidgetOpensAtItsIntendedSize
```

Expected: FAIL because the floating panel still opens at 460 points rather than 411 points.

- [ ] **Step 3: Implement the named timeline target and derived natural width**

Replace `UsageTimelineMetrics` with the same existing values except for the new target, reduced minimum, and derived total:

```swift
enum UsageTimelineMetrics {
  static let percentageColumnWidth: CGFloat = 34
  static let providerColumnWidth: CGFloat = 78
  static let accountColumnWidth: CGFloat = 84
  static let resetColumnWidth: CGFloat = 52
  static let columnSpacing: CGFloat = 6
  static let rowHeight: CGFloat = 23
  static let barHeight: CGFloat = 12
  static let nowLineHeight: CGFloat = 18
  static let naturalTimelineWidth: CGFloat = 115
  static let minimumTimelineWidth: CGFloat = 112
  static let outerHorizontalPadding: CGFloat = 12
  static let outerVerticalPadding: CGFloat = 10
  static let sectionSpacing: CGFloat = 9
  static let sectionContentSpacing: CGFloat = 4

  static let naturalWidth: CGFloat =
    (outerHorizontalPadding * 2)
    + percentageColumnWidth
    + providerColumnWidth
    + accountColumnWidth
    + naturalTimelineWidth
    + resetColumnWidth
    + (columnSpacing * 4)
}
```

- [ ] **Step 4: Run focused layout tests**

Run:

```bash
swift test --filter floatingWidgetOpensAtItsIntendedSize
swift test --filter menuBarContentExpandsWhenAccountsFinishLoading
swift test --filter TimelinePresentationTests
```

Expected: all selected tests PASS at the 411-point natural width.

- [ ] **Step 5: Run the complete test suite**

Run:

```bash
swift test
```

Expected: all tests PASS with no regressions in provider visibility, quota presentation, account actions, or accessibility.

- [ ] **Step 6: Commit the tested implementation**

```bash
git add Sources/UsageMeterUI/Timeline/UsageTimelineMetrics.swift Tests/UsageMeterUITests/AppModelTests.swift
git commit -m "Narrow the usage timeline surface" -m "Reduce the shared Gantt column to the approved 115-point natural target and derive the complete 411-point surface width from the existing aligned columns. Keep widened floating widgets flexible while testing the menu and natural widget at the new width."
```

### Task 2: Verify the packaged app at the approved width

**Files:**
- Verify only: `build/Agentic Usage Meter.app`

**Interfaces:**
- Consumes: the tested `UsageTimelineMetrics.naturalWidth` layout contract.
- Produces: a signed local debug bundle and live sample-data evidence for the 411-point floating widget.

- [ ] **Step 1: Assemble and sign the local app bundle**

Run:

```bash
scripts/assemble-app.sh
codesign --force --deep --sign - "build/Agentic Usage Meter.app"
codesign --verify --deep --strict --verbose=2 "build/Agentic Usage Meter.app"
```

Expected: assembly completes and strict code-signing verification succeeds.

- [ ] **Step 2: Launch live sample data in the floating widget**

Run:

```bash
pkill -x AgenticUsageMeter 2>/dev/null || true
open -n "build/Agentic Usage Meter.app" --args --sample-data --show-widget
```

Expected: the app opens a naturally sized floating widget at approximately 411 points wide.

- [ ] **Step 3: Inspect the rendered layout**

Use the macOS accessibility and screenshot tooling to verify all of the following in the running app:

- the five-hour, weekly, and monthly Gantt bars remain legible;
- shared now lines remain aligned;
- percentage, provider, account, timeline, and reset columns do not overlap;
- Extra Credits labels and values remain readable;
- all sample rows remain visible without scrolling.

- [ ] **Step 4: Confirm repository state**

Run:

```bash
git status --short --branch
```

Expected: the branch is clean after the implementation commit.
