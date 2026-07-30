import Foundation

public struct ClaudeWebProfile: Codable, Equatable, Sendable {
    public let id: UUID

    public init(id: UUID) {
        self.id = id
    }
}

public struct ClaudeOrganization: Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let capabilities: [String]

    public init(id: UUID, name: String, capabilities: [String]) {
        self.id = id
        self.name = name
        self.capabilities = capabilities
    }

    private enum CodingKeys: String, CodingKey {
        case id = "uuid"
        case name
        case capabilities
    }
}
