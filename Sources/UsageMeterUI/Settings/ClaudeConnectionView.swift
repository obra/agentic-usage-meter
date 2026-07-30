import SwiftUI
import WebKit

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

    private var completionLabel: some View {
        Label(
            "Claude account connected",
            systemImage: "checkmark.circle.fill",
        )
        .foregroundStyle(.green)
    }

    private func failureView(_ message: String) -> some View {
        ContentUnavailableView(
            "Claude connection failed",
            systemImage: "exclamationmark.triangle",
            description: Text(message),
        )
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
