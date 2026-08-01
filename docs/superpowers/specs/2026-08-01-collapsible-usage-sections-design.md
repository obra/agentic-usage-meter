# Collapsible Usage Sections Design

**Date:** 2026-08-01

**Status:** Approved

## Context

The menu-bar popover and floating widget render the same usage timeline. As more providers and quota pools are added, the expanded timeline can become taller than the available screen space. Users need to compact sections they do not currently need without losing the at-a-glance account and quota signal.

The existing expanded Gantt visualization remains the authoritative detailed view. Collapse is a presentation preference, not a change to provider data, quota grouping, or time-axis behavior.

## Goals

- Make every visible usage section collapsible.
- Preserve a useful quota summary while collapsed instead of reducing the section to a title alone.
- Share each section's collapse state between the menu-bar popover and floating widget.
- Restore those choices across application launches.
- Keep all sections expanded by default for new installations and existing saved state.
- Let both surfaces shrink and grow vertically as sections collapse and expand.

## Non-goals

- Changing the expanded Gantt layout, its aligned axes, or its fill semantics.
- Changing provider refresh, authentication, usage decoding, or balance behavior.
- Making the account dashboard timeline collapsible.
- Fetching provider icons from the network at runtime.
- Combining or inventing an aggregate percentage for multiple provider quota pools.

## Interaction

Each section header becomes a borderless disclosure button whose full width is clickable. A leading chevron points down while expanded and right while collapsed. The button has a concise expand/collapse accessibility label and respects the system reduced-motion setting.

Expanding restores the current rows and shared time axis. Collapsing replaces those rows with the compact shelf described below. The menu-bar popover and floating widget observe the same model state, so toggling a section in either surface updates the other immediately.

The account dashboard continues to show its existing always-expanded timeline. `UsageTimelineView` therefore exposes collapse configuration as an optional capability rather than making every use of the component collapsible.

## Collapsed timed-section shelf

The approved collapsed treatment is a responsive donut shelf:

- Each visible quota pool produces one shelf cell. A provider account with multiple pools in the same section produces multiple cells; pools are never aggregated.
- The cell centers a locally bundled provider favicon-sized mark inside a 28-point donut. Providers without a bundled mark use a deterministic provider-colored initial fallback.
- The colored arc begins at twelve o'clock and fills clockwise according to the percentage remaining. The neutral remainder of the ring is the amount consumed.
- The account name is shown below the donut on one line. A secondary line shows the exact remaining percentage and, when present, the pool label. For example: `71% · Standard`.
- Cells use equal-width columns and remain on one shelf row while the minimum readable cell width can be maintained. They wrap into additional shelf rows rather than hiding accounts or introducing horizontal scrolling.
- Selecting a cell opens the existing signed-in account dashboard, matching expanded-row behavior.
- Help and accessibility text include provider, account, pool name, percentage remaining, and reset time. The reset time does not compete for visible space in the collapsed shelf.

The donut intentionally uses percentage remaining even though the expanded bar fill represents consumption. In the collapsed state there is no shared time axis; the ring's single purpose is to communicate available capacity.

## Collapsed Extra Credits shelf

Extra Credits uses the same responsive shelf geometry, but does not invent a progress percentage when a provider supplies no denominator:

- Each visible balance produces one cell.
- The provider mark has a neutral ring rather than a progress donut.
- The account name and actual balance or status appear below it, such as `Off`, `$38.42`, `Unlimited`, or `1,200 credits`.
- Selecting a cell opens the account dashboard.
- Help and accessibility text retain the balance label and cycle-end information when supplied.

## State and persistence

`AppModel` is the single source of truth for a set of collapsed section identifiers. The stable identifiers cover the existing window kinds—short, daily, weekly, monthly, and custom—plus Extra Credits.

The set is stored with `PersistedAppState`. Loading a state file that predates this field defaults to an empty set, which means every section is expanded. Newly introduced section identifiers also default expanded. The model updates its observable state and persisted state together, saves through the existing store, and rolls back both if saving fails, matching the current floating-widget preference behavior.

Both `MenuBarContentView` and `FloatingWidgetView` pass the shared set and toggle action into `UsageTimelineView`. The view remains stateless with respect to the preference. `AccountDashboardView` omits the optional collapse configuration and retains its present behavior.

## Presentation structure

The current timeline presentation already emits one row per quota pool and one row per extra-credit balance. The collapsed views consume those same presentation rows so provider ordering, account ordering, Factory pool visibility, formatting, and dashboard routing remain consistent with expanded rows.

Implementation should add small focused components rather than duplicate the timeline:

- a reusable disclosure header;
- a collapsed timed-pool shelf cell;
- a collapsed balance shelf cell;
- a local provider-icon view shared by both cell types.

The expanded `UsageWindowRow` remains unchanged.

## Sizing and animation

The timeline continues to report its intrinsic height. Existing popover and floating-window sizing react to that height, so collapsing removes the expanded rows from layout and shrinks the surface. Expansion uses a short opacity/height transition; reduced-motion users receive the state change without animation.

## Error and edge behavior

- Empty sections remain absent and therefore have no stored UI to render.
- A collapsed identifier remains remembered if its section temporarily disappears; it applies again if provider data later restores that section.
- Percentages are clamped through the existing validated usage-window model before rendering the ring.
- Long account and pool names truncate visually but remain complete in help and accessibility text.
- Missing provider artwork falls back locally; it never delays rendering or creates a new network request.

## Verification

Automated coverage should prove:

- an older persisted-state fixture without collapse data loads with every section expanded;
- toggling a section updates and persists the shared model state;
- a failed save rolls the toggle back;
- menu-bar and widget timeline inputs derive from the same model state;
- each quota pool creates its own collapsed cell with remaining, not consumed, progress;
- multiple pools for one account remain distinct;
- Extra Credits renders neutral rings and real formatted values;
- accessibility values retain reset and cycle-end context.

Live macOS acceptance should verify:

- collapsing in the menu-bar popover updates the open floating widget and vice versa;
- collapse choices survive quitting and relaunching the application;
- the popover and floating widget resize without clipping or unnecessary scrolling;
- five or more accounts remain readable at the production compact width;
- clicking collapsed cells opens the correct signed-in account dashboard.

## Rejected alternatives

- **Header-only collapse:** smaller, but discards the account and quota signal Jesse explicitly wants to retain.
- **View-local `@State`:** cannot synchronize surfaces or survive relaunch.
- **Independent `@AppStorage` inside each timeline:** persistence is easy, but it hides state in leaf views and weakens synchronization, rollback, and testing.
- **One aggregate or concentric donut per account:** obscures distinct quota pools and requires invented aggregation or hard-to-read ring semantics.
- **Progress donuts for Extra Credits:** misleading when the provider exposes a balance without a total allowance.
