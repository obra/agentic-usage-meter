import Foundation
import Testing
import UsageMeterCore

@testable import UsageMeterUI

@Suite
struct TimelinePresentationTests {
  @Test
  func inactiveWindowRendersEmptyFromNowWithoutInventingAReset() throws {
    let account = SubscriptionAccount(
      provider: .factory,
      displayName: "Factory",
      displayOrder: 0,
    )
    let window = try #require(
      UsageWindow(
        id: "factory-standard-five-hour",
        kind: .short,
        duration: 18_000,
        resetAt: nil,
        consumedFraction: 0,
        label: "Standard",
      ),
    )

    let presentation = UsageWindowPresentation(
      account: account,
      window: window,
      now: Date(timeIntervalSince1970: 2_000_000_000),
      timeZone: TimeZone(secondsFromGMT: 0)!,
    )

    #expect(presentation.outerXFraction == 0.5)
    #expect(presentation.outerWidthFraction == 0.5)
    #expect(presentation.fillFraction == 0)
    #expect(presentation.remainingPercentageText == "100%")
    #expect(presentation.relativeResetText == "5h 0m")
    #expect(presentation.exactResetText == nil)
    #expect(presentation.helpText == "No provider reset reported")
    #expect(
      presentation.accessibilityValue.contains(
        "displayed empty window starts now",
      ),
    )
  }

  @Test
  func weeklyRowPresentsAlignedIdentityAndResetValues() throws {
    let account = SubscriptionAccount(
      provider: .codex,
      displayName: "Work",
      authenticatedIdentity: "work@example.com",
      displayOrder: 0,
    )
    let window = try #require(
      UsageWindow(
        id: "weekly",
        kind: .weekly,
        duration: 604_800,
        resetAt: Date(timeIntervalSince1970: 2_000_472_000),
        consumedFraction: 0.66,
      ),
    )

    let presentation = UsageWindowPresentation(
      account: account,
      window: window,
      now: Date(timeIntervalSince1970: 2_000_000_000),
      timeZone: TimeZone(secondsFromGMT: 0)!,
    )

    #expect(presentation.outerWidthFraction == 0.5)
    #expect(presentation.fillFraction == 0.66)
    #expect(presentation.nowXFraction == 0.5)
    #expect(presentation.providerText == "Codex")
    #expect(presentation.accountText == "Work")
    #expect(presentation.remainingPercentageText == "34%")
    #expect(presentation.relativeResetText == "5d 11h")
    #expect(presentation.exactResetText == "Mon 2:40 PM")
    #expect(
      presentation.accessibilityValue
        == "Codex, Work, weekly window, 34 percent remaining, resets Mon 2:40 PM",
    )
  }

  @Test
  func fiveHourRowUsesSharedTenHourAxis() throws {
    let account = SubscriptionAccount(
      provider: .kimi,
      displayName: "Personal",
      displayOrder: 0,
    )
    let window = try #require(
      UsageWindow(
        id: "short",
        kind: .short,
        duration: 18000,
        resetAt: Date(timeIntervalSince1970: 2_000_009_000),
        consumedFraction: 0.25,
      ),
    )

    let presentation = UsageWindowPresentation(
      account: account,
      window: window,
      now: Date(timeIntervalSince1970: 2_000_000_000),
      timeZone: TimeZone(secondsFromGMT: 0)!,
    )

    #expect(presentation.outerXFraction == 0.25)
    #expect(presentation.outerWidthFraction == 0.5)
    #expect(presentation.fillFraction == 0.25)
    #expect(presentation.remainingPercentageText == "75%")
    #expect(presentation.relativeResetText == "2h 30m")
  }

  @Test
  func resetUnderOneHourUsesMinutes() throws {
    let account = SubscriptionAccount(
      provider: .claude,
      displayName: "Personal",
      displayOrder: 0,
    )
    let window = try #require(
      UsageWindow(
        id: "short",
        kind: .short,
        duration: 18000,
        resetAt: Date(timeIntervalSince1970: 2_000_003_540),
        consumedFraction: 0.25,
      ),
    )

    let presentation = UsageWindowPresentation(
      account: account,
      window: window,
      now: Date(timeIntervalSince1970: 2_000_000_000),
      timeZone: TimeZone(secondsFromGMT: 0)!,
    )

    #expect(presentation.relativeResetText == "59m")
  }

  @Test
  func expiredWindowResetsNow() throws {
    let account = SubscriptionAccount(
      provider: .claude,
      displayName: "Personal",
      displayOrder: 0,
    )
    let window = try #require(
      UsageWindow(
        id: "short",
        kind: .short,
        duration: 18000,
        resetAt: Date(timeIntervalSince1970: 1_999_999_999),
        consumedFraction: 0.25,
      ),
    )

    let presentation = UsageWindowPresentation(
      account: account,
      window: window,
      now: Date(timeIntervalSince1970: 2_000_000_000),
      timeZone: TimeZone(secondsFromGMT: 0)!,
    )

    #expect(presentation.relativeResetText == "Now")
  }

  @Test
  func repeatedProviderAndAccountNameKeepsTheAccountColumn() throws {
    let account = SubscriptionAccount(
      provider: .kimi,
      displayName: "  kImI ",
      displayOrder: 0,
    )
    let window = try #require(
      UsageWindow(
        id: "weekly",
        kind: .weekly,
        duration: 604_800,
        resetAt: Date(timeIntervalSince1970: 2_000_472_000),
        consumedFraction: 0.27,
      ),
    )

    let presentation = UsageWindowPresentation(
      account: account,
      window: window,
      now: Date(timeIntervalSince1970: 2_000_000_000),
      timeZone: TimeZone(secondsFromGMT: 0)!,
    )

    #expect(presentation.providerText == "Kimi")
    #expect(presentation.accountText == "kImI")
    #expect(presentation.remainingPercentageText == "73%")
  }

  @Test
  func sectionRowsStayInProviderAndAccountOrder() throws {
    let kimi = SubscriptionAccount(
      provider: .kimi,
      displayName: "Kimi",
      displayOrder: 0,
    )
    let codex = SubscriptionAccount(
      provider: .codex,
      displayName: "Codex",
      displayOrder: 0,
    )
    let claude = SubscriptionAccount(
      provider: .claude,
      displayName: "Claude",
      displayOrder: 0,
    )
    let resetAt = Date(timeIntervalSince1970: 2_000_472_000)
    let weekly = try #require(
      UsageWindow(
        id: "weekly",
        kind: .weekly,
        duration: 604_800,
        resetAt: resetAt,
        consumedFraction: 0.5,
      ),
    )
    let states = [
      AccountViewState(
        account: kimi,
        snapshot: UsageSnapshot(
          accountID: kimi.id,
          fetchedAt: resetAt,
          windows: [weekly],
        ),
      ),
      AccountViewState(account: codex, snapshot: nil),
      AccountViewState(
        account: claude,
        snapshot: UsageSnapshot(
          accountID: claude.id,
          fetchedAt: resetAt,
          windows: [weekly],
        ),
      ),
    ]

    let section = UsageTimelineSectionPresentation(
      kind: .weekly,
      accounts: states,
      now: Date(timeIntervalSince1970: 2_000_000_000),
      timeZone: TimeZone(secondsFromGMT: 0)!,
    )

    #expect(
      section.rows.map(\.account.provider)
        == [.claude, .kimi],
    )
    #expect(
      section.rows.map(\.account.displayName)
        == ["Claude", "Kimi"],
    )
  }

  @Test
  func timelineOmitsWindowKindsThatNoAccountOffers() throws {
    let account = SubscriptionAccount(
      provider: .codex,
      displayName: "Work",
      displayOrder: 0,
    )
    let weekly = try #require(
      UsageWindow(
        id: "weekly",
        kind: .weekly,
        duration: 604_800,
        resetAt: Date(timeIntervalSince1970: 2_000_472_000),
        consumedFraction: 0.5,
      ),
    )
    let state = AccountViewState(
      account: account,
      snapshot: UsageSnapshot(
        accountID: account.id,
        fetchedAt: Date(timeIntervalSince1970: 2_000_000_000),
        windows: [weekly],
      ),
    )

    let timeline = UsageTimelinePresentation(
      accounts: [state],
      now: Date(timeIntervalSince1970: 2_000_000_000),
      timeZone: TimeZone(secondsFromGMT: 0)!,
    )

    #expect(timeline.sections.map(\.kind) == [.weekly])
    #expect(timeline.sections.first?.rows.count == 1)
  }

  @Test
  func timelineOrdersEveryOfferedWindowKindAndOmitsAbsentKinds() throws {
    let account = SubscriptionAccount(
      provider: .minimax,
      displayName: "Work",
      displayOrder: 0,
    )
    let resetAt = Date(timeIntervalSince1970: 2_000_472_000)
    let windows = try [
      UsageWindow(
        id: "monthly",
        kind: .monthly,
        duration: 2_678_400,
        resetAt: resetAt,
        consumedFraction: 0.1,
      ),
      UsageWindow(
        id: "short",
        kind: .short,
        duration: 18000,
        resetAt: resetAt,
        consumedFraction: 0.2,
      ),
      UsageWindow(
        id: "custom",
        kind: .custom,
        duration: 86400,
        resetAt: resetAt,
        consumedFraction: 0.3,
        label: "Burst",
      ),
      UsageWindow(
        id: "daily",
        kind: .daily,
        duration: 86400,
        resetAt: resetAt,
        consumedFraction: 0.4,
      ),
      UsageWindow(
        id: "weekly",
        kind: .weekly,
        duration: 604_800,
        resetAt: resetAt,
        consumedFraction: 0.5,
      ),
    ].map { try #require($0) }
    let state = AccountViewState(
      account: account,
      snapshot: UsageSnapshot(
        accountID: account.id,
        fetchedAt: resetAt,
        windows: windows,
      ),
    )

    let timeline = UsageTimelinePresentation(
      accounts: [state],
      now: Date(timeIntervalSince1970: 2_000_000_000),
    )

    #expect(
      timeline.sections.map(\.kind)
        == [.short, .daily, .weekly, .monthly, .custom],
    )
  }

  @Test
  func timelinePresentsBalancesAfterTimedSections() throws {
    let account = SubscriptionAccount(
      provider: .minimax,
      displayName: "Work",
      displayOrder: 0,
    )
    let credits = try #require(
      UsageBalance(
        id: "credits",
        label: "AI credits",
        remainingAmount: 125.5,
        unit: "credits",
        cycleEndsAt: Date(timeIntervalSince1970: 2_000_472_000),
      ),
    )
    let state = AccountViewState(
      account: account,
      snapshot: UsageSnapshot(
        accountID: account.id,
        fetchedAt: Date(timeIntervalSince1970: 2_000_000_000),
        windows: [],
        balances: [credits],
      ),
    )

    let timeline = UsageTimelinePresentation(
      accounts: [state],
      now: Date(timeIntervalSince1970: 2_000_000_000),
      timeZone: TimeZone(secondsFromGMT: 0)!,
    )

    #expect(timeline.sections.isEmpty)
    #expect(timeline.balanceRows.count == 1)
    #expect(timeline.balanceRows[0].valueText == "125.5 credits")
    #expect(timeline.balanceRows[0].cycleEndText == "Mon 2:40 PM")
  }

  @Test
  func extraCreditRowsFormatEveryExplicitState() throws {
    let account = SubscriptionAccount(
      provider: .claude,
      displayName: "Prime",
      displayOrder: 0,
    )
    let values: [(UsageBalanceValue, String)] = [
      (
        .available(
          amount: Decimal(string: "38.42")!,
          unit: "USD",
        ),
        "$38.42"
      ),
      (
        .available(
          amount: Decimal(string: "1240.5")!,
          unit: "credits",
        ),
        "1,240.5 credits"
      ),
      (.unlimited, "Unlimited"),
      (.disabled, "Off"),
    ]

    for (index, item) in values.enumerated() {
      let balance = try #require(
        UsageBalance(
          id: "credits-\(index)",
          label: "Usage credits",
          value: item.0,
        ),
      )
      let row = UsageBalanceRowPresentation(
        account: account,
        balance: balance,
        timeZone: TimeZone(secondsFromGMT: 0)!,
      )

      #expect(row.labelText == "Usage credits")
      #expect(row.valueText == item.1)
    }
  }
}
