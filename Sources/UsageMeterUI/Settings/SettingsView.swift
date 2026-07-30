import Foundation
import SwiftUI
import UsageMeterCore

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

struct AccountConnectionFormState {
    struct ViewID: Hashable {
        let attemptID: UUID
        let reconnectingAccountID: UUID?
    }

    private(set) var attemptID: UUID

    init(attemptID: UUID = UUID()) {
        self.attemptID = attemptID
    }

    mutating func accountDidConnect(
        nextAttemptID: UUID = UUID(),
    ) {
        attemptID = nextAttemptID
    }

    func viewID(
        reconnectingAccountID: UUID?,
    ) -> ViewID {
        ViewID(
            attemptID: attemptID,
            reconnectingAccountID:
            reconnectingAccountID,
        )
    }
}

struct AccountManagementPresentation {
    var sheetRoute: AccountSheetRoute?
    private(set) var connectionForm:
        AccountConnectionFormState

    init(
        sheetRoute: AccountSheetRoute? = nil,
        connectionForm: AccountConnectionFormState =
            AccountConnectionFormState(),
    ) {
        self.sheetRoute = sheetRoute
        self.connectionForm = connectionForm
    }

    var connectionViewID:
        AccountConnectionFormState.ViewID
    {
        connectionForm.viewID(
            reconnectingAccountID:
            sheetRoute?.reconnectingAccount?.id,
        )
    }

    mutating func presentAddAccount() {
        sheetRoute = .add
    }

    mutating func presentReconnect(
        _ account: SubscriptionAccount,
    ) {
        sheetRoute = .reconnect(account)
    }

    mutating func dismissSheet() {
        sheetRoute = nil
    }

    mutating func connectionDidComplete(
        nextAttemptID: UUID = UUID(),
    ) {
        connectionForm.accountDidConnect(
            nextAttemptID: nextAttemptID,
        )
        dismissSheet()
    }
}

public struct SettingsView: View {
    private let model: AppModel
    private let windowActivation:
        SettingsWindowActivation
    @State private var presentation =
        AccountManagementPresentation()

    public init(model: AppModel) {
        self.model = model
        windowActivation = SettingsWindowActivation()
    }

    public var body: some View {
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
                        Label(
                            "Add Account",
                            systemImage: "plus",
                        )
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .sheet(item: $presentation.sheetRoute) { route in
            AddAccountView(
                model: model,
                route: route,
                onComplete: {
                    presentation.connectionDidComplete()
                },
            )
            .id(
                presentation.connectionViewID,
            )
        }
        .frame(minWidth: 680, minHeight: 560)
        .onAppear {
            windowActivation.settingsDidAppear()
        }
        .onDisappear {
            windowActivation.settingsDidDisappear()
        }
    }
}

private struct AddAccountView: View {
    @Environment(\.dismiss) private var dismiss

    let model: AppModel
    let route: AccountSheetRoute
    let onComplete: () -> Void

    @State private var selectedProvider: Provider
    @State private var claude: ClaudeConnectionModel
    @State private var codex: CodexConnectionModel
    @State private var kimi: KimiConnectionModel

    init(
        model: AppModel,
        route: AccountSheetRoute,
        onComplete: @escaping () -> Void,
    ) {
        self.model = model
        self.route = route
        self.onComplete = onComplete

        let provider = route.provider
        let reconnectingAccount =
            route.reconnectingAccount
        _selectedProvider = State(initialValue: provider)
        _claude = State(
            initialValue: ClaudeConnectionModel(
                appModel: model,
                reconnectingAccount:
                provider == .claude
                    ? reconnectingAccount
                    : nil,
            ),
        )
        _codex = State(
            initialValue: CodexConnectionModel(
                appModel: model,
                reconnectingAccount:
                provider == .codex
                    ? reconnectingAccount
                    : nil,
            ),
        )
        _kimi = State(
            initialValue: KimiConnectionModel.live(
                appModel: model,
                reconnectingAccount:
                provider == .kimi
                    ? reconnectingAccount
                    : nil,
            ),
        )
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Picker(
                    "Provider",
                    selection: $selectedProvider,
                ) {
                    Text("Claude").tag(Provider.claude)
                    Text("Codex").tag(Provider.codex)
                    Text("Kimi").tag(Provider.kimi)
                }
                .pickerStyle(.segmented)
                .disabled(route.isProviderLocked)

                Group {
                    switch selectedProvider {
                    case .claude:
                        ClaudeConnectionView(
                            model: claude,
                            suggestedName:
                            route.reconnectingAccount?
                                .displayName
                                ?? "Claude",
                            onComplete: complete,
                        )
                    case .codex:
                        CodexConnectionView(
                            model: codex,
                            suggestedName:
                            route.reconnectingAccount?
                                .displayName
                                ?? "Codex",
                            onComplete: complete,
                        )
                    case .kimi:
                        KimiConnectionView(
                            model: kimi,
                            suggestedName:
                            route.reconnectingAccount?
                                .displayName
                                ?? "Kimi",
                            onComplete: complete,
                        )
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                )
            }
            .padding(24)
            .navigationTitle(
                route.reconnectingAccount == nil
                    ? "Add an account"
                    : "Reconnect account",
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 720, minHeight: 620)
    }

    private func complete() {
        onComplete()
        dismiss()
    }
}
