import Foundation

public struct SuperGrokCredential:
    Codable,
    Equatable,
    Sendable
{
    public let accessToken: String
    public let email: String?
    public let teamID: String?
    public let userID: String?
    public let authMode: String?
    public let expiresAt: Date?
    public let refreshToken: String?
    public let oidcIssuer: String?
    public let oidcClientID: String?
    public let createdAt: Date?

    public init(
        accessToken: String,
        email: String?,
        teamID: String?,
        userID: String?,
        authMode: String?,
        expiresAt: Date?,
        refreshToken: String? = nil,
        oidcIssuer: String? = nil,
        oidcClientID: String? = nil,
        createdAt: Date? = nil
    ) {
        self.accessToken = accessToken
        self.email = email
        self.teamID = teamID
        self.userID = userID
        self.authMode = authMode
        self.expiresAt = expiresAt
        self.refreshToken = refreshToken
        self.oidcIssuer = oidcIssuer
        self.oidcClientID = oidcClientID
        self.createdAt = createdAt
    }

    public var identityKey: String? {
        let userID = normalized(userID)
        let teamID = normalized(teamID)
        if let userID, let teamID {
            return "\(userID)::\(teamID)"
        }
        return userID ?? teamID ?? normalized(email)
    }

    public var displayIdentity: String? {
        normalized(email) ?? normalized(userID)
            ?? normalized(teamID)
    }

    func needsRefresh(at date: Date) -> Bool {
        let refreshDeadline = date.addingTimeInterval(
            5 * 60
        )
        if let expiresAt {
            return expiresAt <= refreshDeadline
        }
        if let createdAt {
            return createdAt.addingTimeInterval(
                30 * 24 * 60 * 60
            ) <= refreshDeadline
        }
        return false
    }

    var hasRefreshMaterial: Bool {
        authMode?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .lowercased() == "oidc"
            && hasValue(refreshToken)
            && hasValue(oidcIssuer)
            && hasValue(oidcClientID)
    }

    private func normalized(
        _ value: String?
    ) -> String? {
        guard
            let value = value?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
            !value.isEmpty
        else {
            return nil
        }
        return value.lowercased()
    }

    private func hasValue(
        _ value: String?
    ) -> Bool {
        value?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty == false
    }
}
