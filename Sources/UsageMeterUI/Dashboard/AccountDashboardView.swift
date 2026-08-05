import AppKit
import SwiftUI
import UsageMeterCore
import UsageMeterWeb
import WebKit

struct AccountDashboardRoute: Equatable {
    let accountID: UUID
    let webProfileID: UUID
    let strategy: ProviderDashboardStrategy

    init(
        account: SubscriptionAccount,
        strategy: ProviderDashboardStrategy
    ) {
        accountID = account.id
        webProfileID = account.claudeProfileID ?? account.id
        self.strategy = Self.resolvedStrategy(
            for: account,
            fallback: strategy
        )
    }

    private static func resolvedStrategy(
        for account: SubscriptionAccount,
        fallback: ProviderDashboardStrategy
    ) -> ProviderDashboardStrategy {
        guard
            let workspaceID =
                account.authenticatedIdentity?
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
            !workspaceID.isEmpty
        else {
            return fallback
        }
        let page: String
        switch account.provider {
        case .openCodeGo:
            page = "go"
        case .openCodeZen:
            page = "billing"
        default:
            return fallback
        }
        guard
            let url = URL(
                string:
                    "https://opencode.ai/workspace/\(workspaceID)/\(page)"
            )
        else {
            return fallback
        }
        return .embedded(url)
    }
}

enum AccountRowAction: Equatable {
    case rename
    case refresh
    case reconnect
    case openDashboard

    static func resolved(
        clickedName: Bool,
        explicitControl: AccountRowAction?
    ) -> AccountRowAction {
        if let explicitControl {
            return explicitControl
        }
        return clickedName ? .rename : .openDashboard
    }
}

struct AccountDashboardView: View {
    let route: AccountDashboardRoute
    let state: AccountViewState

    var body: some View {
        switch route.strategy {
        case let .embedded(url):
            AccountDashboardWebView(
                url: url,
                profileID: route.webProfileID
            )
        case let .nativeDetail(externalURL):
            nativeDetail(externalURL: externalURL)
        case let .external(url):
            Color.clear
                .onAppear {
                    NSWorkspace.shared.open(url)
                }
        }
    }

    private func nativeDetail(
        externalURL: URL?
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.account.displayName)
                        .font(.title2.weight(.semibold))
                    if let identity =
                        state.account.authenticatedIdentity
                    {
                        Text(identity)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let externalURL {
                    Button("Open Provider Dashboard") {
                        NSWorkspace.shared.open(externalURL)
                    }
                }
            }

            Divider()

            if state.snapshot == nil {
                ContentUnavailableView {
                    Label(
                        "No usage data",
                        systemImage: "gauge.open.with.lines.needle.33percent"
                    )
                } description: {
                    Text(nativeStatusText)
                }
            } else {
                UsageTimelineView(accounts: [state])
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 300)
    }

    private var nativeStatusText: String {
        switch state.error {
        case .authenticationRequired:
            "Reconnect this account to load usage."
        case .subscriptionRequired:
            "This subscription is not active for the selected workspace."
        case .temporarilyUnavailable:
            "The provider is temporarily unavailable."
        case .unsupportedResponse:
            "The provider response is not currently supported."
        case nil:
            "Usage has not been fetched yet."
        }
    }
}

private struct AccountDashboardWebView: NSViewRepresentable {
    let url: URL
    let profileID: UUID

    func makeNSView(context _: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore =
            AccountWebProfileStore(
                accountID: profileID
            ).dataStore
        let webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(
        _ webView: WKWebView,
        context _: Context
    ) {
        guard webView.url != url else {
            return
        }
        webView.load(URLRequest(url: url))
    }
}
