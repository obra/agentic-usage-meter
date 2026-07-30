import Foundation

public struct PersistedAppState: Codable, Equatable, Sendable {
    public var accounts: [SubscriptionAccount]
    public var snapshots: [UUID: UsageSnapshot]
    public var refreshStates: [UUID: AccountRefreshState]

    public init(
        accounts: [SubscriptionAccount],
        snapshots: [UUID: UsageSnapshot],
        refreshStates: [UUID: AccountRefreshState] = [:]
    ) {
        self.accounts = accounts
        self.snapshots = snapshots
        self.refreshStates = refreshStates
    }

    public static let empty = PersistedAppState(
        accounts: [],
        snapshots: [:],
        refreshStates: [:]
    )
}
