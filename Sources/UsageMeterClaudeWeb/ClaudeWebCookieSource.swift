import Foundation
import WebKit

@MainActor
public protocol ClaudeWebCookieSource: AnyObject {
    func cookies(for url: URL, profileID: UUID) async -> [HTTPCookie]
    func prepareForRemoval(profileID: UUID)
    func finishRemoval(profileID: UUID)
}

extension ClaudeWebCookieSource {
    public func prepareForRemoval(profileID _: UUID) {}
    public func finishRemoval(profileID _: UUID) {}
}

@MainActor
public final class WebKitClaudeCookieSource: ClaudeWebCookieSource {
    private let profileFactory:
        @MainActor (UUID) -> any ClaudeWebProfileCookieLoading
    private var profiles:
        [UUID: any ClaudeWebProfileCookieLoading] = [:]
    private var removalLeaseCounts: [UUID: Int] = [:]

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
        guard removalLeaseCounts[profileID] == nil else {
            return []
        }

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

    // Removing a profile's website data store fails while any live
    // reference to it exists, so removal must first evict the cached
    // loader and keep new loads from re-creating it.
    public func prepareForRemoval(profileID: UUID) {
        removalLeaseCounts[profileID, default: 0] += 1
        profiles[profileID] = nil
    }

    public func finishRemoval(profileID: UUID) {
        guard let leaseCount = removalLeaseCounts[profileID] else {
            assertionFailure("Claude profile removal lease underflow")
            return
        }
        if leaseCount == 1 {
            removalLeaseCounts[profileID] = nil
        } else {
            removalLeaseCounts[profileID] = leaseCount - 1
        }
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
