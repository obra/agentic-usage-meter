import Foundation

public struct TightestUsage: Equatable, Sendable {
    public let accountID: UUID
    public let window: UsageWindow

    public init(accountID: UUID, window: UsageWindow) {
        self.accountID = accountID
        self.window = window
    }
}

public enum UsageSummary {
    public static func tightestWindow(in snapshots: [UsageSnapshot]) -> TightestUsage? {
        snapshots
            .flatMap { snapshot in
                snapshot.windows.map {
                    TightestUsage(accountID: snapshot.accountID, window: $0)
                }
            }
            .min { lhs, rhs in
                if lhs.window.remainingFraction == rhs.window.remainingFraction {
                    return lhs.window.resetAt < rhs.window.resetAt
                }
                return lhs.window.remainingFraction < rhs.window.remainingFraction
            }
    }
}
