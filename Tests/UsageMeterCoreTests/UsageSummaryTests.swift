import Foundation
import Testing

@testable import UsageMeterCore

@Test
func tightestWindowUsesLowestRemainingCapacity() throws {
  let now = Date(timeIntervalSince1970: 2_000_000_000)
  let personalID = UUID()
  let workID = UUID()
  let personal = try UsageSnapshot(
    accountID: personalID,
    fetchedAt: now,
    windows: [
      #require(
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
      duration: 18000,
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
      duration: 18000,
      resetAt: now.addingTimeInterval(100),
      consumedFraction: 0.75
    )
  )

  let result = UsageSummary.tightestWindow(
    in: [
      UsageSnapshot(accountID: laterID, fetchedAt: now, windows: [later]),
      UsageSnapshot(accountID: earlierID, fetchedAt: now, windows: [earlier]),
    ]
  )

  #expect(result == TightestUsage(accountID: earlierID, window: earlier))
}

@Test
func concreteResetWinsTieWithInactiveResetlessWindow() throws {
  let now = Date(timeIntervalSince1970: 2_000_000_000)
  let resetless = try #require(
    UsageWindow(
      id: "inactive",
      kind: .short,
      duration: 18_000,
      resetAt: nil,
      consumedFraction: 0,
    ),
  )
  let concrete = try #require(
    UsageWindow(
      id: "active",
      kind: .weekly,
      duration: 604_800,
      resetAt: now.addingTimeInterval(604_800),
      consumedFraction: 0,
    ),
  )
  let concreteAccountID = UUID()

  let result = UsageSummary.tightestWindow(
    in: [
      UsageSnapshot(
        accountID: UUID(),
        fetchedAt: now,
        windows: [resetless],
      ),
      UsageSnapshot(
        accountID: concreteAccountID,
        fetchedAt: now,
        windows: [concrete],
      ),
    ],
  )

  #expect(
    result
      == TightestUsage(
        accountID: concreteAccountID,
        window: concrete,
      ),
  )
}

@Test
func tightestWindowReturnsNilWithoutWindows() {
  #expect(UsageSummary.tightestWindow(in: []) == nil)
}

@Test
func balancesDoNotParticipateInTightestWindowSelection() throws {
  let now = Date(timeIntervalSince1970: 2_000_000_000)
  let accountID = UUID()
  let weekly = try #require(
    UsageWindow(
      id: "weekly",
      kind: .weekly,
      duration: 604_800,
      resetAt: now.addingTimeInterval(86400),
      consumedFraction: 0.4,
    ),
  )
  let credits = try #require(
    UsageBalance(
      id: "credits",
      label: "AI credits",
      remainingAmount: 0,
      unit: "credits",
    ),
  )
  let snapshot = UsageSnapshot(
    accountID: accountID,
    fetchedAt: now,
    windows: [weekly],
    balances: [credits],
  )

  #expect(
    UsageSummary.tightestWindow(in: [snapshot])
      == TightestUsage(accountID: accountID, window: weekly),
  )
}

@Test
func inactiveScopedWindowParticipatesInTightestWindowSelection() throws {
  let now = Date(timeIntervalSince1970: 2_000_000_000)
  let accountID = UUID()
  let legacy = try #require(
    UsageWindow(
      id: "seven-day",
      kind: .weekly,
      duration: 604_800,
      resetAt: now.addingTimeInterval(604_800),
      consumedFraction: 0.67,
    ),
  )
  let scoped = try #require(
    UsageWindow(
      id: "claude-weekly-scoped-6e616d653a4661626c65",
      kind: .weekly,
      duration: 604_800,
      resetAt: now.addingTimeInterval(604_800),
      consumedFraction: 1,
      label: "Fable",
    ),
  )

  #expect(
    UsageSummary.tightestWindow(
      in: [
        UsageSnapshot(
          accountID: accountID,
          fetchedAt: now,
          windows: [legacy, scoped],
        )
      ]
    ) == TightestUsage(accountID: accountID, window: scoped),
  )
}
