import Foundation

public struct OAuthCredential: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var idToken: String?
    public var accountID: String?
    public var expiresAt: Date?

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        idToken: String? = nil,
        accountID: String? = nil,
        expiresAt: Date? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.accountID = accountID
        self.expiresAt = expiresAt
    }
}

public enum ProviderCredential: Codable, Equatable, Sendable {
    case claude(token: String)
    case codex(OAuthCredential)
    case kimi(OAuthCredential)
}
