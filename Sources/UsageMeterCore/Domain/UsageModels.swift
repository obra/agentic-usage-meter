import Foundation

public enum Provider: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
    case kimi
    case minimax
    case githubCopilot = "github-copilot"
    case antigravity
    case factory
    case openCodeGo = "opencode-go"
    case openCodeZen = "opencode-zen"
    case superGrok = "supergrok"
}

public struct SubscriptionAccount: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var provider: Provider
    public var displayName: String
    public var authenticatedIdentity: String?
    public var displayOrder: Int
    public var claudeProfileID: UUID?
    public var claudeOrganizationID: UUID?

    public init(
        id: UUID = UUID(),
        provider: Provider,
        displayName: String,
        authenticatedIdentity: String? = nil,
        displayOrder: Int,
        claudeProfileID: UUID? = nil,
        claudeOrganizationID: UUID? = nil,
    ) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.authenticatedIdentity = authenticatedIdentity
        self.displayOrder = displayOrder
        self.claudeProfileID = claudeProfileID
        self.claudeOrganizationID = claudeOrganizationID
    }
}

public enum UsageWindowKind: String, Codable, Sendable {
    case short
    case weekly
}

public struct UsageWindow: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: UsageWindowKind
    public let duration: TimeInterval
    public let resetAt: Date
    public let consumedFraction: Double

    public init?(
        id: String,
        kind: UsageWindowKind,
        duration: TimeInterval,
        resetAt: Date,
        consumedFraction: Double
    ) {
        guard
            !id.isEmpty,
            duration.isFinite,
            duration > 0,
            consumedFraction.isFinite,
            (0 ... 1).contains(consumedFraction)
        else {
            return nil
        }

        self.id = id
        self.kind = kind
        self.duration = duration
        self.resetAt = resetAt
        self.consumedFraction = consumedFraction
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let kind = try container.decode(UsageWindowKind.self, forKey: .kind)
        let duration = try container.decode(TimeInterval.self, forKey: .duration)
        let resetAt = try container.decode(Date.self, forKey: .resetAt)
        let consumedFraction = try container.decode(Double.self, forKey: .consumedFraction)

        guard let window = UsageWindow(
            id: id,
            kind: kind,
            duration: duration,
            resetAt: resetAt,
            consumedFraction: consumedFraction,
        ) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Usage window contains invalid values.",
                ),
            )
        }

        self = window
    }

    public var startAt: Date {
        resetAt.addingTimeInterval(-duration)
    }

    public var remainingFraction: Double {
        1 - consumedFraction
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case duration
        case resetAt
        case consumedFraction
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public let accountID: UUID
    public let fetchedAt: Date
    public let windows: [UsageWindow]

    public init(accountID: UUID, fetchedAt: Date, windows: [UsageWindow]) {
        self.accountID = accountID
        self.fetchedAt = fetchedAt
        self.windows = windows
    }
}
