# Aligned Usage Timeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace text pills inside quota bars with the approved percentage-leading, single-line timeline and make the menu popover and floating widget prefer their natural content height.

**Architecture:** Keep provider data and `TimelineLayout` unchanged. Extend `UsageWindowPresentation` with identity and reset-interval values, render those values in four stable SwiftUI columns, then let the shared timeline content choose its natural height with a scroll fallback only when its host constrains it.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Swift Testing, macOS 26

## Global Constraints

- Keep the menu-bar popover width at 520 points.
- Preserve the ten-hour short-window axis and fourteen-day weekly axis, both centered on now.
- Preserve stable Claude, Codex, Kimi, and account display ordering.
- Render only window kinds returned by provider snapshots.
- Put no labels or pills inside Gantt bars.
- Display percentage, identity, Gantt, and relative reset in that left-to-right order.
- Keep exact localized reset time in help and accessibility text.
- Do not change provider clients, authentication, refresh scheduling, persistence, or normalized usage models.

---

## File Map

- `Sources/UsageMeterUI/Timeline/UsageWindowPresentation.swift`
  derives provider/account identity, percentage text, relative reset text, exact
  reset text, and accessibility text.
- `Sources/UsageMeterUI/Timeline/UsageWindowRow.swift`
  renders the approved four-column row and Gantt marks.
- `Sources/UsageMeterUI/Timeline/UsageTimelineView.swift`
  omits empty sections and aligns section headers with row columns.
- `Sources/UsageMeterUI/MenuBar/MenuBarContentView.swift`
  prefers natural timeline height and uses scrolling only under a bounded host.
- `Sources/UsageMeterUI/Widget/FloatingWidgetView.swift`
  provides the same natural-first, scroll-fallback timeline behavior.
- `Sources/UsageMeterUI/Widget/FloatingWidgetController.swift`
  sizes a new unsaved widget from its SwiftUI fitting size.
- `Sources/AgenticUsageMeter/AgenticUsageMeterApp.swift`
  resynchronizes an unsaved widget when account rows change.
- `Tests/UsageMeterUITests/TimelinePresentationTests.swift`
  covers presentation formatting, identity de-duplication, ordering, and absent
  window kinds.
- `Tests/UsageMeterUITests/AppModelTests.swift`
  updates the floating-widget size contract.

### Task 1: Presentation Values for the Approved Row

**Files:**
- Modify: `Sources/UsageMeterUI/Timeline/UsageWindowPresentation.swift`
- Modify: `Tests/UsageMeterUITests/TimelinePresentationTests.swift`

**Interfaces:**
- Consumes: `SubscriptionAccount`, `UsageWindow`, `Date`, and `TimeZone`.
- Produces: `providerText: String`, `accountText: String?`,
  `remainingPercentageText: String`, `relativeResetText: String`,
  `exactResetText: String`, and the existing `accessibilityValue: String`.

- [ ] **Step 1: Replace the pill-oriented expectations with failing presentation tests**

Add focused assertions to `TimelinePresentationTests`:

```swift
@Test
func weeklyRowFormatsAlignedIdentityAndResetInterval() throws {
    let account = SubscriptionAccount(
        provider: .codex,
        displayName: "Work",
        authenticatedIdentity: "work@example.com",
        displayOrder: 0,
    )
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let window = try #require(
        UsageWindow(
            id: "weekly",
            kind: .weekly,
            duration: 604_800,
            resetAt: now.addingTimeInterval(472_000),
            consumedFraction: 0.66,
        ),
    )

    let presentation = UsageWindowPresentation(
        account: account,
        window: window,
        now: now,
        timeZone: TimeZone(secondsFromGMT: 0)!,
    )

    #expect(presentation.providerText == "Codex")
    #expect(presentation.accountText == "Work")
    #expect(presentation.remainingPercentageText == "34%")
    #expect(presentation.relativeResetText == "5d 11h")
    #expect(presentation.exactResetText == "Mon 2:40 PM")
    #expect(
        presentation.accessibilityValue
            == "Codex, Work, weekly window, 34 percent remaining, resets Mon 2:40 PM",
    )
}

@Test
func resetIntervalUsesHoursMinutesAndNow() throws {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let account = SubscriptionAccount(
        provider: .claude,
        displayName: "Work",
        displayOrder: 0,
    )

    func presentation(resetOffset: TimeInterval) throws
        -> UsageWindowPresentation
    {
        let window = try #require(
            UsageWindow(
                id: "short-\(resetOffset)",
                kind: .short,
                duration: 18_000,
                resetAt: now.addingTimeInterval(resetOffset),
                consumedFraction: 0.2,
            ),
        )
        return UsageWindowPresentation(
            account: account,
            window: window,
            now: now,
            timeZone: TimeZone(secondsFromGMT: 0)!,
        )
    }

    #expect(try presentation(resetOffset: 9_000).relativeResetText == "2h 30m")
    #expect(try presentation(resetOffset: 3_540).relativeResetText == "59m")
    #expect(try presentation(resetOffset: -1).relativeResetText == "Now")
}

@Test
func identityOmitsRepeatedProviderAccountName() throws {
    let account = SubscriptionAccount(
        provider: .kimi,
        displayName: "Kimi",
        displayOrder: 0,
    )
    let window = try #require(
        UsageWindow(
            id: "weekly",
            kind: .weekly,
            duration: 604_800,
            resetAt: Date(timeIntervalSince1970: 2_000_472_000),
            consumedFraction: 0.27,
        ),
    )

    let presentation = UsageWindowPresentation(
        account: account,
        window: window,
        now: Date(timeIntervalSince1970: 2_000_000_000),
        timeZone: TimeZone(secondsFromGMT: 0)!,
    )

    #expect(presentation.providerText == "Kimi")
    #expect(presentation.accountText == nil)
    #expect(presentation.remainingPercentageText == "73%")
}
```

