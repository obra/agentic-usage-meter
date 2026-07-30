import Foundation

public enum ClaudeLoginCookieDetector {
    public static func hasSession(in cookies: [HTTPCookie]) -> Bool {
        apiCookies(in: cookies) != nil
    }

    public static func apiCookies(
        in cookies: [HTTPCookie]
    ) -> [HTTPCookie]? {
        let allowedNames = [
            "sessionKey",
            "cf_clearance",
            "__cf_bm"
        ]
        let selected = cookies.filter { cookie in
            allowedNames.contains(cookie.name)
                && !cookie.value.isEmpty
                && isClaudeDomain(cookie.domain)
        }
        guard selected.contains(where: { $0.name == "sessionKey" }) else {
            return nil
        }
        return selected
    }

    static func isClaudeDomain(_ domain: String) -> Bool {
        domain == "claude.ai" || domain.hasSuffix(".claude.ai")
    }
}
