# Usage Levels and Extra Credits Design

**Date:** 2026-07-31

**Status:** Visually approved; written-spec review pending

**Target:** Menu-bar popover, floating widget, provider normalization, and
refresh policy

## Summary

Show every provider-reported rolling usage level, including an inactive
zero-use window that does not yet have a provider reset time. Keep timed usage
as compact, aligned, single-line Gantt rows, and move monetary or credit state
into its own compact **Extra Credits** section.

Every timed row uses five shared columns:

```text
% remaining | provider | account | timeline | time remaining
```

The columns align across all timed sections, but there is no visible global
column-header row beneath **Usage**. Section labels and the shared **Now** marker
provide the only timeline headers.

This design extends
`2026-07-30-aligned-usage-timeline-design.md` by splitting provider and account
into separate columns. It extends
`2026-07-30-provider-expansion-design.md` by defining resetless inactive
windows, explicit extra-credit states, and a development refresh policy. All
other provider, dashboard, authentication, ordering, and natural-height
decisions remain in force.

## Goals

- Keep comparable provider windows on the existing shared time axes.
- Show a provider's zero-use rolling allowance even when the provider omits a
  reset time until first use.
- Preserve the distinction between authoritative provider times and
  display-only placement.
- Show extra-credit availability, balance, unlimited status, or disabled status
  without implying unsupported data.
- Align percentage, provider, account, timeline, and remaining-time columns
  across the complete usage view.
- Permit one-minute refreshes in development builds while retaining the
  ten-minute production contact floor.

## Non-Goals

- A provider-specific usage renderer.
- Inventing an extra-credit balance from a spending cap, amount used, local
  token counts, or another indirect value.
- Showing **Off** for providers that do not expose an extra-credit feature or
  whose feature state is unknown.
- A spend-history dashboard, transaction ledger, cloud relay, or credential
  sync service.
- Changes to Settings, account authentication, account ordering, or dashboard
  session isolation.
- Scaling transient-error backoff down to one minute in development.

## Normalized Timed Windows

A normalized timed window continues to contain:

- a stable provider-local pool ID;
- window kind and duration;
- remaining fraction;
- provider-reported start time when available;
- provider-reported reset time when available.

The reset time becomes optional so the model can represent a real provider
response containing zero consumption and no reset. This is an absent provider
fact, not permission for adapters to estimate it.

The following invariants apply:

- A window with a provider reset renders from its real start and reset using the
  existing geometry.
- A zero-use window with no reset is a valid inactive rolling window.
- A nonzero window with no reset is invalid because neither its placement nor
  time remaining can be represented truthfully.
- A provider response that omits the entire window remains absent; the shared UI
  does not manufacture a product feature.

Existing persisted snapshots that contain a reset time continue to decode.
New resetless snapshots encode without one. No data migration or legacy schema
rewrite is required.

## Display-Only Placement for Inactive Windows

At presentation time, an inactive resetless window is shown as an empty
duration bar beginning at the current render time:

- an inactive five-hour window begins at **Now** and ends five hours later;
- an inactive weekly window begins at **Now** and ends seven days later.

The empty bar has the same full height, outline, duration, provider color, and
shared-axis treatment as an active row, with zero consumed fill. Its visible
remaining percentage is `100%`. The remaining-time column shows the window
duration, such as `5h 0m` or `7d 0h`.

This projected endpoint is recalculated from the view's clock. It is never
written back as a provider reset, persisted as provider data, used for refresh
scheduling, or described as an exact reset in accessibility text. The row's
accessibility value says the allowance is unused, that no provider reset was
reported, and that the displayed empty window starts now.

The five-hour section keeps its ten-hour axis with **Now** at 50%. The weekly
section keeps its fourteen-day axis with **Now** at 50%. Consequently, an
inactive bar begins on the center line and fills the right half of the relevant
axis by duration, while an active provider window retains its actual placement.

## Timed Usage Layout

All timed sections participate in one parent SwiftUI grid so row columns line
up across section boundaries:

| Column | Content | Alignment and sizing |
| --- | --- | --- |
| Percentage | Rounded remaining percentage | Fixed width, trailing, monospaced digits |
| Provider | Provider dot and short provider name | Fixed width, leading |
| Account | User-defined account name | Flexible, leading, truncates if necessary |
| Timeline | Outline, consumed fill, and shared Now line | Flexible shared geometry |
| Remaining | Compact relative time | Fixed width, trailing, monospaced digits |

