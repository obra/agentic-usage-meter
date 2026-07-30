import Foundation

public struct PersistedAppState: Codable, Equatable, Sendable {
    public var accounts: [SubscriptionAccount]
    public var snapshots: [UUID: UsageSnapshot]

    public init(
        accounts: [SubscriptionAccount],
        snapshots: [UUID: UsageSnapshot]
    ) {
        self.accounts = accounts
        self.snapshots = snapshots
    }

    public static let empty = PersistedAppState(accounts: [], snapshots: [:])
}
