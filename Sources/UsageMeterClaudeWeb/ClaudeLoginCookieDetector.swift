import Foundation

public enum ClaudeLoginCookieDetector {
    public static func hasSession(in cookies: [HTTPCookie]) -> Bool {
        cookies.contains { cookie in
            cookie.name == "sessionKey"
                && !cookie.value.isEmpty
                && isClaudeDomain(cookie.domain)
        }
    }

    static func isClaudeDomain(_ domain: String) -> Bool {
        domain == "claude.ai" || domain.hasSuffix(".claude.ai")
    }
}