Rows remain single-line. Provider and account are separate aligned columns, so
values like `41%`, `Claude`, and `Prime` never depend on the length of the
neighboring label. Account text receives truncation priority; accessibility
retains its full value.

There are no pills, labels, or other text inside a timeline bar. There is no
large column header beneath **Usage**. Section headers span the grid and place
their **Now** label above the same horizontal coordinate as the row center
line.

Timed sections preserve existing ordering and visibility rules:

1. five-hour windows;
2. weekly windows;
3. other comparable durations from shorter to longer;
4. rows in provider-catalog and user account order.

Empty timed sections remain absent. The menu-bar popover and floating widget
retain natural-height sizing, with scrolling only when the complete content
cannot fit on the active screen.

## Extra-Credit Domain Model

Extra-credit state is normalized independently from timed quota windows. A
provider can report one of three displayable states:

- **Available:** an authoritative remaining amount and unit;
- **Unlimited:** the provider explicitly reports unlimited extra usage;
- **Off:** the provider explicitly reports that the feature is disabled or not
  enabled for the account.

Absent or unknown provider data produces no extra-credit row. It does not map
to **Off**.

An available amount may be currency, provider credits, or another named unit.
The model stores the provider-reported remaining balance and optional cycle end.
It does not calculate balance from a limit minus usage. Provider-specific spend
caps, usage histories, automatic reload settings, and disabled-reason details
remain diagnostic data unless a later design gives them a user-facing purpose.

## Extra Credits Section

The compact **Extra Credits** section follows every timed section. It contains
one single-line row for each account whose provider explicitly exposes a
displayable extra-credit state.

Rows align provider, account, credit label, and value independently:

```text
Claude     Prime       Usage credits      $38.42
Codex      Personal    ChatGPT credits      Off
Factory    Work        Extra usage    Unlimited
```

The credit-label column uses the provider adapter's short product-appropriate
name, such as **Usage credits**, **ChatGPT credits**, or **Extra usage**. The
trailing value is right aligned and contains the authoritative formatted
balance, **Unlimited**, or **Off**. Numeric values use the provider-reported
currency exponent or unit.

Rows preserve provider-catalog and user account order. Clicking an Extra
Credits row opens the same account-scoped provider dashboard as its timed usage
row. The section is omitted when no account exposes a known extra-credit state.

## Provider Mapping

Adapters map only authoritative fields from their existing usage response:

### Claude

Continue using the Claude Web organization usage endpoint. Decode timed limits
from `five_hour` and `seven_day`, accepting `utilization: 0` with a null reset as
an inactive resetless window. Decode explicit extra-usage or spend state into
Available, Unlimited, or Off only when the payload provides the required fact.

Claude's payload distinguishes a balance from a spending limit and amount used.
The adapter must not infer a balance from the latter fields.

### Codex

Continue using the account-scoped Codex usage endpoint. Decode timed limits as
today, and decode its `credits` object as follows:

- explicit unlimited state becomes **Unlimited**;
- explicit absence or disabling of credits becomes **Off**;
- an enabled finite credit balance becomes **Available** with the reported
  balance;
- an absent credits object produces no row.

String-form numeric balances are parsed without losing their reported decimal
precision.

### Factory

Preserve a zero-use rolling window with no `windowEnd` as an inactive resetless
window instead of omitting it. Map Factory's explicit extra-usage allowance and
balance fields to Available or Off. Do not infer allowance from a missing
balance.

### OpenCode Zen

Continue mapping its authoritative usage balance to Available. No timed window
or status is added unless the provider reports one.

### Other Providers

Existing timed limits remain unchanged. Providers without an authoritative
extra-credit feature or state do not receive an Extra Credits row. The UI never
uses a generic fallback to label them Off.

## Refresh Policy

One shared refresh policy supplies both the automatic cadence and the
`AccountRefresher` provider-contact floor:

| Build | Automatic eligibility cadence | Per-account provider-contact floor |
| --- | --- | --- |
| Development (`DEBUG`) | 60 seconds | 60 seconds |
| Release | 600 seconds | 600 seconds |

Manual refresh requests continue to use the same per-account floor and cannot
bypass it. Authentication, explicit reconnect, and initial account validation
retain their existing connection semantics.

The app chooses a development or release policy at its composition boundary.
Tests inject the policy and clock directly rather than depending on a compiler
flag. Provider adapters do not create timers or independently fetch
credentials.

