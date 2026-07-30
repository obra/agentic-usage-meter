import Foundation
import WebKit

@MainActor
public protocol ClaudeWebCookieSource: AnyObject {
    func cookies(for url: URL, profileID: UUID) async -> [HTTPCookie]
}

@MainActor
public final class WebKitClaudeCookieSource: ClaudeWebCookieSource {
    public init() {}

    public func cookies(for url: URL, profileID: UUID) async -> [HTTPCookie] {
        let store = WKWebsiteDataStore(forIdentifier: profileID)
        return await withCheckedContinuation { continuation in
            store.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }
}
