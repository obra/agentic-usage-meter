import SwiftUI
import UsageMeterCore

struct APIKeyConnectionForm {
    var displayName: String
    var apiKey: String

    var validatedDisplayName: String {
        displayName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    var canConnect: Bool {
        !validatedDisplayName.isEmpty
            && !apiKey.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
    }
}

struct APIKeyConnectionView: View {
    let model: AppModel
    let provider: Provider
    let reconnectingAccount: SubscriptionAccount?
    let onComplete: () -> Void

    @State private var form: APIKeyConnectionForm
    @State private var isConnecting = false
    @State private var errorMessage: String?

    init(
        model: AppModel,
        provider: Provider,
        reconnectingAccount: SubscriptionAccount?,
        suggestedName: String,
        onComplete: @escaping () -> Void
    ) {
        precondition(provider == .minimax)
        self.model = model
        self.provider = provider
        self.reconnectingAccount = reconnectingAccount
        self.onComplete = onComplete
        _form = State(
            initialValue: APIKeyConnectionForm(
                displayName: suggestedName,
                apiKey: ""
            )
        )
    }

    var body: some View {
        Form {
            Section {
                TextField(
                    "Account name",
                    text: $form.displayName
                )
                SecureField(
                    "MiniMax API key",
                    text: $form.apiKey
                )
            } header: {
                Text("MiniMax Token Plan")
            } footer: {
                Text(
                    "Create an API key in the MiniMax platform. The key is stored only in this account's macOS Keychain record."
                )
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                if isConnecting {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(
                    reconnectingAccount == nil
                        ? "Add Account"
                        : "Reconnect",
                    action: connect
                )
                .buttonStyle(.borderedProminent)
                .disabled(
                    !form.canConnect || isConnecting
                )
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 520)
    }

    private func connect() {
        guard
            form.canConnect,
            let credential = MiniMaxCredential(
                apiKey: form.apiKey
            )
        else {
            return
        }

        isConnecting = true
        errorMessage = nil
        Task {
            do {
                if let reconnectingAccount {
                    try await model.reconnectAccount(
                        id: reconnectingAccount.id,
                        credential: credential
                    )
                } else {
                    try await model.connectAccount(
                        SubscriptionAccount(
                            provider: provider,
                            displayName:
                                form.validatedDisplayName,
                            displayOrder:
                                model.accounts.count {
                                    $0.account.provider
                                        == provider
                                }
                        ),
                        credential: credential
                    )
                }
                onComplete()
            } catch {
                errorMessage =
                    "MiniMax account could not be connected."
                isConnecting = false
            }
        }
    }
}
