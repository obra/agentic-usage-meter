import Foundation
import WebKit

@MainActor
public protocol ClaudeWebCookieSource: AnyObject {
    func cookies(for url: URL, profileID: UUID) async -> [HTTPCookie]
}

@MainActor
public final class WebKitClaudeCookieSource: ClaudeWebCookieSource {
    private let profileFactory:
        @MainActor (UUID) -> any ClaudeWebProfileCookieLoading
    private var profiles:
        [UUID: any ClaudeWebProfileCookieLoading] = [:]

    public convenience init() {
        self.init { profileID in
            WebKitClaudeWebProfileCookieLoader(
                profileID: profileID
            )
        }
    }

    init(
        profileFactory:
            @escaping @MainActor (UUID) ->
            any ClaudeWebProfileCookieLoading
    ) {
        self.profileFactory = profileFactory
    }

    public func cookies(
        for _: URL,
        profileID: UUID
    ) async -> [HTTPCookie] {
        let profile: any ClaudeWebProfileCookieLoading
        if let existing = profiles[profileID] {
            profile = existing
        } else {
            let created = profileFactory(profileID)
            profiles[profileID] = created
            profile = created
        }

        let cookies = await profile.cookies()
        if !ClaudeLoginCookieDetector.hasSession(in: cookies) {
            profile.warmIfNeeded()
        }
        return cookies
    }
}

@MainActor
protocol ClaudeWebProfileCookieLoading: AnyObject {
    func cookies() async -> [HTTPCookie]
    func warmIfNeeded()
}

@MainActor
private final class WebKitClaudeWebProfileCookieLoader:
    ClaudeWebProfileCookieLoading
{
    private static let warmupURL =
        URL(string: "https://claude.ai/robots.txt")!

    private let profileStore: ClaudeWebProfileStore
    private var warmupWebView: WKWebView?
    private var didStartWarmup = false

    init(profileID: UUID) {
        profileStore = ClaudeWebProfileStore(
            profileID: profileID
        )
    }

    func cookies() async -> [HTTPCookie] {
        let cookies = await withCheckedContinuation { continuation in
            profileStore.dataStore.httpCookieStore
                .getAllCookies { cookies in
                    continuation.resume(returning: cookies)
                }
        }
        if ClaudeLoginCookieDetector.hasSession(in: cookies) {
            warmupWebView?.stopLoading()
            warmupWebView = nil
        }
        return cookies
    }

    func warmIfNeeded() {
        guard !didStartWarmup else {
            return
        }
        didStartWarmup = true

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = profileStore.dataStore
        let webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )
        warmupWebView = webView
        webView.load(URLRequest(url: Self.warmupURL))
    }
}
