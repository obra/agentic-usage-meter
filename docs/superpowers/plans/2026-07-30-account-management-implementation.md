# Fluent Account Management Implementation Plan

> **Required subskill:** Use `superpowers:executing-plans` to implement this
> plan task by task.

**Goal:** Replace the Settings tab switcher with one fluent Accounts surface,
present add and reconnect as a focused sheet, and make account naming and
provider-local ordering direct row interactions.

**Architecture:** Keep `AppModel` authoritative for persisted accounts and
reuse all existing provider connection models. Add small, value-type
presentation helpers for sheet routing, name editing, and provider-local move
calculation so interaction rules can be tested without coupling tests to
SwiftUI's rendered view hierarchy. `SettingsView` owns sheet presentation;
`AccountListView` owns the active edit and pending removal; each row owns only
its draft name and focus state.

**Tech Stack:** Swift 6.2, SwiftUI for macOS 26, Swift Testing, Swift Package
Manager.

---

## File Map

- Modify `Sources/UsageMeterUI/Settings/SettingsView.swift`
  - Replace `TabView` with the single Accounts surface and toolbar.
  - Add the add/reconnect sheet route and provider-card selector.
  - Keep the existing provider connection models and completion reset.
- Modify `Sources/UsageMeterUI/Settings/AccountListView.swift`
  - Add native section-local list moves and the row drag affordance.
  - Add single-row inline rename with Return, focus-loss, and Escape behavior.
  - Add visible authentication-required reconnect and complete overflow menu.
  - Add an empty-state Add Account action.
- Modify `Sources/UsageMeterUI/Settings/ClaudeConnectionView.swift`
  - Add the embedded-browser Google sign-in warning to the existing
    introduction.
- Modify `Tests/UsageMeterUITests/SettingsViewTests.swift`
  - Test sheet route semantics, provider locking, connection reset, name-edit
    decisions, provider-local ordered-ID moves, and Claude guidance.

## Task 1: Model the Sheet and Editing Interactions

**Files:**

- Modify: `Tests/UsageMeterUITests/SettingsViewTests.swift`
- Modify: `Sources/UsageMeterUI/Settings/SettingsView.swift`
- Modify: `Sources/UsageMeterUI/Settings/AccountListView.swift`

### Step 1: Write failing presentation-state tests

Add tests for the structured interaction contracts:

```swift
@Test
func reconnectRouteLocksTheExistingProvider() {
    let account = SubscriptionAccount(
        provider: .codex,
        displayName: "Work",
        displayOrder: 0,
    )
    let route = AccountSheetRoute.reconnect(account)

    #expect(route.provider == .codex)
    #expect(route.isProviderLocked)
    #expect(route.reconnectingAccount?.id == account.id)
}

@Test
func addRouteStartsWithClaudeAndAllowsProviderChanges() {
    let route = AccountSheetRoute.add

    #expect(route.provider == .claude)
    #expect(!route.isProviderLocked)
    #expect(route.reconnectingAccount == nil)
}

@Test
func accountNameEditRejectsBlankDraftWithoutDiscardingIt() {
    var edit = AccountNameEdit(
        originalName: "Work",
        draftName: "   ",
    )

    #expect(edit.saveDecision == .invalid)
    #expect(edit.draftName == "   ")
}

@Test
func accountNameEditCanCancelBackToTheOriginalName() {
    var edit = AccountNameEdit(
        originalName: "Work",
        draftName: "Personal",
    )

    edit.cancel()

    #expect(edit.draftName == "Work")
}
```

`AccountNameEdit.SaveDecision` is a small equatable enum with `.save(String)`
and `.invalid`; the saved value is trimmed.

### Step 2: Prove the tests fail

Run:

```bash
swift test --filter SettingsViewTests
```

Expected: compilation fails because `AccountSheetRoute` and
`AccountNameEdit` do not exist.

### Step 3: Add the smallest presentation helpers

In `SettingsView.swift`, add:

```swift
enum AccountSheetRoute: Identifiable {
    case add
    case reconnect(SubscriptionAccount)

    var id: String {
        switch self {
        case .add:
            "add"
        case let .reconnect(account):
            "reconnect-\(account.id.uuidString)"
        }
    }

    var provider: Provider {
        switch self {
        case .add:
            .claude
        case let .reconnect(account):
            account.provider
        }
    }

    var reconnectingAccount: SubscriptionAccount? {
        guard case let .reconnect(account) = self else {
            return nil
        }
        return account
    }

    var isProviderLocked: Bool {
        reconnectingAccount != nil
    }
}
```

In `AccountListView.swift`, add:

