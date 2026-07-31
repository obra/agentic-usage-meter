import SwiftUI

public struct GitHubCopilotConnectionView:
    View
{
    private let model: GitHubCopilotConnectionModel
    private let onComplete: () -> Void
    @State private var displayName: String

    public init(
        model: GitHubCopilotConnectionModel,
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
                    "Requesting GitHub authorization…"
                )
            case .waitingForApproval:
                waitingView
            case let .readyToSave(login):
                saveForm(login: login)
            case let .duplicateIdentity(login):
                ContentUnavailableView {
                    Label(
                        "GitHub account already connected",
                        systemImage:
                            "person.crop.circle.badge.checkmark"
                    )
                } description: {
                    Text(
                        "\(login) already has a Copilot row."
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
                    "Validating Copilot usage…"
                )
            case .complete:
                Label(
                    "GitHub Copilot account connected",
                    systemImage:
                        "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
            case let .failed(message):
                ContentUnavailableView {
                    Label(
                        "Copilot connection failed",
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
        .onDisappear {
            model.cancel()
        }
    }

    private var introduction: some View {
        VStack(spacing: 12) {
            Image(
                systemName:
                    "chevron.left.forwardslash.chevron.right"
            )
            .font(.system(size: 36))
            Text("Connect GitHub Copilot")
                .font(.title2.weight(.semibold))
            Text(
                "GitHub device authorization opens in your regular browser. You can choose a different signed-in GitHub account there."
            )
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            Button("Open GitHub") {
                Task {
                    await model.start()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: 520)
    }

    @ViewBuilder
    private var waitingView: some View {
        if let prompt = model.prompt {
            VStack(spacing: 12) {
                Text(
                    "Approve this device in GitHub"
                )
                .font(.headline)
                Text(prompt.userCode)
                    .font(.title.monospaced())
                    .textSelection(.enabled)
                Link(
                    "Open GitHub Authorization",
                    destination:
                        prompt.verificationURL
                )
                Text(
                    "Code expires \(prompt.expiresAt.formatted(.relative(presentation: .named)))"
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
        login: String
    ) -> some View {
        Form {
            Section {
                LabeledContent(
                    "GitHub account",
                    value: login
                )
                TextField(
                    "Account name",
                    text: $displayName
                )
            } footer: {
                Text(
                    "The OAuth token is stored only in this account's macOS Keychain record."
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
        .frame(maxWidth: 520)
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
