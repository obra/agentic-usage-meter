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
per entry that has a model scope and the qualified `group`
("weekly"; other groups are unqualified surface and pass silently
until live evidence justifies them). The window reuses the weekly
kind with `label` set to the model display name, exactly like
Factory's per-pool windows, so presentation, shelf, and persistence
need no changes: the timeline already renders repeated kinds as
labeled subrows, and state.json only gains an additive `label` key on
the new rows. No new `UsageWindowKind` or `UsageSectionID` raw value
is introduced, keeping old builds and external state.json readers
decoding — though readers that select windows by kind must prefer the
unlabeled window now that a kind can repeat.

Scoped entries are optional surface, not part of the qualified legacy
contract, so they degrade by skipping rather than rejecting, at every
level: a `limits` value that is not an array is treated as absent,
an element that fails to decode is dropped, and so are out-of-range
percents and nonzero percents without a reset (the existing
no-invented-reset invariant). Only these malformed cases produce the
count-only log line; unscoped entries (duplicates of the legacy
windows) and non-weekly groups are expected surface and pass without
logging. Entries colliding on id resolve to the higher-consumed one,
so a duplicate can only tighten the reported limit, never hide it.
`is_active` is ignored because the provider reports real percents on
inactive scoped entries; `severity` is ignored because the UI has no
severity concept. The two legacy windows keep their fail-closed rules
unchanged.

A consequence to name: the menu-bar summary takes the tightest window
across all snapshots, so an exhausted scoped pool now drives the
badge. That is the binding limit the provider itself reports as
active, so it participates deliberately.

## Testing

Decoder tests pin the fixture's scoped window (kind, duration,
fraction, label, id), the skip rules (unscoped, non-weekly group,
malformed entry, nonzero without reset), the higher-consumed winner
on duplicate ids, that a drifted non-array `limits` container leaves
the legacy pair intact, and that a response without `limits` still
yields exactly the two legacy windows. Client tests for both the
OAuth and web paths cover the three-window shape end to end. A
presentation test mirrors the Factory pool-label case for a Claude
account with two weekly windows.
