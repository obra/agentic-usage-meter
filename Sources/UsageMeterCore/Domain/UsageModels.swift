import Foundation

public enum Provider: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
    case kimi
}

public struct SubscriptionAccount: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var provider: Provider
    public var displayName: String
    public var authenticatedIdentity: String?
    public var displayOrder: Int

    public init(
        id: UUID = UUID(),
        provider: Provider,
        displayName: String,
        authenticatedIdentity: String? = nil,
        displayOrder: Int
    ) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.authenticatedIdentity = authenticatedIdentity
        self.displayOrder = displayOrder
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

    public var startAt: Date {
        resetAt.addingTimeInterval(-duration)
    }

    public var remainingFraction: Double {
        1 - consumedFraction
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
