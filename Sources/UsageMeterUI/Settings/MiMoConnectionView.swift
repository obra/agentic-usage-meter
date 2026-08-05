import SwiftUI
import UsageMeterCore
import WebKit

public struct MiMoConnectionView: View {
    private let model: MiMoConnectionModel
    private let onComplete: () -> Void
    @State private var displayName: String

    public init(
        model: MiMoConnectionModel,
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
                connectionIntroduction
            case .signingIn:
                signingInView
            case .readyToSave:
                saveForm
            case .saving:
                ProgressView(
                    "Saving MiMo account…"
                )
            case .complete:
                Label(
                    "MiMo account connected",
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
            Text("Sign in to MiMo")
                .font(
                    .title2.weight(.semibold)
                )
            Text(
                "The Xiaomi MiMo platform opens in an isolated browser profile. Usage appears once the token-plan balance is reachable."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 480)

            Label(
                "Each connected account keeps its own MiMo session and signed-in dashboard.",
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
                MiMoWebView(
                    webView: webView
                )
            }
            if !model.hasRenderedLoginPage {
                ProgressView(
                    "Opening MiMo sign-in…"
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

    private var saveForm: some View {
        Form {
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

    private func failureView(
        _ message: String
    ) -> some View {
        ContentUnavailableView {
            Label(
                "MiMo connection failed",
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

private struct MiMoWebView:
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
