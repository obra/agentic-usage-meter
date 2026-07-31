import Foundation

public struct OpenCodeDashboardCredential:
    Codable,
    Equatable,
    Sendable
{
    public let workspaceID: String
    public let authCookie: String

    public init(
        workspaceID: String,
        authCookie: String
    ) {
        self.workspaceID = workspaceID
        self.authCookie = authCookie
    }

    public var identityKey: String? {
        normalized(workspaceID)
    }

    private func normalized(
        _ value: String
    ) -> String? {
        let value = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return value.isEmpty ? nil : value
    }
}
