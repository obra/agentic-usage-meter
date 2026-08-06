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

public enum ClaudeOrganizationSelection {
    // The organizations endpoint also lists Anthropic Console ("api")
    // organizations, whose usage endpoint does not serve subscription
    // quota. Only chat-capable organizations can qualify an account.
    public static func qualified(
        from organizations: [ClaudeOrganization]
    ) -> [ClaudeOrganization] {
        organizations.filter {
            $0.capabilities.contains("chat")
        }
    }
}
