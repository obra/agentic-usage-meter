import SwiftUI
import UsageMeterCore

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

struct AccountOrder {
    static func moving(
        _ ids: [UUID],
        fromOffsets source: IndexSet,
        toOffset destination: Int,
    ) -> [UUID] {
        guard
            !source.isEmpty,
            source.allSatisfy(ids.indices.contains),
            (0...ids.count).contains(destination)
        else {
            return ids
        }

        let movingIDs = source.map { ids[$0] }
        var reordered = ids
        for index in source.sorted(by: >) {
            reordered.remove(at: index)
        }
        let removedBeforeDestination =
            source.filter { $0 < destination }.count
        let insertionIndex = min(
            max(
                destination - removedBeforeDestination,
                0,
            ),
            reordered.count,
        )
        reordered.insert(
            contentsOf: movingIDs,
            at: insertionIndex,
        )
        return reordered
    }

    static func moving(
        _ ids: [UUID],
        accountID: UUID,
        by offset: Int,
    ) -> [UUID] {
        guard
            let index = ids.firstIndex(of: accountID),
            ids.indices.contains(index + offset)
        else {
            return ids
        }
        var reordered = ids
        reordered.swapAt(index, index + offset)
        return reordered
    }
}

struct AccountRowPresentation {
    static func showsReconnectAction(
        for error: AccountViewError?,
    ) -> Bool {
        error == .authenticationRequired
    }
}

public struct AccountListView: View {
    private let model: AppModel
    private let onAdd: () -> Void
    private let onReconnect: (SubscriptionAccount) -> Void
    @State private var pendingRemoval: SubscriptionAccount?
    @State private var editingAccountID: UUID?

    public init(
        model: AppModel,
        onAdd: @escaping () -> Void,
        onReconnect: @escaping (SubscriptionAccount) -> Void,
    ) {
        self.model = model
        self.onAdd = onAdd
        self.onReconnect = onReconnect
    }

