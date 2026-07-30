# Account Management Design

## Goal

Make adding, reconnecting, renaming, and ordering accounts feel like one
coherent macOS workflow. The Accounts list is the stable home. Add and
Reconnect are temporary tasks presented over it, not separate destinations.

## Scope

This design changes the Settings window and account-row interactions. It reuses
the existing Claude, Codex, and Kimi connection models, browser flows,
credential storage, validation, removal, refresh, and persistence behavior.

It does not change provider authentication protocols, usage decoding, refresh
cadence, menu-bar rendering, or the floating widget.

## Window Structure

Settings contains one Accounts surface instead of a tab view.

The window toolbar contains:

- the title, Accounts;
- a prominent Add Account button.

When there are no accounts, the empty state also offers Add Account. Both
actions present the same add-account sheet.

The existing activation behavior remains: while Settings or its sheet is open,
the application uses regular activation policy and appears in Command-Tab.
Closing the last Settings window returns it to accessory behavior.

## Add and Reconnect Sheet

The sheet route has two modes:

- `add`, with a selectable provider;
- `reconnect(account)`, with the account's provider selected and locked.

The add sheet begins with three provider choices: Claude, Codex, and Kimi. The
selected provider's existing connection view occupies the rest of the sheet.
The sheet is large enough to host Claude's embedded browser without introducing
a second nested navigation surface.

Successful save dismisses the sheet and leaves the user on the updated Accounts
list. Cancel dismisses the sheet and invokes the existing connection cleanup.
Authentication, identity confirmation, duplicate-account detection, and usage
validation retain their existing behavior.

Claude's introduction includes this warning:

> Use email sign-in here. Continue with Google won't work in this isolated
> browser.

This describes a limitation of Google's OAuth policy for embedded user agents,
not a limitation of Claude accounts. Anthropic supports Google sign-in in
regular browsers and its native clients, while Google rejects OAuth inside
`WKWebView`.

References:

- https://support.claude.com/en/articles/13189465-log-in-to-your-claude-account
- https://developers.google.com/identity/protocols/oauth2/native-app

## Account List

Accounts remain grouped in the fixed provider order: Claude, Codex, then Kimi.
Only accounts within the same provider can be reordered.

Each row contains:

- a drag affordance;
- the editable account name;
- the authenticated identity when one is available;
- current refresh or error status;
- a visible Reconnect button when authentication is required;
- an overflow menu.

The overflow menu contains Refresh, Reconnect, Rename, Move Up, Move Down, and
Remove. Move commands remain available as keyboard and accessibility fallbacks
to drag-and-drop and are disabled at their respective boundaries.

Transient and unsupported-response errors remain status text rather than
prominent reconnect actions. Refresh is still available from the overflow menu.
Removal retains its destructive confirmation.

## Inline Rename

Clicking the account name replaces it with a focused text field containing the
current name.

- Return saves.
- Moving focus away saves.
- Escape cancels and restores the original name.
- An empty or persistence-failed value remains in edit mode and shows a local
  validation indication.

Only one row is edited at a time. Beginning a rename on another row finishes
the current edit first.

The row uses `AppModel.renameAccount`, preserving its trimming, validation,
persistence, and rollback behavior.

## Reordering

Provider sections use native SwiftUI list reordering. A move is translated into
the provider's complete ordered account-ID list and passed to
`AppModel.reorderAccounts`.

The UI animates a successful move in place. If persistence fails, the model's
existing rollback restores the prior order. Dragging never changes provider
membership or provider-section order.

## State Boundaries

`SettingsView` owns the optional sheet route. The route determines whether the
sheet is adding or reconnecting and supplies the provider lock.

`AccountListView` owns the pending removal and currently edited account ID.
Individual rows own only their temporary name field and focus state.

`AppModel` remains authoritative for accounts, snapshots, errors, ordering, and
persistence. No duplicate editable account collection is introduced in the UI.

## Accessibility

- Add Account and Reconnect have explicit button labels.
- The account name exposes Rename as its action rather than relying only on a
  pointer gesture.
- Drag ordering retains Move Up and Move Down alternatives.
- Status and authenticated identity remain readable by VoiceOver.
- Escape reliably cancels inline editing and sheet presentation.

## Error Handling

- Connection failures remain inside the sheet so the user can retry or cancel.
- Rename validation and save failures do not discard the typed name.
- Reorder persistence failures restore the previous order.
- A failed removal leaves the account in the list.
- One account's authentication failure does not disable editing or refreshing
  other accounts.

## Verification

Automated tests cover:

- add and reconnect sheet routing;
- provider selection and reconnect provider locking;
- connection completion returning to the Accounts list;
- inline rename save, focus-loss save, and Escape cancellation;
- rename validation and persistence-failure behavior;
- provider-local drag ordering and boundary move commands;
- reorder rollback;
- visible reconnect treatment for authentication failures;
- presence of Claude's embedded-browser login guidance.

Manual acceptance uses the real five-account state:

- the Accounts window shows all Claude, Codex, and Kimi subscriptions;
- Add Account can start each provider flow;
- Reconnect opens the correct locked provider flow;
- names can be edited in place;
- both Claude and Codex stacks can be reordered by dragging;
- Settings and its sheet keep the app in Command-Tab;
- closing Settings restores menu-bar-only activation.
