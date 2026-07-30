import Foundation
import Testing
import UsageMeterCore
@testable import UsageMeterUI

@Suite
struct TimelinePresentationTests {
    @Test
    func weeklyRowContainsApprovedGeometryAndPills() throws {
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
        #expect(presentation.remainingText == "34% left")
        #expect(presentation.expiryText == "Mon 2:40 PM")
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
        #expect(presentation.remainingText == "75% left")
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
}
