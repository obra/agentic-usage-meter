# Multi-Organization Claude Accounts

## Problem

A claude.ai login can belong to several chat-capable organizations,
but the connect flow always binds a new account to the first
qualified organization, so the others cannot be metered (issue #8).
Reconnecting also re-selects the first organization instead of the
account's stored one.

## Design

### Connect flow

After login, the flow fetches organizations and filters to
chat-capable ones as today.

- No chat organizations: fails, unchanged.
- One chat organization: unchanged single-account path with the
  naming step.
- Several chat organizations: a new choosing step lists each
  organization with a checkbox. Organizations whose ID matches no
  existing account are pre-checked. Organizations already metered by
  an existing account stay selectable but start unchecked and name
  the account metering them; a second login can hold its own seat in
  the same Team organization, so duplicates are allowed, just not
  encouraged. Continue loads usage for each selected organization,
  then a summary step saves one account per selection. Accounts are
  named after their organizations and share the login's single
  WebKit profile. An undecodable usage payload fails the flow, and
  transient failures save without a snapshot, both as today.

### Reconnect

Reconnect qualifies against the account's stored organization ID
instead of the first organization. If the new login's organization
list does not include it, the flow fails and explains that the login
does not belong to the account's organization.

After a successful reconnect, sibling accounts that shared the old
profile are re-pointed to the replacement profile only when the new
login's organization list includes their organization; their
authentication and backoff state resets with the repaired session. A
sibling whose organization is missing stays on the old profile, and
the old profile is deleted only when the profile changed and no
account references it anymore.

### Removal

`AppModel.removeAccount` runs the adapter's authentication cleanup
only when no other account references the same `claudeProfileID`.
Otherwise it removes the account's state and leaves the shared
profile in place. The profile store is deleted with its last account.

### Cancellation

Cancelling the connect flow deletes the provisional profile only when
no account was saved from it, unchanged. Saving any account from a
multi-selection marks the profile as owned.

## Testing

- Choice building: pre-check logic and already-connected labels are
  pure presentation, tested directly.
- Connection model: driving qualification with a stubbed transport
  covers the single-organization path unchanged, the choosing step,
  per-selection usage policy, reconnect against the stored
  organization, and reconnect failure when the organization is
  missing.
- AppModel: shared-profile removal skips authentication cleanup until
  the last account; reconnect re-points siblings and cleans up the
  old profile exactly once.
