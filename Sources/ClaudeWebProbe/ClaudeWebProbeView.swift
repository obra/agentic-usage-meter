import SwiftUI
import WebKit

struct ClaudeWebProbeView: View {
    @ObservedObject var model: ClaudeWebProbeModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Claude account")
                    .font(.headline)
                Text(model.profileID.uuidString.lowercased())
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            Divider()

            switch model.phase {
            case .signingIn:
                ZStack {
                    if let webView = model.webView {
                        ClaudeWebView(webView: webView)
                    }
                    if !model.hasRenderedLoginPage {
                        ProgressView("Opening Claude sign-in…")
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity
                            )
                            .background(Color(nsColor: .windowBackgroundColor))
                    }
                }
            case .loadingOrganizations:
                ProgressView("Loading organizations…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loadingUsage:
                ProgressView(
                    "Checking the tracker-compatible organization…"
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .complete:
                Label(
                    "Qualification complete",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ContentUnavailableView(
                    "Qualification failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            }
        }
        .frame(minWidth: 440, minHeight: 560)
    }
}

private struct ClaudeWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
