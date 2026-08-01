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
    public var collapsedUsageSections: Set<UsageSectionID>

    public init(
        accounts: [SubscriptionAccount],
        snapshots: [UUID: UsageSnapshot],
        refreshStates: [UUID: AccountRefreshState] = [:],
        isFloatingWidgetVisible: Bool = false,
        floatingWidgetPlacement: FloatingWidgetPlacement? = nil,
        collapsedUsageSections: Set<UsageSectionID> = [],
    ) {
        self.accounts = accounts
        self.snapshots = snapshots
        self.refreshStates = refreshStates
        self.isFloatingWidgetVisible = isFloatingWidgetVisible
        self.floatingWidgetPlacement = floatingWidgetPlacement
        self.collapsedUsageSections = collapsedUsageSections
    }

    public static let empty = PersistedAppState(
        accounts: [],
        snapshots: [:],
        refreshStates: [:],
        isFloatingWidgetVisible: false,
        floatingWidgetPlacement: nil,
        collapsedUsageSections: [],
    )

    private enum CodingKeys: String, CodingKey {
        case accounts
        case snapshots
        case refreshStates
        case isFloatingWidgetVisible
        case floatingWidgetPlacement
        case collapsedUsageSections
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self,
        )
        accounts = try container.decode(
            [SubscriptionAccount].self,
            forKey: .accounts,
        )
        snapshots = try container.decode(
            [UUID: UsageSnapshot].self,
            forKey: .snapshots,
        )
        refreshStates = try container.decode(
            [UUID: AccountRefreshState].self,
            forKey: .refreshStates,
        )
        isFloatingWidgetVisible = try container.decode(
            Bool.self,
            forKey: .isFloatingWidgetVisible,
        )
        floatingWidgetPlacement = try container.decodeIfPresent(
            FloatingWidgetPlacement.self,
            forKey: .floatingWidgetPlacement,
        )
        collapsedUsageSections = try container.decodeIfPresent(
            Set<UsageSectionID>.self,
            forKey: .collapsedUsageSections,
        ) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(
            keyedBy: CodingKeys.self,
        )
        try container.encode(accounts, forKey: .accounts)
        try container.encode(snapshots, forKey: .snapshots)
        try container.encode(
            refreshStates,
            forKey: .refreshStates,
        )
        try container.encode(
            isFloatingWidgetVisible,
            forKey: .isFloatingWidgetVisible,
        )
        try container.encodeIfPresent(
            floatingWidgetPlacement,
            forKey: .floatingWidgetPlacement,
        )
        try container.encode(
            collapsedUsageSections,
            forKey: .collapsedUsageSections,
        )
    }
}
