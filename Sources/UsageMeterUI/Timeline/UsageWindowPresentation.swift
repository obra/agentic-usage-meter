import Foundation
import UsageMeterCore

public struct UsageWindowPresentation: Equatable, Sendable {
    public let provider: Provider
    public let accountName: String
    public let outerXFraction: Double
    public let outerWidthFraction: Double
    public let fillFraction: Double
    public let nowXFraction: Double
    public let remainingText: String
    public let expiryText: String
    public let accessibilityValue: String

    public init(
        account: SubscriptionAccount,
        window: UsageWindow,
        now: Date,
        timeZone: TimeZone = .autoupdatingCurrent,
    ) {
        provider = account.provider
        accountName = account.displayName

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
        remainingText = "\(remainingPercent)% left"

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE h:mm a"
        expiryText = formatter.string(from: window.resetAt)

        let providerName = switch account.provider {
        case .claude:
            "Claude"
        case .codex:
            "Codex"
        case .kimi:
            "Kimi"
        }
        let windowName = switch window.kind {
        case .short:
            "five-hour"
        case .weekly:
            "weekly"
        }
        accessibilityValue =
            "\(providerName), \(account.displayName), "
                + "\(windowName) window, \(remainingPercent) percent remaining, "
                + "resets \(expiryText)"
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
        rows = accounts
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

private func accountStateComesBefore(
    _ lhs: AccountViewState,
    _ rhs: AccountViewState,
) -> Bool {
    let providerOrder = Dictionary(
        uniqueKeysWithValues: Provider.allCases.enumerated().map {
            ($0.element, $0.offset)
        },
    )
    let lhsProvider = providerOrder[lhs.account.provider] ?? .max
    let rhsProvider = providerOrder[rhs.account.provider] ?? .max
    if lhsProvider != rhsProvider {
        return lhsProvider < rhsProvider
    }
    if lhs.account.displayOrder != rhs.account.displayOrder {
        return lhs.account.displayOrder < rhs.account.displayOrder
    }
    return lhs.id.uuidString < rhs.id.uuidString
}
