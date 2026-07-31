# Compact Usage Timeline Design

**Date:** 2026-07-31
**Status:** Approved direction; written-spec review pending
**Target:** Menu-bar popover and floating widget

## Summary

Compress the approved single-line, shared-axis usage timeline without changing
its information hierarchy or quota geometry. The menu-bar popover and the
floating widget use a 460-point natural width, tighter columns and padding, and
23-point rows. The result should show the current multi-provider account set
without scrolling whenever the active screen has enough vertical space.

This design also clarifies Factory's Standard and Droid Core presentation,
shortens GitHub Copilot's provider label, and preserves the existing rule that
the UI renders only quota windows returned by a provider.

## Compact Layout

The shared timeline row keeps the existing order:

1. percentage remaining;
2. provider identity;
3. account or pool identity;
4. shared-axis Gantt bar;
5. time remaining until reset.

The natural width changes from 520 to 460 points. The compact metrics are:

| Metric | Value |
| --- | ---: |
| Row height | 23 pt |
| Gantt bar height | 12 pt |
| Now-line height | 18 pt |
| Inter-column spacing | 6 pt |
| Percentage column | 34 pt |
| Provider column | 78 pt |
| Account/pool column | 84 pt |
| Reset column | 52 pt |
| Timeline minimum | 160 pt |
| Timeline content padding | 12 pt horizontal, 10 pt vertical |

Section spacing becomes 9 points and spacing within each section becomes 4
points. Header and footer controls use small macOS control sizing with 10 to 12
points of outer padding. Typography remains at its current semantic styles so
the density change does not make labels smaller or less legible.

Long provider and account names remain one line and truncate at the tail.
Accessibility and help text retain the full values. The percentage, provider,
account, timeline, and reset columns remain aligned across every row and the
Extra Credits section.

## Factory Pool Visibility

Factory's Standard allowance is the primary pool and always remains visible.
Droid Core is a fallback pool: Factory consumes Standard first, and only draws
from Droid Core's separate limits after Standard has been exhausted.

Hide all Droid Core timeline rows while every returned Core window is unused.
A Core window counts as used when it has a positive consumed fraction. Once any
Core window has been consumed, show all returned Core windows together so its
five-hour, weekly, and monthly resets remain comparable.

When only Standard is visible, use the account name normally. When Core becomes
visible beside Standard, prefix the account column with the pool label, for
example `Standard · Factory` and `Droid Core · Factory`. Accessibility always
includes the pool label, even when only Standard is visible.

The decoder continues preserving all returned pools in the normalized
snapshot. Pool visibility is a presentation decision, which allows the UI to
reveal Droid Core without another provider fetch when its usage becomes
positive in a refreshed snapshot.

## Provider Labels and Missing Windows

Use `GitHub` as the provider catalog label to save horizontal space. Existing
user-editable account names remain unchanged.

Kimi continues to render only the window kinds present in its response. The
decoder already accepts five-hour Kimi windows when supplied; a weekly-only
snapshot therefore produces only a weekly row. The UI does not synthesize a
five-hour allowance or reset.

## Window Sizing

The menu-bar popover always uses the new 460-point natural width and its natural
content height, bounded by the active screen. Scrolling remains the fallback
only when the full content cannot physically fit.

New or naturally placed floating widgets open at the same 460-point width and
natural content height. A saved manual floating-widget placement remains user
owned and is not silently overwritten. The compact internal layout still
applies inside a wider saved panel.

## Data and Error Boundaries

No provider authentication, persistence, refresh scheduling, or network code
changes. Factory filtering consumes normalized `UsageWindow` values, and the
existing account state continues to preserve last-good snapshots and provider
errors.

An absent Factory Core pool stays absent. A malformed active window remains a
provider error. Resetless zero-use Standard windows remain visible as empty
meters beginning at now for display, without inventing a provider reset.

## Testing and Acceptance

Automated tests cover behavior rather than rendered SwiftUI source:

- dormant Droid Core windows are omitted while Standard remains visible;
- positive usage in any Core window reveals every returned Core window;
- pool labels distinguish Standard and Droid Core rows and remain present in
  accessibility text;
- GitHub's provider catalog label is `GitHub`;
- absent Kimi window kinds do not create rows;
- new floating widgets open at 460 points and stay within the screen;
- menu-bar content still expands to its natural height as account data loads.

Live visual acceptance uses representative Claude, Codex, Kimi, GitHub, and
Factory data. It verifies aligned columns, readable bars, useful timeline
resolution, clean truncation, compact headers and footer controls, natural
height, and the absence of scrolling when the complete data set fits.