Existing transient-error backoff remains unchanged. A development build may
refresh a healthy account once per minute, but a failing account must not hammer
a provider once per minute.

## Errors and Last-Good Data

The existing last-good snapshot behavior remains authoritative:

- a malformed primary timed window rejects the refresh and keeps the previous
  snapshot;
- a nonzero window missing its reset rejects the refresh;
- an absent optional credit object is valid and produces no credit row;
- a present but malformed credit object rejects the refresh rather than showing
  potentially incorrect financial data;
- an explicitly disabled credit feature is valid data and renders **Off**;
- network, server, authentication, and rate-limit states keep their existing
  classification and retry behavior.

Diagnostics may name the provider field or normalized state that failed, but
must not record balances alongside tokens, cookies, authorization headers, or
other credentials in raw response dumps.

## Accessibility

Each timed row remains one accessibility element whose spoken order is:

1. provider and full account name;
2. window kind;
3. percentage remaining;
4. exact provider reset, or unused rolling-window semantics when resetless.

Each Extra Credits row speaks provider, full account name, explicit state, and
formatted authoritative balance when present. Color and timeline geometry are
never the only source of meaning.

## Implementation Boundaries

- `UsageWindow` represents an optional provider reset while enforcing that only
  zero-use windows may omit it.
- Provider decoders own authoritative mapping and reject inconsistent payloads.
- Timeline presentation owns the display-only placement of resetless windows.
- `UsageTimelinePresentation` creates distinct timed and extra-credit rows.
- `UsageTimelineView` owns the cross-section grid and Extra Credits section.
- `UsageWindowRow` owns the five timed columns and Gantt drawing.
- The application composition boundary selects development or release refresh
  policy; `AccountRefresher` remains the hard contact gate.

No provider-specific condition belongs in the shared SwiftUI views.

## Testing and Acceptance

Focused tests exercise domain and presentation behavior rather than rendered
SwiftUI strings:

- old snapshots with concrete reset times still decode;
- resetless zero-use windows round-trip through persistence;
- resetless nonzero windows are rejected;
- each provider decoder covers active, inactive resetless, absent, and malformed
  window data applicable to that provider;
- Claude, Codex, Factory, and OpenCode Zen cover Available, Unlimited, Off,
  absent, and malformed extra-credit states applicable to their schemas;
- deterministic timeline geometry places an inactive row at 50%, gives it one
  duration of width, and gives it zero consumed fill;
- active timeline geometry and shared Now lines remain unchanged;
- presentation rows preserve provider and user account order;
- absent unknown credit state omits the row instead of rendering Off;
- injected development policy enforces 60 seconds, release policy enforces 600
  seconds, and manual refresh respects both;
- transient backoff remains independent of the healthy refresh cadence.

Live acceptance uses the menu-bar popover and floating widget with multiple
real accounts:

- all five columns align across five-hour and weekly sections;
- provider and account remain separate, single-line labels;
- no global column header appears beneath **Usage**;
- active bars retain their real placement and inactive bars begin at **Now**;
- Extra Credits appears as a distinct compact section with no inferred values;
- all rows fit at natural height whenever the active screen permits;
- a development build updates an eligible healthy account after one minute;
- release assembly retains the ten-minute floor;
- provider requests remain account-isolated and credentials are fetched no more
  often than the active policy allows;
- the production app assembles, passes strict signature verification, and
  preserves real multi-account refresh behavior.

## Qualification Evidence

The design is based on locally qualified response shapes without retaining
credential values:

- Claude's organization usage payload can report zero utilization with a null
  reset and exposes separate extra-usage, spend, and balance concepts.
- Codex's usage payload exposes a distinct credits object with enabled,
  unlimited, balance, and overage state.
- Factory can omit a rolling-window end at zero use and separately reports
  extra-usage allowance and balance.
- OpenCode Zen already exposes an authoritative balance through the normalized
  model.

Product references:

- [Claude usage credits](https://support.claude.com/en/articles/12429409-manage-usage-credits-for-paid-claude-plans)
- [Codex pricing and credits](https://developers.openai.com/codex/pricing)

## Acceptance Decision

Implementation may begin only after Jesse reviews this written specification.
Approval includes the narrow persistence compatibility described above: old
snapshots with a reset continue to decode, and new snapshots may represent a
zero-use window without a reset. It does not authorize a broader migration or
backward-compatibility layer.