- [ ] **Step 2: Run the focused tests and verify the new API fails**

Run:

```bash
swift test --filter TimelinePresentationTests
```

Expected: compilation fails because the new presentation properties do not
exist and the old tests still reference `remainingText` and `expiryText`.

- [ ] **Step 3: Implement the minimal presentation API**

Replace the pill-oriented properties with:

```swift
public let providerText: String
public let accountText: String?
public let remainingPercentageText: String
public let relativeResetText: String
public let exactResetText: String
```

In the initializer:

```swift
providerText = account.provider.displayName
let trimmedAccountName = account.displayName.trimmingCharacters(
    in: .whitespacesAndNewlines,
)
accountText =
    trimmedAccountName.caseInsensitiveCompare(providerText) == .orderedSame
        ? nil
        : trimmedAccountName

let remainingPercent = Int(
    (window.remainingFraction * 100).rounded(),
)
remainingPercentageText = "\(remainingPercent)%"
relativeResetText = Self.relativeResetText(
    resetAt: window.resetAt,
    now: now,
)
exactResetText = Self.exactResetText(
    resetAt: window.resetAt,
    timeZone: timeZone,
)
```

Add private formatters in the same file:

```swift
private static func relativeResetText(
    resetAt: Date,
    now: Date,
) -> String {
    let totalSeconds = Int(
        resetAt.timeIntervalSince(now).rounded(.down),
    )
    guard totalSeconds > 0 else {
        return "Now"
    }
    let totalMinutes = totalSeconds / 60
    guard totalMinutes >= 60 else {
        return "\(totalMinutes)m"
    }
    let totalHours = totalMinutes / 60
    guard totalHours >= 24 else {
        return "\(totalHours)h \(totalMinutes % 60)m"
    }
    return "\(totalHours / 24)d \(totalHours % 24)h"
}

private static func exactResetText(
    resetAt: Date,
    timeZone: TimeZone,
) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "EEE h:mm a"
    return formatter.string(from: resetAt)
}
```

Move provider display naming to a file-private `Provider.displayName` extension
in `UsageWindowPresentation.swift`. Build `accessibilityValue` with
`exactResetText`.

- [ ] **Step 4: Run the focused presentation tests**

Run:

```bash
swift test --filter TimelinePresentationTests
```

Expected: all `TimelinePresentationTests` pass.

- [ ] **Step 5: Commit the presentation contract**

```bash
git add Sources/UsageMeterUI/Timeline/UsageWindowPresentation.swift \
    Tests/UsageMeterUITests/TimelinePresentationTests.swift
git commit -m "Present aligned usage row values"
```

### Task 2: Four-Column SwiftUI Row and Non-empty Sections

**Files:**
- Modify: `Sources/UsageMeterUI/Timeline/UsageWindowRow.swift`
- Modify: `Sources/UsageMeterUI/Timeline/UsageTimelineView.swift`
- Modify: `Tests/UsageMeterUITests/TimelinePresentationTests.swift`

**Interfaces:**
- Consumes: Task 1's `UsageWindowPresentation` properties and existing
  `UsageTimelineSectionPresentation`.
- Produces: a 29-point row with fixed percentage, identity, and reset columns;
  a flexible shared-axis timeline column; and sections only for present data.

- [ ] **Step 1: Add a failing absent-window-kind presentation test**

Add:

