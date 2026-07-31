# Narrow Usage Timeline Design

**Date:** 2026-07-31
**Status:** Approved direction; written-spec review pending
**Target:** Menu-bar popover and naturally sized floating widget

## Summary

Reduce the shared Gantt timeline column by 30 percent and remove the reclaimed
width from the complete usage surface. Provider, account, percentage, reset,
padding, and spacing widths remain unchanged.

The current 460-point surface leaves approximately 164 points for the timeline.
The new natural timeline target is 115 points, producing a 411-point popover and
naturally placed floating widget.

## Width Derivation

The natural width is derived from the existing aligned columns rather than
stored as an unrelated magic number:

```text
horizontal padding                 24
percentage/provider/account/reset 248
four six-point column gaps         24
timeline target                   115
                                  ---
natural surface width             411
```

`UsageTimelineMetrics` owns the 115-point target and derives the 411-point
natural width from it. The timeline minimum becomes 112 points, which is 70
percent of the previous 160-point minimum.

The timeline remains flexible above its target. A manually widened floating
widget may use the extra space for longer Gantt bars. Existing saved floating
widget placements remain unchanged.

## Preserved Behavior

The change affects only horizontal layout metrics. It does not alter:

- five-hour, weekly, or monthly axis durations;
- window start, end, fill, or now-line fractions;
- percentage, provider, account, or reset column widths;
- section ordering or provider window presence;
- Factory Standard and Droid Core visibility;
- Kimi's provider-supplied window behavior;
- account dashboard interactions, help text, or accessibility descriptions.

Extra Credits uses the same narrower surface. Its flexible balance-label column
absorbs the width reduction while its provider, account, and value columns stay
aligned and unchanged.

## Testing and Acceptance

The floating-widget size test expects a 411-point natural width. The menu-bar
hosting test renders at the same width and continues verifying natural-height
expansion after accounts load.

Live sample-data acceptance verifies that:

- the complete surface is approximately 49 points narrower;
- five-hour, weekly, and monthly bars remain legible;
- the shared now lines remain aligned;
- text columns do not overlap the timeline or reset values;
- Extra Credits labels and values remain readable;
- the complete sample still fits without scrolling.
