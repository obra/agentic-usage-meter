# Pace-Readable Timeline Bars

## Problem

Timeline bars fill with the remaining quota fraction anchored to the
window's start. Judging whether consumption has outpaced elapsed time
means comparing the fill width against the distance from the now-line
to the reset edge, which are unrelated distances on the axis.

## Design

The fill keeps meaning remaining quota but anchors to the window's
reset edge. Because the now-line marks where remaining time begins,
pace becomes a single glance:

- Fill reaching the now-line: consumption is exactly on budget.
- Gap between the now-line and the fill's left edge: overdrawn by
  that fraction of the window.
- Fill extending left past the now-line: surplus quota.

`UsageWindowPresentation` exposes `fillXFraction`, the axis-relative
left edge of the fill: `outerXFraction + outerWidthFraction × (1 −
fillFraction)`. `UsageWindowRow` draws the fill from that offset to
the window's right edge instead of leading-aligned inside the box.

Everything else is unchanged: window box position, now-line,
percentage and reset columns, help and accessibility text. A zero-use
window without a reset renders a 100% fill covering the whole box,
exactly as before. The popover, dashboard detail, and floating widget
all render through `UsageWindowRow`, so they change together. The
collapsed shelf's bars have no time axis and stay plain
remaining-fraction bars.

## Testing

Presentation tests pin `fillXFraction` for on-pace, overdrawn,
surplus, and no-reset windows. Existing timeline tests continue to
cover layout, ordering, and text.
