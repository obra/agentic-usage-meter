import Foundation
import Testing
@testable import UsageMeterCore

@Test
func tightestWindowUsesLowestRemainingCapacity() throws {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let personalID = UUID()
    let workID = UUID()
    let personal = UsageSnapshot(
        accountID: personalID,
        fetchedAt: now,
        windows: [
            try #require(
                UsageWindow(
                    id: "personal-weekly",
                    kind: .weekly,
                    duration: 604_800,
                    resetAt: now.addingTimeInterval(100),
                    consumedFraction: 0.45
                )
            )
        ]
    )
    let workWindow = try #require(
        UsageWindow(
            id: "work-short",
            kind: .short,
            duration: 18_000,
            resetAt: now.addingTimeInterval(200),
            consumedFraction: 0.81
        )
    )
    let work = UsageSnapshot(
        accountID: workID,
        fetchedAt: now,
        windows: [workWindow]
    )

    let tightest = UsageSummary.tightestWindow(in: [personal, work])

    #expect(tightest == TightestUsage(accountID: workID, window: workWindow))
}

@Test
func tightestWindowBreaksRemainingCapacityTiesByEarliestReset() throws {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let laterID = UUID()
    let earlierID = UUID()
    let later = try #require(
        UsageWindow(
            id: "later",
            kind: .weekly,
            duration: 604_800,
            resetAt: now.addingTimeInterval(500),
            consumedFraction: 0.75
        )
    )
    let earlier = try #require(
        UsageWindow(
            id: "earlier",
            kind: .short,
            duration: 18_000,
            resetAt: now.addingTimeInterval(100),
            consumedFraction: 0.75
        )
    )

    let result = UsageSummary.tightestWindow(
        in: [
            UsageSnapshot(accountID: laterID, fetchedAt: now, windows: [later]),
            UsageSnapshot(accountID: earlierID, fetchedAt: now, windows: [earlier])
        ]
    )

    #expect(result == TightestUsage(accountID: earlierID, window: earlier))
}

@Test
func tightestWindowReturnsNilWithoutWindows() {
    #expect(UsageSummary.tightestWindow(in: []) == nil)
}
