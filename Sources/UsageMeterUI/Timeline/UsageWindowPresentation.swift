import Foundation
import UsageMeterCore

public struct UsageWindowPresentation: Equatable, Sendable {
    public let provider: Provider
    public let providerText: String
    public let accountText: String?
    public let outerXFraction: Double
    public let outerWidthFraction: Double
    public let fillFraction: Double
    public let nowXFraction: Double
    public let remainingPercentageText: String
    public let relativeResetText: String
    public let exactResetText: String
    public let accessibilityValue: String

    public init(
        account: SubscriptionAccount,
        window: UsageWindow,
        now: Date,
        timeZone: TimeZone = .autoupdatingCurrent,
    ) {
        provider = account.provider
        providerText =
            ProviderCatalog.live.definition(
                for: account.provider,
            )?.displayName
            ?? account.provider.rawValue
        let trimmedAccountName = account.displayName.trimmingCharacters(
            in: .whitespacesAndNewlines,
        )
        accountText =
            trimmedAccountName.caseInsensitiveCompare(providerText)
                == .orderedSame
            ? nil
            : trimmedAccountName

        let axisDuration: TimeInterval =
            window.kind == .weekly ? 604_800 : 18000
        let layout = TimelineLayout(
            duration: axisDuration,
            now: now,
        )!
        outerXFraction = layout.xFraction(for: window)
        outerWidthFraction = layout.widthFraction(for: window)
        fillFraction = window.consumedFraction
        nowXFraction = 0.5

        let remainingPercent = Int(
            (window.remainingFraction * 100).rounded(),
        )
        remainingPercentageText = "\(remainingPercent)%"
        relativeResetText = Self.relativeResetText(
            from: now,
            to: window.resetAt,
        )

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE h:mm a"
        exactResetText = formatter.string(from: window.resetAt)

        let windowName =
            switch window.kind {
            case .short:
                "five-hour"
            case .weekly:
                "weekly"
            }
        accessibilityValue =
            "\(providerText), \(account.displayName), "
            + "\(windowName) window, \(remainingPercent) percent remaining, "
            + "resets \(exactResetText)"
    }

    private static func relativeResetText(
        from now: Date,
        to resetAt: Date,
    ) -> String {
        let interval = resetAt.timeIntervalSince(now)
        guard interval > 0 else {
            return "Now"
        }

        let totalMinutes = Int(interval) / 60
        if totalMinutes < 60 {
            return "\(totalMinutes)m"
        }

        let totalHours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if totalHours < 24 {
            return "\(totalHours)h \(minutes)m"
        }

        let days = totalHours / 24
        let hours = totalHours % 24
        return "\(days)d \(hours)h"
    }
}

public struct UsageTimelineRowPresentation:
    Equatable,
    Identifiable,
    Sendable
{
    public let account: SubscriptionAccount
    public let window: UsageWindow
    public let windowPresentation: UsageWindowPresentation

    public var id: String {
        "\(account.id.uuidString):\(window.id)"
    }
}

public struct UsageTimelineSectionPresentation:
    Equatable,
    Sendable
{
    public let kind: UsageWindowKind
    public let rows: [UsageTimelineRowPresentation]

    public init(
        kind: UsageWindowKind,
        accounts: [AccountViewState],
        now: Date,
        timeZone: TimeZone = .autoupdatingCurrent,
    ) {
        self.kind = kind
        rows =
            accounts
            .sorted(by: accountStateComesBefore)
            .flatMap { state in
                (state.snapshot?.windows ?? [])
                    .filter { $0.kind == kind }
                    .map { window in
                        UsageTimelineRowPresentation(
                            account: state.account,
                            window: window,
                            windowPresentation:
                                UsageWindowPresentation(
                                    account: state.account,
                                    window: window,
                                    now: now,
                                    timeZone: timeZone,
                                ),
                        )
                    }
            }
    }
}

public struct UsageTimelinePresentation: Equatable, Sendable {
    public let sections: [UsageTimelineSectionPresentation]

    public init(
        accounts: [AccountViewState],
        now: Date,
        timeZone: TimeZone = .autoupdatingCurrent,
    ) {
        sections = [UsageWindowKind.short, .weekly].compactMap { kind in
            let section = UsageTimelineSectionPresentation(
                kind: kind,
                accounts: accounts,
                now: now,
                timeZone: timeZone,
            )
            return section.rows.isEmpty ? nil : section
        }
    }
}

private func accountStateComesBefore(
    _ lhs: AccountViewState,
    _ rhs: AccountViewState,
) -> Bool {
    let lhsProvider = ProviderCatalog.live.sortIndex(
        for: lhs.account.provider,
    )
    let rhsProvider = ProviderCatalog.live.sortIndex(
        for: rhs.account.provider,
    )
    if lhsProvider != rhsProvider {
        return lhsProvider < rhsProvider
    }
    if lhs.account.displayOrder != rhs.account.displayOrder {
        return lhs.account.displayOrder < rhs.account.displayOrder
    }
    return lhs.id.uuidString < rhs.id.uuidString
}
