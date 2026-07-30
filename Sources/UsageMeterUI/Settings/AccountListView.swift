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

public struct AccountListView: View {
    private let model: AppModel
    private let onReconnect: (SubscriptionAccount) -> Void
    @State private var pendingRemoval: SubscriptionAccount?

    public init(
        model: AppModel,
        onReconnect: @escaping (SubscriptionAccount) -> Void,
    ) {
        self.model = model
        self.onReconnect = onReconnect
    }

    public var body: some View {
        List {
            ForEach(Provider.allCases, id: \.self) { provider in
                let accounts = providerAccounts(provider)
                if !accounts.isEmpty {
                    Section(providerName(provider)) {
                        ForEach(accounts) { state in
                            AccountSettingsRow(
                                state: state,
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
                    }
                }
            }
        }
        .overlay {
            if model.accounts.isEmpty {
                ContentUnavailableView(
                    "No accounts",
                    systemImage: "person.crop.circle.badge.plus",
                    description: Text(
                        "Add a Claude, Codex, or Kimi subscription.",
                    ),
                )
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
        var ids = providerAccounts(account.provider)
            .map(\.id)
        guard
            let index = ids.firstIndex(of: account.id),
            ids.indices.contains(index + offset)
        else {
            return
        }
        ids.swapAt(index, index + offset)
        Task {
            try? await model.reorderAccounts(
                provider: account.provider,
                orderedIDs: ids,
            )
        }
    }
}

private struct AccountSettingsRow: View {
    let state: AccountViewState
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onRefresh: () -> Void
    let onReconnect: () -> Void
    let onMove: (Int) -> Void
    let onRename: (String) async throws -> Void
    let onRemove: () -> Void

    @State private var isRenaming = false
    @State private var name = ""

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                if isRenaming {
                    TextField("Account name", text: $name)
                        .onSubmit {
                            saveName()
                        }
                } else {
                    Text(state.account.displayName)
                        .fontWeight(.medium)
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
                Button("Save") {
                    saveName()
                }
                Button("Cancel") {
                    isRenaming = false
                }
            } else {
                Button {
                    onMove(-1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(!canMoveUp)

                Button {
                    onMove(1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(!canMoveDown)

                Menu {
                    Button("Refresh", action: onRefresh)
                    Button("Reconnect", action: onReconnect)
                    Button("Rename") {
                        name = state.account.displayName
                        isRenaming = true
                    }
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
            }
        }
        .padding(.vertical, 4)
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

    private func saveName() {
        Task {
            do {
                try await onRename(name)
                isRenaming = false
            } catch {
                return
            }
        }
    }
}

private func providerName(_ provider: Provider) -> String {
    switch provider {
    case .claude:
        "Claude"
    case .codex:
        "Codex"
    case .kimi:
        "Kimi"
    }
}