```swift
@Test
func sectionIsEmptyWhenNoAccountOffersItsWindowKind() throws {
    let account = SubscriptionAccount(
        provider: .codex,
        displayName: "Work",
        displayOrder: 0,
    )
    let weekly = try #require(
        UsageWindow(
            id: "weekly",
            kind: .weekly,
            duration: 604_800,
            resetAt: Date(timeIntervalSince1970: 2_000_472_000),
            consumedFraction: 0.5,
        ),
    )
    let state = AccountViewState(
        account: account,
        snapshot: UsageSnapshot(
            accountID: account.id,
            fetchedAt: Date(timeIntervalSince1970: 2_000_000_000),
            windows: [weekly],
        ),
    )

    let shortSection = UsageTimelineSectionPresentation(
        kind: .short,
        accounts: [state],
        now: Date(timeIntervalSince1970: 2_000_000_000),
    )

    #expect(shortSection.rows.isEmpty)
}
```

- [ ] **Step 2: Run the focused tests**

Run:

```bash
swift test --filter TimelinePresentationTests
```

Expected: the new presentation test passes, establishing the structured input
that the view must omit.

- [ ] **Step 3: Replace the pill row with the approved columns**

Use these shared constants in `UsageWindowRow`:

```swift
static let percentageColumnWidth: CGFloat = 42
static let identityColumnWidth: CGFloat = 156
static let resetColumnWidth: CGFloat = 64
static let columnSpacing: CGFloat = 8
static let rowHeight: CGFloat = 29
```

The row body is:

```swift
HStack(spacing: Self.columnSpacing) {
    Text(presentation.remainingPercentageText)
        .font(.caption.monospacedDigit())
        .fontWeight(.semibold)
        .frame(
            width: Self.percentageColumnWidth,
            alignment: .trailing,
        )

    identity
        .frame(
            width: Self.identityColumnWidth,
            alignment: .leading,
        )

    timeline
        .frame(height: Self.rowHeight)

    Text(presentation.relativeResetText)
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(
            width: Self.resetColumnWidth,
            alignment: .trailing,
        )
}
.frame(height: Self.rowHeight)
.help("Resets \(presentation.exactResetText)")
.accessibilityElement(children: .ignore)
.accessibilityLabel(presentation.accessibilityValue)
```

`identity` keeps the provider dot and provider/account on one line:

```swift
HStack(spacing: 4) {
    Circle()
        .fill(row.account.provider.timelineColor)
        .frame(width: 7, height: 7)
    Text(presentation.providerText)
        .foregroundStyle(.secondary)
        .fixedSize()
    if let accountText = presentation.accountText {
        Text("·")
            .foregroundStyle(.secondary)
        Text(accountText)
            .fontWeight(.medium)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}
.font(.caption)
.lineLimit(1)
```

`timeline` retains the existing fraction calculations but removes both text
capsules. Draw the outer window at 14 points high, clip the full-height consumed
fill to the same rounded rectangle, and draw the now line at 22 points high.

- [ ] **Step 4: Omit empty sections and align the Now header**

Construct both section presentations once in `UsageTimelineView.body`, filter
out empty sections, and render:

```swift
let sections = [
    UsageTimelineSectionPresentation(
        kind: .short,
        accounts: accounts,
        now: now,
        timeZone: timeZone,
    ),
    UsageTimelineSectionPresentation(
        kind: .weekly,
        accounts: accounts,
        now: now,
        timeZone: timeZone,
    ),
].filter { !$0.rows.isEmpty }
```

Use `ForEach(sections, id: \.kind)`. The section header uses the same four
column widths as rows: clear percentage and identity columns, `Now` centered
over the timeline, and a clear reset column. Delete the `No current data`
branch.

- [ ] **Step 5: Run focused tests and build the UI product**

Run:

```bash
swift test --filter TimelinePresentationTests
swift build --product AgenticUsageMeter
```

Expected: tests pass and the product builds.

- [ ] **Step 6: Commit the row and section rendering**

```bash
git add Sources/UsageMeterUI/Timeline/UsageWindowRow.swift \
    Sources/UsageMeterUI/Timeline/UsageTimelineView.swift \
    Tests/UsageMeterUITests/TimelinePresentationTests.swift
git commit -m "Render aligned single-line usage rows"
```

### Task 3: Natural-height Popover and Widget

**Files:**
- Modify: `Sources/UsageMeterUI/MenuBar/MenuBarContentView.swift`
- Modify: `Sources/UsageMeterUI/Widget/FloatingWidgetView.swift`
- Modify: `Sources/UsageMeterUI/Widget/FloatingWidgetController.swift`
- Modify: `Sources/AgenticUsageMeter/AgenticUsageMeterApp.swift`
- Modify: `Tests/UsageMeterUITests/AppModelTests.swift`

**Interfaces:**
- Consumes: the compact natural height of Task 2's `UsageTimelineView`.
- Produces: natural-first menu and widget sizing with a scroll fallback under
  host constraints; new widgets use the SwiftUI fitting height.

