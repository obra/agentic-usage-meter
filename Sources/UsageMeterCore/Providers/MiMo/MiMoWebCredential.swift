import Foundation

public struct MiMoWebCredential: Codable, Equatable, Sendable {
    public let cookieHeader: String

    public init?(cookieHeader: String) {
        let value = cookieHeader.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !value.isEmpty else {
            return nil
        }
        self.cookieHeader = value
    }
}
