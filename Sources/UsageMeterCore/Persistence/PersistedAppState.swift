import Foundation

public struct FloatingWidgetPlacement:
    Codable,
    Equatable,
    Sendable
{
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(
        x: Double,
        y: Double,
        width: Double,
        height: Double,
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct PersistedAppState: Codable, Equatable, Sendable {
    public var accounts: [SubscriptionAccount]
    public var snapshots: [UUID: UsageSnapshot]
    public var refreshStates: [UUID: AccountRefreshState]
    public var isFloatingWidgetVisible: Bool
    public var floatingWidgetPlacement: FloatingWidgetPlacement?

    public init(
        accounts: [SubscriptionAccount],
        snapshots: [UUID: UsageSnapshot],
        refreshStates: [UUID: AccountRefreshState] = [:],
        isFloatingWidgetVisible: Bool = false,
        floatingWidgetPlacement: FloatingWidgetPlacement? = nil,
    ) {
        self.accounts = accounts
        self.snapshots = snapshots
        self.refreshStates = refreshStates
        self.isFloatingWidgetVisible = isFloatingWidgetVisible
        self.floatingWidgetPlacement = floatingWidgetPlacement
    }

    public static let empty = PersistedAppState(
        accounts: [],
        snapshots: [:],
        refreshStates: [:],
        isFloatingWidgetVisible: false,
        floatingWidgetPlacement: nil,
    )
}
