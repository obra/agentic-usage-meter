import SwiftUI
import WebKit

struct ClaudeConnectionGuidance {
    enum SignInMethod {
        case email
    }

    let allowsGoogleSignIn: Bool
    let recommendedSignInMethod: SignInMethod

    static let embeddedBrowser =
        ClaudeConnectionGuidance(
            allowsGoogleSignIn: false,
            recommendedSignInMethod: .email,
        )

    var message: String {
        "Use email sign-in here. Continue with Google won't work in this isolated browser."
    }
}

public struct ClaudeConnectionView: View {
    private let model: ClaudeConnectionModel
    private let onComplete: () -> Void
    @State private var displayName: String

    public init(
        model: ClaudeConnectionModel,
        suggestedName: String,
        onComplete: @escaping () -> Void,
    ) {
        self.model = model
        self.onComplete = onComplete
        _displayName = State(initialValue: suggestedName)
    }

    public var body: some View {
        VStack(spacing: 16) {
            switch model.phase {
            case .idle:
                connectionIntroduction
            case .signingIn:
                ZStack {
                    if let webView = model.webView {
                        ClaudeWebView(webView: webView)
                    }
                    if !model.hasRenderedLoginPage {
                        ProgressView(
                            "Opening Claude sign-in…",
                        )
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                        )
                        .background(
                            Color(nsColor: .windowBackgroundColor),
                        )
                    }
                }
            case .loadingOrganizations:
                ProgressView("Loading Claude organizations…")
            case let .choosingOrganizations(choices):
                organizationChoiceForm(choices)
            case .loadingUsage:
                ProgressView("Validating Claude usage…")
            case let .readyToSave(
                organizationName,
                organizationCount,
            ):
                saveForm(
                    detail:
                    organizationCount > 1
                        ? "\(organizationName) (first of \(organizationCount) organizations)"
                        : organizationName,
                )
            case let .readyToSaveOrganizations(connections):
                selectionSaveForm(connections)
            case .saving:
                ProgressView("Saving Claude account…")
            case .complete:
                completionLabel
            case let .failed(message):
                failureView(message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            Task {
                await model.cancel()
            }
        }
    }

    private var connectionIntroduction: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 36))
            Text("Sign in to Claude")
                .font(.title2.weight(.semibold))
            Text(
                "Claude opens in an isolated embedded browser profile. Other Claude accounts remain signed in separately.",
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 440)

            Label {
                Text(
                    ClaudeConnectionGuidance
                        .embeddedBrowser.message,
                )
                .multilineTextAlignment(.leading)
            } icon: {
                Image(
                    systemName:
                        "exclamationmark.triangle",
                )
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(10)
            .frame(maxWidth: 440)
            .background(
                Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 10),
            )

            Button("Continue") {
                Task {
                    await model.start()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func saveForm(detail: String) -> some View {
        Form {
            LabeledContent("Authenticated as") {
                Text(detail)
                    .textSelection(.enabled)
            }
            TextField("Account name", text: $displayName)
            Button("Save Account") {
                save()
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                displayName.trimmingCharacters(
                    in: .whitespacesAndNewlines,
                ).isEmpty,
            )
        }
        .formStyle(.grouped)
        .frame(maxWidth: 500)
    }

    private func organizationChoiceForm(
        _ choices: [ClaudeOrganizationChoice],
    ) -> some View {
        Form {
            Section {
                ForEach(choices) { choice in
                    Toggle(
                        isOn: Binding(
                            get: { choice.isSelected },
                            set: { _ in
                                model.toggleOrganization(
                                    id: choice.id,
                                )
                            },
                        ),
                    ) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(choice.organization.name)
                            if let connectedAccountName =
                                choice.connectedAccountName
                            {
                                Text(
                                    "Already connected as \(connectedAccountName)",
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("This login belongs to several organizations")
            } footer: {
                Text(
                    "Each selected organization becomes its own account.",
                )
            }
            Button("Continue") {
                Task {
                    await model.confirmOrganizationSelection()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!choices.contains(where: \.isSelected))
        }
        .formStyle(.grouped)
        .frame(maxWidth: 500)
    }

    private func selectionSaveForm(
        _ connections: [ClaudeOrganizationConnection],
    ) -> some View {
        Form {
            Section("New accounts") {
                ForEach(connections) { connection in
                    Text(connection.organizationName)
                }
            }
            Button(
                connections.count == 1
                    ? "Save Account"
                    : "Save \(connections.count) Accounts",
            ) {
                Task {
                    await model.saveSelectedOrganizations()
                    if model.phase == .complete {
                        onComplete()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .formStyle(.grouped)
        .frame(maxWidth: 500)
    }

    private var completionLabel: some View {
        Label(
            "Claude account connected",
            systemImage: "checkmark.circle.fill",
        )
        .foregroundStyle(.green)
    }

    private func failureView(_ message: String) -> some View {
        ContentUnavailableView {
            Label(
                "Claude connection failed",
                systemImage: "exclamationmark.triangle",
            )
        } description: {
            Text(message)
        } actions: {
            Button("Try Validation Again") {
                Task {
                    await model.retry()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func save() {
        Task {
            do {
                try await model.save(
                    displayName: displayName,
                )
                onComplete()
            } catch {
                return
            }
        }
    }
}

private struct ClaudeWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context _: Context) -> WKWebView {
        webView
    }

    func updateNSView(
        _: WKWebView,
        context _: Context,
    ) {}
}
