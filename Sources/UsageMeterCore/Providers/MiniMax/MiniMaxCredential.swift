import Foundation

public struct MiniMaxCredential: Codable, Equatable, Sendable {
    public let apiKey: String

    public init?(apiKey: String) {
        let value = apiKey.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !value.isEmpty else {
            return nil
        }
        self.apiKey = value
    }
}
