# Claude Scoped Usage Windows

## Problem

The Claude usage endpoint reports per-model weekly pools — today the
Fable share of the weekly limit — only inside the newer `limits`
array, as entries with `"kind": "weekly_scoped"` and a
`scope.model.display_name`. The legacy top-level fields the decoder
reads (`five_hour`, `seven_day`) never carry them, and the legacy
per-model fields (`seven_day_opus`, `seven_day_sonnet`) are null on
current plans. The decoder does not declare `limits`, so the scoped
pool is silently dropped and an account can display a comfortable
weekly number while its Fable share is exhausted.

## Design

The decoder additionally decodes `limits` and emits one extra window
per entry that has a model scope and a recognized `group` ("session"
maps to the short shape, "weekly" to the weekly shape). The window
reuses the existing kinds with `label` set to the model display name,
exactly like Factory's per-pool windows, so presentation, shelf, and
persistence need no changes: the timeline already renders repeated
kinds as labeled subrows, and state.json only gains an additive
`label` key on the new rows. No new `UsageWindowKind` or
`UsageSectionID` raw value is introduced, keeping old builds and
external state.json readers decoding.

Scoped entries are optional surface, not part of the qualified legacy
contract, so they degrade by skipping rather than rejecting:
unscoped entries (duplicates of the legacy windows), unknown groups,
malformed entries, duplicate ids, and nonzero percents without a
reset are all dropped — the last per the existing no-invented-reset
invariant — with a count-only log line. `is_active` is ignored
because the provider reports real percents on inactive scoped
entries; `severity` is ignored because the UI has no severity
concept. The two legacy windows keep their fail-closed rules
unchanged.

A consequence to name: the menu-bar summary takes the tightest window
across all snapshots, so an exhausted scoped pool now drives the
badge. That is the binding limit the provider itself reports as
active, so it participates deliberately.

## Testing

Decoder tests pin the fixture's scoped window (kind, duration,
fraction, label, id), the skip rules (unscoped, unknown group,
malformed entry, duplicate id, nonzero without reset), and that a
response without `limits` still yields exactly the two legacy
windows. Client tests for both the OAuth and web paths cover the
three-window shape end to end. A presentation test mirrors the
Factory pool-label case for a Claude account with two weekly windows.