```swift
struct AccountNameEdit {
    enum SaveDecision: Equatable {
        case save(String)
        case invalid
    }

    let originalName: String
    var draftName: String

    var saveDecision: SaveDecision {
        let trimmed = draftName.trimmingCharacters(
            in: .whitespacesAndNewlines,
        )
        return trimmed.isEmpty ? .invalid : .save(trimmed)
    }

    mutating func cancel() {
        draftName = originalName
    }
}
```

### Step 4: Run the focused tests

Run:

```bash
swift test --filter SettingsViewTests
```

Expected: the new presentation-helper tests pass.

### Step 5: Commit

```bash
git add Sources/UsageMeterUI/Settings/SettingsView.swift \
  Sources/UsageMeterUI/Settings/AccountListView.swift \
  Tests/UsageMeterUITests/SettingsViewTests.swift
git commit -m "Model fluent account management interactions

Add testable value types for add and reconnect sheet routing, provider locking,
and inline account-name validation and cancellation. These isolate interaction
decisions from SwiftUI rendering while leaving AppModel authoritative for
persistence."
```

## Task 2: Make Accounts the Single Settings Surface

**Files:**

- Modify: `Tests/UsageMeterUITests/SettingsViewTests.swift`
- Modify: `Sources/UsageMeterUI/Settings/SettingsView.swift`
- Modify: `Sources/UsageMeterUI/Settings/AccountListView.swift`

### Step 1: Write failing route-transition tests

Extend the presentation state to own the optional route and form identity:

```swift
@Test
func completingConnectionDismissesSheetAndResetsProviderModels() {
    let firstAttemptID = UUID(
        uuidString: "11111111-1111-1111-1111-111111111111",
    )!
    let secondAttemptID = UUID(
        uuidString: "22222222-2222-2222-2222-222222222222",
    )!
    var presentation = AccountManagementPresentation(
        connectionForm: AccountConnectionFormState(
            attemptID: firstAttemptID,
        ),
    )
    presentation.presentAddAccount()
    let firstViewID = presentation.connectionViewID

    presentation.connectionDidComplete(
        nextAttemptID: secondAttemptID,
    )

    #expect(presentation.sheetRoute == nil)
    #expect(presentation.connectionViewID != firstViewID)
}

@Test
func reconnectPresentationCarriesTheSelectedAccount() {
    let account = SubscriptionAccount(
        provider: .kimi,
        displayName: "Kimi",
        displayOrder: 0,
    )
    var presentation = AccountManagementPresentation()

    presentation.presentReconnect(account)

    #expect(
        presentation.sheetRoute?.reconnectingAccount?.id
            == account.id,
    )
}
```

### Step 2: Prove the new tests fail

Run:

```bash
swift test --filter SettingsViewTests
```

Expected: compilation fails because `AccountManagementPresentation` does not
exist.

### Step 3: Implement the presentation state

Add `AccountManagementPresentation` in `SettingsView.swift`. It holds:

- `sheetRoute: AccountSheetRoute?`;
- `connectionForm: AccountConnectionFormState`;
- `presentAddAccount()`;
- `presentReconnect(_:)`;
- `dismissSheet()`;
- `connectionDidComplete(nextAttemptID:)`;
- `connectionViewID`, derived from the current reconnecting account.

Keep all methods synchronous and value-based.

### Step 4: Replace the Settings tab view

Refactor `SettingsView` to:

```swift
NavigationStack {
    AccountListView(
        model: model,
        onAdd: {
            presentation.presentAddAccount()
        },
        onReconnect: { account in
            presentation.presentReconnect(account)
        },
    )
    .navigationTitle("Accounts")
    .toolbar {
        ToolbarItem(placement: .primaryAction) {
            Button {
                presentation.presentAddAccount()
            } label: {
                Label("Add Account", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
.sheet(item: sheetRouteBinding) { route in
    AddAccountView(
        model: model,
        route: route,
        onCancel: {
            presentation.dismissSheet()
        },
        onComplete: {
            presentation.connectionDidComplete()
        },
    )
    .id(presentation.connectionViewID)
}
```

Keep the existing `SettingsWindowActivation` `onAppear` and `onDisappear`.
Use a binding that routes sheet dismissal through `dismissSheet()`.

Give `AccountListView` an `onAdd` closure and place a bordered prominent
`Add Account` button in its empty-state actions.

### Step 5: Run the focused and activation tests

Run:

```bash
swift test --filter SettingsViewTests
swift test --filter SettingsWindowPresenterTests
```

Expected: both pass.

### Step 6: Commit

