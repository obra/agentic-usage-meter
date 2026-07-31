import SwiftUI

public struct SuperGrokConnectionView: View {
    @Environment(\.openURL) private var openURL

    private let model: SuperGrokConnectionModel
    private let onComplete: () -> Void
    @State private var displayName: String

    public init(
        model: SuperGrokConnectionModel,
        suggestedName: String,
        onComplete: @escaping () -> Void
    ) {
        self.model = model
        self.onComplete = onComplete
        _displayName = State(
            initialValue: suggestedName
        )
    }

    public var body: some View {
        VStack(spacing: 16) {
            switch model.phase {
            case .idle:
                introduction
            case .authorizing:
                ProgressView(
                    "Starting Grok device authorization…"
                )
            case .waitingForApproval:
                waitingView
            case let .readyToSave(identity):
                saveForm(identity: identity)
            case let .duplicateIdentity(identity):
                ContentUnavailableView {
                    Label(
                        "Grok account already connected",
                        systemImage:
                            "person.crop.circle.badge.checkmark"
                    )
                } description: {
                    Text(
                        "\(identity) already has a SuperGrok row."
                    )
                } actions: {
                    Button("Use Another Account") {
                        Task {
                            await model.start()
                        }
                    }
                }
            case .saving:
                ProgressView(
                    "Saving SuperGrok account…"
                )
            case .complete:
                Label(
                    "SuperGrok account connected",
                    systemImage:
                        "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
            case let .failed(message):
                ContentUnavailableView {
                    Label(
                        "SuperGrok connection failed",
                        systemImage:
                            "exclamationmark.triangle"
                    )
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") {
                        Task {
                            await model.start()
                        }
                    }
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
        .onChange(of: model.prompt) {
            _, prompt in
            if let prompt {
                openURL(prompt.verificationURL)
            }
        }
        .onDisappear {
            model.cancel()
        }
    }

    private var introduction: some View {
        VStack(spacing: 12) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 36))
            Text("Connect SuperGrok")
                .font(
                    .title2.weight(.semibold)
                )
            Text(
                "The Grok CLI signs this account in inside a temporary isolated profile. Approval opens in your regular browser, and the resulting token is stored only in this account's Keychain record."
            )
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            Button("Open Grok Authorization") {
                Task {
                    await model.start()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: 540)
    }

    @ViewBuilder
    private var waitingView: some View {
        if let prompt = model.prompt {
            VStack(spacing: 12) {
                Text(
                    "Approve this device with xAI"
                )
                .font(.headline)
                Text(prompt.userCode)
                    .font(.title.monospaced())
                    .textSelection(.enabled)
                Link(
                    "Open Grok Authorization",
                    destination:
                        prompt.verificationURL
                )
                Text(
                    "The app is waiting for approval in your browser."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                ProgressView()
            }
        } else {
            ProgressView(
                "Waiting for device code…"
            )
        }
    }

    private func saveForm(
        identity: String
    ) -> some View {
        Form {
            Section {
                LabeledContent(
                    "Grok account",
                    value: identity
                )
                TextField(
                    "Account name",
                    text: $displayName
                )
            } footer: {
                Text(
                    "Usage and the embedded Grok dashboard remain isolated per account. The first dashboard open may ask you to sign in again."
                )
            }

            HStack {
                Spacer()
                Button("Save Account") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    displayName
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )
                        .isEmpty
                )
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 540)
    }

    private func save() {
        Task {
            do {
                try await model.save(
                    displayName: displayName
                )
                onComplete()
            } catch {
                return
            }
        }
    }
}