    public var body: some View {
        List {
            ForEach(ProviderCatalog.live.all) { definition in
                let provider = definition.provider
                let accounts = providerAccounts(provider)
                if !accounts.isEmpty {
                    Section(definition.displayName) {
                        ForEach(accounts) { state in
                            AccountSettingsRow(
                                state: state,
                                editingAccountID:
                                    $editingAccountID,
                                canMoveUp:
                                state.id != accounts.first?.id,
                                canMoveDown:
                                state.id != accounts.last?.id,
                                onRefresh: {
                                    Task {
                                        await model.refreshAccount(
                                            id: state.id,
                                        )
                                    }
                                },
                                onReconnect: {
                                    onReconnect(state.account)
                                },
                                onMove: { offset in
                                    move(
                                        state.account,
                                        by: offset,
                                    )
                                },
                                onRename: { displayName in
                                    try await model.renameAccount(
                                        id: state.id,
                                        displayName: displayName,
                                    )
                                },
                                onRemove: {
                                    pendingRemoval = state.account
                                },
                            )
                        }
                        .onMove { source, destination in
                            move(
                                accounts,
                                provider: provider,
                                fromOffsets: source,
                                toOffset: destination,
                            )
                        }
                    }
                }
            }
        }
        .overlay {
            if model.accounts.isEmpty {
                ContentUnavailableView {
                    Label(
                        "No accounts",
                        systemImage:
                            "person.crop.circle.badge.plus",
                    )
                } description: {
                    Text(
                        "Add a Claude, Codex, or Kimi subscription.",
                    )
                } actions: {
                    Button("Add Account", action: onAdd)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .alert(
            "Remove account?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: {
                    if !$0 {
                        pendingRemoval = nil
                    }
                },
            ),
            presenting: pendingRemoval,
        ) { account in
            Button("Remove", role: .destructive) {
                Task {
                    try? await model.removeAccount(
                        id: account.id,
                    )
                    pendingRemoval = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingRemoval = nil
            }
        } message: { account in
            Text(
                "\(account.displayName) and its local authentication data will be deleted.",
            )
        }
    }

    private func providerAccounts(
        _ provider: Provider,
    ) -> [AccountViewState] {
        model.accounts.filter {
            $0.account.provider == provider
        }
    }

    private func move(
        _ account: SubscriptionAccount,
        by offset: Int,
    ) {
        let currentIDs =
            providerAccounts(account.provider)
            .map(\.id)
        let orderedIDs = AccountOrder.moving(
            currentIDs,
            accountID: account.id,
            by: offset,
        )
        guard orderedIDs != currentIDs else {
            return
        }
        Task {
            try? await model.reorderAccounts(
                provider: account.provider,
                orderedIDs: orderedIDs,
            )
        }
    }

    private func move(
        _ accounts: [AccountViewState],
        provider: Provider,
        fromOffsets source: IndexSet,
        toOffset destination: Int,
    ) {
        let currentIDs = accounts.map(\.id)
        let orderedIDs = AccountOrder.moving(
            currentIDs,
            fromOffsets: source,
            toOffset: destination,
        )
        guard orderedIDs != currentIDs else {
            return
        }
        Task {
            try? await model.reorderAccounts(
                provider: provider,
                orderedIDs: orderedIDs,
            )
        }
    }
}

private struct AccountSettingsRow: View {
    let state: AccountViewState
    @Binding var editingAccountID: UUID?
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onRefresh: () -> Void
    let onReconnect: () -> Void
    let onMove: (Int) -> Void
    let onRename: (String) async throws -> Void
    let onRemove: () -> Void

    @State private var draftName = ""
    @State private var renameError: String?
    @State private var isSavingName = false
    @State private var isCancellingName = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityLabel(
                    "Drag to reorder \(state.account.displayName)",
                )

            VStack(alignment: .leading, spacing: 3) {
                if isRenaming {
                    TextField(
                        "Account name",
                        text: $draftName,
                    )
                    .focused($isNameFocused)
                    .onSubmit {
                        saveName()
                    }
                    .onExitCommand {
                        cancelName()
                    }
                    .onAppear {
                        Task { @MainActor in
                            isNameFocused = true
                        }
                    }
                } else {
                    Button(action: beginRename) {
                        Text(state.account.displayName)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .accessibilityLabel(
                        "Rename \(state.account.displayName)",
                    )
                    .accessibilityAction(
                        named: "Rename",
                        beginRename,
                    )
                }

                if let renameError {
                    Text(renameError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                if let identity =
                    state.account.authenticatedIdentity
                {
                    Text(identity)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                statusText
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isRenaming {
                if isSavingName {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Save") {
                    saveName()
                }
                .disabled(isSavingName)
                Button("Cancel") {
                    cancelName()
                }
                .disabled(isSavingName)
            } else {
                if AccountRowPresentation
                    .showsReconnectAction(for: state.error)
                {
                    Button(
                        "Reconnect",
                        action: onReconnect,
                    )
                    .buttonStyle(.bordered)
                }

                Menu {
                    Button("Refresh", action: onRefresh)
                    Button("Reconnect", action: onReconnect)
                    Button("Rename") {
                        beginRename()
                    }
                    Button("Move Up") {
                        onMove(-1)
                    }
                    .disabled(!canMoveUp)
                    Button("Move Down") {
                        onMove(1)
                    }
                    .disabled(!canMoveDown)
                    Divider()
                    Button(
                        "Remove",
                        role: .destructive,
                        action: onRemove,
                    )
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel(
                    "Actions for \(state.account.displayName)",
                )
            }
        }
        .padding(.vertical, 4)
        .onChange(of: isNameFocused) {
            wasFocused,
            isFocused in
            if
                wasFocused,
                !isFocused
            {
                if isCancellingName {
                    isCancellingName = false
                } else {
                    saveName()
                }
            }
        }
    }

    private var isRenaming: Bool {
        editingAccountID == state.id
    }

    @ViewBuilder
    private var statusText: some View {
        if state.isRefreshing {
            Text("Refreshing…")
        } else if let error = state.error {
            switch error {
            case .authenticationRequired:
                Text("Reconnect required")
            case .temporarilyUnavailable:
                Text("Temporarily unavailable")
            case .unsupportedResponse:
                Text("Provider response changed")
            }
        } else if let fetchedAt = state.snapshot?.fetchedAt {
            Text("Updated \(fetchedAt.formatted(.relative(presentation: .named)))")
        } else {
            Text("Waiting for usage data")
        }
    }

    private func beginRename() {
        draftName = state.account.displayName
        renameError = nil
        isCancellingName = false
        editingAccountID = state.id
    }

    private func cancelName() {
        var edit = AccountNameEdit(
            originalName: state.account.displayName,
            draftName: draftName,
        )
        edit.cancel()
        draftName = edit.draftName
        renameError = nil
        isCancellingName = true
        if editingAccountID == state.id {
            editingAccountID = nil
        }
        isNameFocused = false
    }

    private func saveName() {
        guard !isSavingName else {
            return
        }
        let edit = AccountNameEdit(
            originalName: state.account.displayName,
            draftName: draftName,
        )
        guard case let .save(displayName) =
            edit.saveDecision
        else {
            renameError = "Enter an account name."
            editingAccountID = state.id
            isNameFocused = true
            return
        }

        isSavingName = true
        renameError = nil
        Task {
            do {
                try await onRename(displayName)
                draftName = displayName
                if editingAccountID == state.id {
                    editingAccountID = nil
                }
            } catch {
                renameError =
                    "The account name couldn't be saved."
                editingAccountID = state.id
                isNameFocused = true
            }
            isSavingName = false
        }
    }
}