```bash
git add Sources/UsageMeterUI/Settings/SettingsView.swift \
  Sources/UsageMeterUI/Settings/AccountListView.swift \
  Tests/UsageMeterUITests/SettingsViewTests.swift
git commit -m "Present account connections from one Settings surface

Replace the Accounts/Add Account tab split with a stable Accounts window and a
focused add or reconnect sheet. Keep existing provider models and window
activation behavior, and reset connection state after successful saves."
```

## Task 3: Add Provider Choices and Claude Browser Guidance

**Files:**

- Modify: `Tests/UsageMeterUITests/SettingsViewTests.swift`
- Modify: `Sources/UsageMeterUI/Settings/SettingsView.swift`
- Modify: `Sources/UsageMeterUI/Settings/ClaudeConnectionView.swift`

### Step 1: Write failing provider-presentation tests

Add stable presentation metadata instead of asserting rendered SwiftUI strings:

```swift
@Test
func providerChoicesHaveCompleteLabelsAndSymbols() {
    #expect(
        Provider.allCases.map(ProviderPresentation.init)
            .map(\.title)
            == ["Claude", "Codex", "Kimi"],
    )
    #expect(
        Provider.allCases.map(ProviderPresentation.init)
            .allSatisfy { !$0.systemImage.isEmpty },
    )
}

@Test
func claudeConnectionGuidanceExplainsEmbeddedGoogleLimitation() {
    #expect(
        ClaudeConnectionGuidance.embeddedBrowser
            == "Use email sign-in here. Continue with Google won't work in this isolated browser.",
    )
}
```

### Step 2: Prove the new tests fail

Run:

```bash
swift test --filter SettingsViewTests
```

Expected: compilation fails because the presentation metadata does not exist.

### Step 3: Implement provider choice metadata and controls

Add `ProviderPresentation` with title, detail, and SF Symbol:

- Claude — `globe` — “Isolated browser session”
- Codex — `terminal` — “ChatGPT OAuth in your browser”
- Kimi — `moon.stars` — “Device authorization”

Refactor `AddAccountView` so the sheet has:

- a leading title: `Add an account` or `Reconnect <name>`;
- a Cancel button;
- three equal-width provider buttons for add mode;
- one locked provider summary for reconnect mode;
- the selected existing provider connection view below a divider.

Provider buttons use a rounded rectangle selection background, a symbol, title,
and short detail. They remain buttons with explicit labels, not tap gestures.
Give the sheet `minWidth: 720` and `minHeight: 620`.

### Step 4: Add Claude's sign-in guidance

Define:

```swift
enum ClaudeConnectionGuidance {
    static let embeddedBrowser =
        "Use email sign-in here. Continue with Google won't work in this isolated browser."
}
```

Display it beneath the existing isolated-profile explanation with
`exclamationmark.triangle` and secondary styling. Do not change the Claude
authentication flow.

### Step 5: Run focused tests

Run:

```bash
swift test --filter SettingsViewTests
```

Expected: all Settings presentation tests pass.

### Step 6: Commit

```bash
git add Sources/UsageMeterUI/Settings/SettingsView.swift \
  Sources/UsageMeterUI/Settings/ClaudeConnectionView.swift \
  Tests/UsageMeterUITests/SettingsViewTests.swift
git commit -m "Clarify provider selection and Claude sign-in

Present provider choices as focused account-connection cards, lock reconnects
to their existing provider, and explain the embedded-browser Google OAuth
limitation without changing provider authentication."
```

## Task 4: Make Rows Directly Editable and Reorderable

**Files:**

- Modify: `Tests/UsageMeterUITests/SettingsViewTests.swift`
- Modify: `Sources/UsageMeterUI/Settings/AccountListView.swift`

### Step 1: Write failing provider-local move tests

Add tests for the ordered-ID calculation:

```swift
@Test
func movingAccountsUsesTheCompleteProviderLocalOrder() {
    let first = UUID()
    let second = UUID()
    let third = UUID()

    #expect(
        AccountOrder.moving(
            [first, second, third],
            fromOffsets: IndexSet(integer: 0),
            toOffset: 3,
        ) == [second, third, first],
    )
}

@Test
func movingAnEmptySelectionKeepsTheExistingOrder() {
    let ids = [UUID(), UUID()]

    #expect(
        AccountOrder.moving(
            ids,
            fromOffsets: IndexSet(),
            toOffset: 1,
        ) == ids,
    )
}
```

### Step 2: Prove the new tests fail

Run:

```bash
swift test --filter SettingsViewTests
```

Expected: compilation fails because `AccountOrder` does not exist.

### Step 3: Implement provider-local native moves

Add `AccountOrder.moving(_:fromOffsets:toOffset:)`, using the same index
semantics as SwiftUI `onMove`. Update each provider section:

