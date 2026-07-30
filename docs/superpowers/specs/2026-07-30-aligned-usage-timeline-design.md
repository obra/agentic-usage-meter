# Aligned Usage Timeline Design

**Date:** 2026-07-30
**Status:** Visually approved; written-spec review pending
**Target:** Menu-bar popover and floating widget

## Summary

Replace the current pills-inside-bars timeline with the selected aligned-leading
layout. Every quota row is one compact line:

1. percentage remaining, right-aligned in a fixed-width column;
2. provider and account identity, beginning at a shared x-position;
3. the existing bars-inside-Gantt visualization on the section's shared axis;
4. time remaining until reset, right-aligned in a fixed-width column.

This design supersedes only the overlay-pill treatment in
`docs/plans/2026-07-29-agentic-usage-meter-design.md`. It preserves that
document's provider ordering, shared time axes, consumed-capacity fill,
provider colors, and normalized domain model.

## Row Layout

At the existing 520-point popover width, each row uses four stable columns:

| Column | Content | Alignment |
| --- | --- | --- |
| Remaining | Rounded integer percentage, such as `95%` | Trailing |
| Identity | Provider dot, provider name, middle dot, account name | Leading |
| Timeline | Outer quota window, consumed fill, and shared now line | Shared section geometry |
| Reset | Compact relative interval, such as `4h 12m` | Trailing |

The percentage column is wide enough for `100%`. All percentage values share a
trailing edge. The identity column begins immediately after it, so provider and
account labels share a leading edge regardless of whether the percentage has
two or three digits.

Provider and account appear on the same baseline:

```text
 95%  ● Claude · Prime Radiant  [Gantt window]  4h 12m
100%  ● Codex · Personal       [Gantt window]  7d 0h
```

The provider name is secondary text. The account name has primary emphasis.
The provider-colored dot remains the redundant provider cue. If provider and
account names are identical, show the provider once. If an unusually long
identity cannot fit, truncate only the account portion; accessibility retains
the full provider and account names.

There are no pills or text overlays inside the timeline bar.

## Timeline Geometry

Five-hour windows share the existing ten-hour axis centered on now. Weekly
windows share the existing fourteen-day axis centered on now. A section renders
only accounts that actually provide that window kind; the UI does not invent a
missing five-hour or weekly window.

The outer Gantt bar starts at the derived window start and ends at reset. Its
full-height colored fill begins at the window start and fills left to right by
the consumed fraction. The unfilled portion is remaining capacity. A one-point
now line crosses every row at the same horizontal position within a section.

Moving the percentage out of the bar must not change the timeline's x-position,
width fraction, fill fraction, or now-line position.

## Reset Presentation

The visible reset column shows a compact relative interval derived at render
time from the absolute reset date, for example:

- `1h 23m`
- `4d 9h`
- `7d 0h`

The row's help text and accessibility value include the exact localized reset
date and time. Relative text updates as time advances without changing the
stored snapshot.

Intervals at or below zero render as `Now` until refreshed data replaces the
expired window. The formatter never shows seconds:

- at least one day: whole days and remaining whole hours, including `0h`;
- at least one hour: whole hours and remaining whole minutes, including `0m`;
- less than one hour: whole minutes.

## Sections and Ordering

The short-window section precedes the weekly section when both contain rows.
Do not render an empty section or a synthetic `No current data` row merely
because no account currently supplies that window kind.

Rows retain the existing stable provider and account order:

1. Claude
2. Codex
3. Kimi
4. user display order within each provider

Quota values never reorder rows.

## Window Sizing

The menu-bar popover keeps its 520-point width and takes its natural content
height. It does not place the timeline in a scroll view when the complete
content fits on the active screen.

The floating widget opens at the same natural content height. If the user
manually makes the widget shorter, or if the account list cannot physically fit
on the active screen, scrolling is the fallback; clipping rows is not.

Headers, section spacing, row height, dividers, and footer controls all count
toward the natural height. Adding or removing an account or window kind causes
the presentation to recalculate that height.

## Accessibility

Each row remains one accessibility element. Its label contains:

- provider and full account name;
- window kind;
- percentage remaining;
- exact localized reset date and time.

The visual left-to-right order is percentage, identity, timeline, and relative
reset. Accessibility uses the more natural spoken order: identity, window kind,
percentage remaining, exact reset.

Color, fill geometry, and the provider dot are never the only source of meaning.

## Implementation Boundaries

The rendering change belongs in the existing timeline presentation boundary:

- `UsageWindowPresentation` derives percentage, relative reset text, exact reset
  text, and accessibility text.
- `UsageWindowRow` owns the four-column SwiftUI layout and Gantt drawing.
- `UsageTimelineView` owns section presence, section headers, shared column
  alignment, and row ordering.
- `MenuBarContentView` and `FloatingWidgetView` own natural-height presentation
  and the bounded scrolling fallback.

Provider clients, authentication, refresh scheduling, persistence, and timeline
geometry do not change.

## Testing and Acceptance

Focused automated tests cover behavior rather than rendered SwiftUI strings:

- percentages round and format through `100%`;
- relative reset intervals cover hours, days, and expired windows;
- exact reset and accessibility text remain localized and complete;
- absent window kinds do not create rows or sections;
- provider and account ordering remains stable;
- shared timeline fractions and the now line are unchanged.

Live visual acceptance at 520 points verifies:

- two- and three-digit percentages share a trailing edge;
- every identity begins at the same x-position;
- provider and account remain on one line for the current accounts;
- no text overlaps or obscures a Gantt bar;
- all current rows fit in the menu-bar popover without scrolling;
- the floating widget presents the same rows and falls back to scrolling only
  when constrained below its natural height.
