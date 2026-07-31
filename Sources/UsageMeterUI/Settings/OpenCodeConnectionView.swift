import SwiftUI
import UsageMeterCore
import WebKit

public struct OpenCodeConnectionView:
    View
{
    private let provider: Provider
    private let model: OpenCodeConnectionModel
    private let onComplete: () -> Void
    @State private var displayName: String

    public init(
        provider: Provider,
        model: OpenCodeConnectionModel,
        suggestedName: String,
        onComplete: @escaping () -> Void
    ) {
        precondition(
            provider == .openCodeGo
                || provider == .openCodeZen
        )
        self.provider = provider
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
                connectionIntroduction
            case .signingIn:
                signingInView
            case .readyToSave(
                let workspaceID
            ):
                saveForm(
                    workspaceID: workspaceID
                )
            case .duplicateIdentity(
                let workspaceID
            ):
                duplicateView(
                    workspaceID: workspaceID
                )
            case .saving:
                ProgressView(
                    "Saving \(providerName) account…"
                )
            case .complete:
                Label(
                    "\(providerName) account connected",
                    systemImage:
                        "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
            case .failed(let message):
                failureView(message)
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
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
            Text("Sign in to \(providerName)")
                .font(
                    .title2.weight(.semibold)
                )
            Text(
                "OpenCode opens in an isolated browser profile. Choose the workspace you want this account to track after signing in."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 480)

            Label(
                "Each connected account keeps its own OpenCode session and signed-in dashboard.",
                systemImage: "person.2"
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            Button("Continue") {
                Task {
                    await model.start()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var signingInView: some View {
        ZStack {
            if let webView = model.webView {
                OpenCodeWebView(
                    webView: webView
                )
            }
            if !model.hasRenderedLoginPage {
                ProgressView(
                    "Opening OpenCode sign-in…"
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                .background(
                    Color(
                        nsColor:
                            .windowBackgroundColor
                    )
                )
            }
        }
    }

    private func saveForm(
        workspaceID: String
    ) -> some View {
        Form {
            LabeledContent(
                "Workspace"
            ) {
                Text(workspaceID)
                    .textSelection(.enabled)
            }
            TextField(
                "Account name",
                text: $displayName
            )
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
        .formStyle(.grouped)
        .frame(maxWidth: 500)
    }

    private func duplicateView(
        workspaceID: String
    ) -> some View {
        ContentUnavailableView {
            Label(
                "Workspace already connected",
                systemImage:
                    "exclamationmark.triangle"
            )
        } description: {
            Text(
                "\(workspaceID) is already connected to \(providerName)."
            )
        } actions: {
            Button("Choose Another Workspace") {
                Task {
                    await model.start()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func failureView(
        _ message: String
    ) -> some View {
        ContentUnavailableView {
            Label(
                "\(providerName) connection failed",
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
            .buttonStyle(.borderedProminent)
        }
    }

    private var providerName: String {
        ProviderCatalog.live.definition(
            for: provider
        )?.displayName ?? "OpenCode"
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

private struct OpenCodeWebView:
    NSViewRepresentable
{
    let webView: WKWebView

    func makeNSView(
        context _: Context
    ) -> WKWebView {
        webView
    }

    func updateNSView(
        _: WKWebView,
        context _: Context
    ) {}
}
