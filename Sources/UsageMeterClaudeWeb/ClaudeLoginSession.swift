import AppKit
import Foundation
import WebKit

@MainActor
public final class ClaudeLoginSession: NSObject {
    public let profileID: UUID
    public private(set) var webView: WKWebView?

    private let onPageReady: @MainActor () -> Void
    private let onAuthenticated:
        @MainActor (UUID, [HTTPCookie]) -> Void
    private var profileStore: ClaudeWebProfileStore?
    private var cookieStore: WKHTTPCookieStore?
    private var popupPanel: NSPanel?
    private var popupWebView: WKWebView?
    private var pollTimer: Timer?
    private var pollsSinceLoginLeft = 0
    private var reloadAttempts = 0
    private var isFinished = false

    public init(
        profileID: UUID,
        onPageReady: @escaping @MainActor () -> Void = {},
        onAuthenticated:
            @escaping @MainActor (UUID, [HTTPCookie]) -> Void
    ) {
        self.profileID = profileID
        self.onPageReady = onPageReady
        self.onAuthenticated = onAuthenticated
    }

    public func start() -> WKWebView {
        if let webView {
            return webView
        }

        let profileStore = ClaudeWebProfileStore(profileID: profileID)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = profileStore.dataStore
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        self.profileStore = profileStore
        self.webView = webView
        startMonitoring(profileStore.dataStore.httpCookieStore)
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        return webView
    }

    public func close() {
        isFinished = true
        stopMonitoring()
        closePopup()
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
        profileStore = nil
    }

    public func cancel() async throws {
        close()
        try await ClaudeWebProfileStore.remove(profileID: profileID)
    }

    private func startMonitoring(_ cookieStore: WKHTTPCookieStore) {
        self.cookieStore = cookieStore
        cookieStore.add(self)

        let timer = Timer(
            timeInterval: 1,
            target: self,
            selector: #selector(pollForSession),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        searchForSession(in: cookieStore)
    }

    private func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        cookieStore?.remove(self)
        cookieStore = nil
    }

    @objc
    private func pollForSession() {
        guard !isFinished, let cookieStore else {
            stopMonitoring()
            return
        }
        searchForSession(in: cookieStore)
        reloadIfLoggedInWithoutVisibleSession()
    }

    private func searchForSession(in cookieStore: WKHTTPCookieStore) {
        cookieStore.getAllCookies { [weak self] cookies in
            guard let self, !self.isFinished else {
                return
            }
            guard
                let apiCookies =
                    ClaudeLoginCookieDetector.apiCookies(
                        in: cookies
                    )
            else {
                return
            }
            self.completeLogin(cookies: apiCookies)
        }
    }

    private func completeLogin(cookies: [HTTPCookie]) {
        guard !isFinished else {
            return
        }
        isFinished = true
        stopMonitoring()
        closePopup()
        onAuthenticated(profileID, cookies)
    }

    private func reloadIfLoggedInWithoutVisibleSession() {
        guard !isFinished, let url = webView?.url else {
            return
        }
        guard Self.isClaudeURL(url), !url.path.hasPrefix("/login") else {
            pollsSinceLoginLeft = 0
            return
        }

        pollsSinceLoginLeft += 1
        guard pollsSinceLoginLeft >= 3, reloadAttempts < 3 else {
            return
        }
        pollsSinceLoginLeft = 0
        reloadAttempts += 1
        webView?.reloadFromOrigin()
    }

    private func closePopup() {
        popupWebView?.stopLoading()
        popupWebView?.navigationDelegate = nil
        popupWebView?.uiDelegate = nil
        popupPanel?.close()
        popupWebView = nil
        popupPanel = nil
    }

    private static func isClaudeURL(_ url: URL) -> Bool {
        guard let host = url.host else {
            return false
        }
        return host == "claude.ai" || host.hasSuffix(".claude.ai")
    }
}

extension ClaudeLoginSession:
    WKNavigationDelegate,
    WKUIDelegate,
    WKHTTPCookieStoreObserver
{
    public func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        guard !isFinished else {
            return
        }
        searchForSession(in: cookieStore)
    }

    public func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        guard !isFinished else {
            return
        }
        onPageReady()
        searchForSession(
            in: webView.configuration.websiteDataStore.httpCookieStore
        )
    }

    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        closePopup()

        let frame = NSRect(x: 0, y: 0, width: 500, height: 600)
        let popupWebView = WKWebView(
            frame: frame,
            configuration: configuration
        )
        popupWebView.navigationDelegate = self
        popupWebView.uiDelegate = self

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Sign In"
        panel.contentView = popupWebView
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        self.popupWebView = popupWebView
        popupPanel = panel
        return popupWebView
    }

    public func webViewDidClose(_ webView: WKWebView) {
        guard webView === popupWebView else {
            return
        }
        closePopup()
    }
}