- [ ] **Step 1: Update the widget-size test to require content fitting**

Change `floatingWidgetOpensAtItsIntendedSize` to load the five sample account
states used by the app, open the controller, and assert:

```swift
#expect(panel.frame.width == 520)
#expect(panel.frame.height > 360)
#expect(panel.frame.height <= panel.screen!.visibleFrame.height)
```

Keep the existing cleanup that hides the widget.

- [ ] **Step 2: Run the widget test and verify the fixed 360-point panel fails**

Run:

```bash
swift test --filter floatingWidgetOpensAtItsIntendedSize
```

Expected: failure because `FloatingWidgetController` still opens at 520 by 360.

- [ ] **Step 3: Make the menu timeline natural-first**

Extract the padded timeline into a local view property and replace the fixed
`ScrollView.frame(minHeight:maxHeight:)` with:

```swift
ViewThatFits(in: .vertical) {
    timeline
        .fixedSize(horizontal: false, vertical: true)
    ScrollView {
        timeline
    }
}
```

The menu's outer `.frame(width: 520)` remains unchanged.

- [ ] **Step 4: Make the floating widget natural-first with scroll fallback**

Give `FloatingWidgetView` a fixed 520-point ideal width. Wrap the padded
timeline in the same vertical `ViewThatFits`: natural fixed-size content first,
`ScrollView` second. Keep the header, close button, material, and resize
behavior unchanged.

- [ ] **Step 5: Size a new unsaved panel from the hosting view**

In `FloatingWidgetController.makePanel`, create the hosting view before the
panel:

```swift
let hostingView = NSHostingView(
    rootView: FloatingWidgetView(model: model),
)
hostingView.frame.size.width = 520
hostingView.layoutSubtreeIfNeeded()
let fittingHeight = hostingView.fittingSize.height
let screenHeight =
    NSScreen.main?.visibleFrame.height
        ?? max(fittingHeight, 360)
let initialHeight = min(
    max(fittingHeight, 240),
    screenHeight,
)
```

Use `initialHeight` in `contentRect` and set `panel.contentView = hostingView`.
When no saved placement exists, `applySavedPlacement` recalculates the hosting
view's current fitting height, resizes the panel within its screen's visible
height, and then centers it. A valid saved placement remains authoritative and
the `ScrollView` handles a saved height below the natural height.

- [ ] **Step 6: Resynchronize an unsaved visible widget when rows change**

In `MenuBarLabel`, add:

```swift
.onChange(of: model.accounts) {
    widgetController.synchronize()
}
```

`FloatingWidgetController.synchronize()` resizes only when
`floatingWidgetPlacement == nil`; it never overwrites a user-saved frame.

- [ ] **Step 7: Run the widget test and full automated suite**

Run:

```bash
swift test --filter floatingWidgetOpensAtItsIntendedSize
swift test
```

Expected: the widget test and the complete suite pass.

- [ ] **Step 8: Commit natural sizing**

```bash
git add Sources/UsageMeterUI/MenuBar/MenuBarContentView.swift \
    Sources/UsageMeterUI/Widget/FloatingWidgetView.swift \
    Sources/UsageMeterUI/Widget/FloatingWidgetController.swift \
    Sources/AgenticUsageMeter/AgenticUsageMeterApp.swift \
    Tests/UsageMeterUITests/AppModelTests.swift
git commit -m "Size usage surfaces to their content"
```

### Task 4: Full Build and Live Acceptance

**Files:**
- No source changes expected.
- Generated artifact: `build/Agentic Usage Meter.app`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: automated, packaged-app, and live visual evidence for the approved
  rendering.

- [ ] **Step 1: Run the complete test and debug build gates**

Run:

```bash
swift test
swift build --product AgenticUsageMeter
```

Expected: all tests pass and the executable builds.

- [ ] **Step 2: Assemble the complete app bundle**

Run:

```bash
CONFIGURATION=debug Scripts/assemble-app.sh
```

Expected: `build/Agentic Usage Meter.app` is produced.

- [ ] **Step 3: Launch sample data for visual acceptance**

Run:

```bash
open -n "build/Agentic Usage Meter.app" \
    --args --sample-data --show-widget
```

Inspect the menu-bar popover and floating widget. Verify:

- percentages share a trailing edge;
- identities share a leading edge and remain one line;
- provider and account are visually distinct;
- no text appears inside a Gantt bar;
- five-hour rows appear only for Claude sample accounts;
- all current sample rows fit in the menu popover without scrolling;
- exact reset time appears in row help and accessibility;
- the widget opens at natural height and scrolls after being resized shorter.

- [ ] **Step 4: Check repository state**

Run:

```bash
git status --short
```

Expected: no source, test, or plan changes remain uncommitted. The ignored
application bundle may remain under `build/`.
