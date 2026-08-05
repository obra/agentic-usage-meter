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

struct APIKeyConnectionPresentation {
    let sectionTitle: String
    let secretLabel: String
    let guidance: String
    let failureMessage: String

    init(provider: Provider) {
        switch provider {
        case .minimax:
            sectionTitle = "MiniMax Token Plan"
            secretLabel = "MiniMax API key"
            guidance =
                "Create an API key in the MiniMax platform. The key is stored only in this account's macOS Keychain record."
            failureMessage =
                "MiniMax account could not be connected."
        case .factory:
            sectionTitle = "Factory API key"
            secretLabel = "Factory API key"
            guidance =
                "Create a key at app.factory.ai/settings/api-keys. The key is stored only in this account's macOS Keychain record."
            failureMessage =
                "Factory account could not be connected."
        case .zai:
            sectionTitle = "Z.ai Coding Plan"
            secretLabel = "Z.ai API key"
            guidance =
                "Use your Coding Plan API key from z.ai/manage-apikey. The key is stored only in this account's macOS Keychain record."
            failureMessage =
                "Z.ai account could not be connected."
        default:
            preconditionFailure(
                "Provider does not use an API-key connection."
            )
        }
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
        precondition(
            provider == .minimax
                || provider == .factory
                || provider == .zai
        )
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
                    presentation.secretLabel,
                    text: $form.apiKey
                )
            } header: {
                Text(presentation.sectionTitle)
            } footer: {
                Text(presentation.guidance)
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
        guard form.canConnect else {
            return
        }

        switch provider {
        case .minimax:
            guard
                let credential = MiniMaxCredential(
                    apiKey: form.apiKey
                )
            else {
                return
            }
            connect(using: credential)
        case .factory:
            guard
                let credential = FactoryCredential(
                    apiKey: form.apiKey
                )
            else {
                return
            }
            connect(using: credential)
        case .zai:
            guard
                let credential = ZaiCredential(
                    apiKey: form.apiKey
                )
            else {
                return
            }
            connect(using: credential)
        default:
            preconditionFailure(
                "Provider does not use an API-key connection."
            )
        }
    }

    private var presentation:
        APIKeyConnectionPresentation
    {
        APIKeyConnectionPresentation(provider: provider)
    }

    private func connect<
        Credential: Codable & Sendable
    >(
        using credential: Credential
    ) {
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
                errorMessage = presentation.failureMessage
                isConnecting = false
            }
        }
    }
}
