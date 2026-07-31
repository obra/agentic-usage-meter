import AppKit
import Foundation
import UsageMeterCore
import UsageMeterWeb
import WebKit

enum OpenCodeLoginDetector {
    static func workspaceID(in url: URL) -> String? {
        guard
            let host = url.host,
            isOpenCodeDomain(host)
        else {
            return nil
        }
        let components = url.path.split(
            separator: "/",
            omittingEmptySubsequences: true
        )
        guard
            components.count >= 2,
            components[0] == "workspace"
        else {
            return nil
        }
        let workspaceID =
            String(components[1])
            .removingPercentEncoding?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        guard
            let workspaceID,
            !workspaceID.isEmpty
        else {
            return nil
        }
        return workspaceID
    }

    static func authCookie(
        in cookies: [HTTPCookie]
    ) -> String? {
        cookies.first { cookie in
            cookie.name == "auth"
                && !cookie.value.isEmpty
                && isOpenCodeDomain(
                    cookie.domain
                )
        }?.value
    }

    private static func isOpenCodeDomain(
        _ domain: String
    ) -> Bool {
        let domain = domain.lowercased()
            .trimmingCharacters(
                in: CharacterSet(
                    charactersIn: "."
                )
            )
        return domain == "opencode.ai"
            || domain.hasSuffix(".opencode.ai")
    }
}

@MainActor
final class OpenCodeLoginSession: NSObject {
    private let accountID: UUID
    private let onPageReady: @MainActor () -> Void
    private let onAuthenticated:
        @MainActor (
            OpenCodeDashboardCredential
        ) -> Void

    private var profileStore: AccountWebProfileStore?
    private var cookieStore: WKHTTPCookieStore?
    private var webView: WKWebView?
    private var popupPanel: NSPanel?
    private var popupWebView: WKWebView?
    private var workspaceID: String?
    private var authCookie: String?
    private var isFinished = false

    init(
        accountID: UUID,
        onPageReady:
            @escaping @MainActor () -> Void =
            {},
        onAuthenticated:
            @escaping @MainActor (
                OpenCodeDashboardCredential
            ) -> Void
    ) {
        self.accountID = accountID
        self.onPageReady = onPageReady
        self.onAuthenticated = onAuthenticated
    }

    func start() -> WKWebView {
        if let webView {
            return webView
        }

        let profileStore =
            AccountWebProfileStore(
                accountID: accountID
            )
        let configuration =
            WKWebViewConfiguration()
        configuration.websiteDataStore =
            profileStore.dataStore
        configuration.preferences
            .javaScriptCanOpenWindowsAutomatically =
            true

        let webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )
        webView.navigationDelegate = self
        webView.uiDelegate = self
        self.profileStore = profileStore
        self.webView = webView

        let cookieStore =
            profileStore.dataStore
            .httpCookieStore
        self.cookieStore = cookieStore
        cookieStore.add(self)
        searchForAuthentication(
            in: cookieStore
        )
        webView.load(
            URLRequest(
                url: URL(
                    string:
                        "https://opencode.ai/auth"
                )!
            )
        )
        return webView
    }

    func close() {
        isFinished = true
        cookieStore?.remove(self)
        cookieStore = nil
        closePopup()
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
        profileStore = nil
    }

    private func consider(_ url: URL?) {
        guard
            !isFinished,
            let url,
            let workspaceID =
                OpenCodeLoginDetector.workspaceID(
                    in: url
                )
        else {
            return
        }
        self.workspaceID = workspaceID
        completeIfReady()
    }

    private func searchForAuthentication(
        in cookieStore: WKHTTPCookieStore
    ) {
        cookieStore.getAllCookies {
            [weak self] cookies in
            guard
                let self,
                !self.isFinished
            else {
                return
            }
            self.authCookie =
                OpenCodeLoginDetector
                .authCookie(in: cookies)
            self.completeIfReady()
        }
    }

    private func completeIfReady() {
        guard
            !isFinished,
            let workspaceID,
            let authCookie
        else {
            return
        }
        isFinished = true
        cookieStore?.remove(self)
        cookieStore = nil
        closePopup()
        onAuthenticated(
            OpenCodeDashboardCredential(
                workspaceID: workspaceID,
                authCookie: authCookie
            )
        )
    }

    private func closePopup() {
        popupWebView?.stopLoading()
        popupWebView?.navigationDelegate = nil
        popupWebView?.uiDelegate = nil
        popupPanel?.close()
        popupWebView = nil
        popupPanel = nil
    }
}

extension OpenCodeLoginSession:
    WKNavigationDelegate,
    WKUIDelegate,
    WKHTTPCookieStoreObserver
{
    func cookiesDidChange(
        in cookieStore: WKHTTPCookieStore
    ) {
        searchForAuthentication(
            in: cookieStore
        )
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        onPageReady()
        consider(webView.url)
        searchForAuthentication(
            in: webView.configuration
                .websiteDataStore
                .httpCookieStore
        )
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction:
            WKNavigationAction,
        decisionHandler:
            @escaping @MainActor (
                WKNavigationActionPolicy
            ) -> Void
    ) {
        consider(
            navigationAction.request.url
        )
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration:
            WKWebViewConfiguration,
        for navigationAction:
            WKNavigationAction,
        windowFeatures:
            WKWindowFeatures
    ) -> WKWebView? {
        closePopup()

        let frame = NSRect(
            x: 0,
            y: 0,
            width: 560,
            height: 680
        )
        let popupWebView = WKWebView(
            frame: frame,
            configuration: configuration
        )
        popupWebView.navigationDelegate =
            self
        popupWebView.uiDelegate = self

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [
                .titled,
                .closable,
                .resizable,
            ],
            backing: .buffered,
            defer: false
        )
        panel.title = "Sign In to OpenCode"
        panel.contentView = popupWebView
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        self.popupWebView = popupWebView
        popupPanel = panel
        return popupWebView
    }

    func webViewDidClose(
        _ webView: WKWebView
    ) {
        guard webView === popupWebView else {
            return
        }
        closePopup()
    }
}
