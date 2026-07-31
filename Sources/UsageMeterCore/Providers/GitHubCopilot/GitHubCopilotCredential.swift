import Foundation

public struct GitHubCopilotCredential:
    Codable,
    Equatable,
    Sendable
{
    public let accessToken: String
    public let userID: String
    public let login: String

    public init(
        accessToken: String,
        userID: String,
        login: String
    ) {
        self.accessToken = accessToken
        self.userID = userID
        self.login = login
    }
}

public struct GitHubCopilotOAuthResult:
    Equatable,
    Sendable
{
    public let credential: GitHubCopilotCredential

    public init(
        credential: GitHubCopilotCredential
    ) {
        self.credential = credential
    }
}