```swift
ForEach(accounts) { state in
    AccountSettingsRow(...)
}
.onMove { source, destination in
    let orderedIDs = AccountOrder.moving(
        accounts.map(\.id),
        fromOffsets: source,
        toOffset: destination,
    )
    Task {
        try? await model.reorderAccounts(
            provider: provider,
            orderedIDs: orderedIDs,
        )
    }
}
```

Because every `onMove` lives inside one provider section, drag operations
cannot change provider membership. Add a leading `line.3.horizontal` affordance.
Retain Move Up and Move Down only in the overflow menu as accessibility and
keyboard fallbacks.

### Step 4: Implement one-at-a-time inline rename

Move edit ownership to `AccountListView` with:

```swift
@State private var editingAccountID: UUID?
```

Pass a binding into each row. The name is a plain button when idle. Activating
it sets the row's draft to the current display name, marks that account as the
only active edit, and focuses the text field.

The edit field:

- uses `.onSubmit` to save;
- observes focus loss and saves once;
- uses `.onExitCommand` to cancel;
- keeps the typed draft and shows a local error on blank or thrown save;
- exits edit mode only after `AppModel.renameAccount` succeeds.

When another name is activated, finish the current edit before starting the
new one. If the current draft cannot be saved, keep that row active.

### Step 5: Complete row actions and status treatment

Remove the visible chevron buttons. Add:

- a visible bordered `Reconnect` button only when
  `state.error == .authenticationRequired`;
- overflow items in this order: Refresh, Reconnect, Rename, Move Up, Move Down,
  divider, Remove;
- disabled move items at provider-stack boundaries;
- status text for all current non-authentication error states;
- accessibility labels for the drag affordance, rename button, and menu.

Preserve the existing removal confirmation.

### Step 6: Run focused tests and the full UI module

Run:

```bash
swift test --filter SettingsViewTests
swift test --filter UsageMeterUITests
```

Expected: all tests pass.

### Step 7: Commit

```bash
git add Sources/UsageMeterUI/Settings/AccountListView.swift \
  Tests/UsageMeterUITests/SettingsViewTests.swift
git commit -m "Make account rows directly editable and reorderable

Use native provider-local list moves, move ordering fallbacks into the overflow
menu, make account names directly editable with explicit validation behavior,
and surface reconnect only when authentication is required."
```

## Task 5: Verify, Build, and Exercise the Whole App

**Files:**

- Modify only if verification exposes a root-cause defect.

### Step 1: Run the full automated suite

Run:

```bash
swift test
```

Expected: all package tests pass.

### Step 2: Review the complete diff

Run:

```bash
git diff 514d6af --check
git diff --stat 514d6af
git status --short
```

Confirm the implementation changes only the approved Settings/account
management surface, tests, and plan. Confirm no provider protocol, usage
decoder, or credential-storage changes slipped into the diff.

### Step 3: Assemble and verify the signed app

Run:

```bash
./Scripts/assemble-app.sh
codesign --force --deep --sign - "build/Agentic Usage Meter.app"
codesign --verify --deep --strict --verbose=2 \
  "build/Agentic Usage Meter.app"
```

Expected: the app assembles and local ad-hoc signature verification succeeds.
`Scripts/verify-release.sh` remains the separate gate for a real Developer ID
signed, notarized, and stapled distribution artifact.

### Step 4: Relaunch the assembled app

Resolve the exact running process for
`build/Agentic Usage Meter.app/Contents/MacOS/AgenticUsageMeter`, terminate
only that process if present, and open the rebuilt bundle:

```bash
open "build/Agentic Usage Meter.app"
```

### Step 5: Perform live account-management acceptance

Using the existing real account state, verify:

- all Claude, Codex, and Kimi accounts appear without a settings-tab split;
- Add Account opens the sheet and each provider can be selected;
- Claude displays the email-sign-in guidance;
- an authentication-required account offers a visible Reconnect action;
- reconnect locks the selected provider;
- account names enter focused inline editing and support Return and Escape;
- Claude and Codex accounts reorder only within their own provider stacks;
- the Settings window and connection sheet keep the app in Command-Tab;
- closing Settings restores menu-bar-only behavior;
- the app remains stable across an automatic refresh interval.

Do not create, remove, rename, or reconnect a real account solely for
verification without Jesse's explicit intent. Exercise read-only UI states and
cancel any connection flow opened for inspection.

### Step 6: Final repository check and integration commit if needed

Run:

```bash
git status --short --branch
git log --oneline -8
```

If verification required an additional fix, commit it with a focused message
that names the root cause and evidence. Otherwise, leave the task at the four
implementation commits plus this plan commit.
