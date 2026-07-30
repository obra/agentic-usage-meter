import SwiftUI
import UsageMeterCore

public struct SettingsView: View {
    private enum Tab: Hashable {
        case accounts
        case connect
    }

    private let model: AppModel
    @State private var selectedTab = Tab.accounts
    @State private var reconnectingAccount:
        SubscriptionAccount?

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            AccountListView(
                model: model,
                onReconnect: { account in
                    reconnectingAccount = account
                    selectedTab = .connect
                },
            )
            .tabItem {
                Label("Accounts", systemImage: "person.2")
            }
            .tag(Tab.accounts)

            AddAccountView(
                model: model,
                reconnectingAccount: reconnectingAccount,
                onComplete: {
                    reconnectingAccount = nil
                    selectedTab = .accounts
                },
            )
            .id(reconnectingAccount?.id)
            .tabItem {
                Label(
                    reconnectingAccount == nil
                        ? "Add Account"
                        : "Reconnect",
                    systemImage: "plus.circle",
                )
            }
            .tag(Tab.connect)
        }
        .frame(minWidth: 680, minHeight: 560)
    }
}

private struct AddAccountView: View {
    let model: AppModel
    let reconnectingAccount: SubscriptionAccount?
    let onComplete: () -> Void

    @State private var selectedProvider: Provider
    @State private var claude: ClaudeConnectionModel
    @State private var codex: CodexConnectionModel
    @State private var kimi: KimiConnectionModel

    init(
        model: AppModel,
        reconnectingAccount: SubscriptionAccount?,
        onComplete: @escaping () -> Void,
    ) {
        self.model = model
        self.reconnectingAccount = reconnectingAccount
        self.onComplete = onComplete

        let provider =
            reconnectingAccount?.provider ?? .claude
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
        VStack(alignment: .leading, spacing: 18) {
            Picker("Provider", selection: $selectedProvider) {
                Text("Claude").tag(Provider.claude)
                Text("Codex").tag(Provider.codex)
                Text("Kimi").tag(Provider.kimi)
            }
            .pickerStyle(.segmented)
            .disabled(reconnectingAccount != nil)

            Group {
                switch selectedProvider {
                case .claude:
                    ClaudeConnectionView(
                        model: claude,
                        suggestedName:
                        reconnectingAccount?.displayName
                            ?? "Claude",
                        onComplete: onComplete,
                    )
                case .codex:
                    CodexConnectionView(
                        model: codex,
                        suggestedName:
                        reconnectingAccount?.displayName
                            ?? "Codex",
                        onComplete: onComplete,
                    )
                case .kimi:
                    KimiConnectionView(
                        model: kimi,
                        suggestedName:
                        reconnectingAccount?.displayName
                            ?? "Kimi",
                        onComplete: onComplete,
                    )
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
            )
        }
        .padding(24)
    }
}
