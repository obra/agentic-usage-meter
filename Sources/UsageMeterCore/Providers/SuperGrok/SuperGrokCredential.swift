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

    public init(
        accessToken: String,
        email: String?,
        teamID: String?,
        userID: String?,
        authMode: String?,
        expiresAt: Date?
    ) {
        self.accessToken = accessToken
        self.email = email
        self.teamID = teamID
        self.userID = userID
        self.authMode = authMode
        self.expiresAt = expiresAt
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
}
