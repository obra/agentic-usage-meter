import Foundation

public struct OpenCodeZenUsageDecoder:
    Sendable
{
    public init() {}

    public func decode(
        _ data: Data,
        accountID: UUID,
        fetchedAt: Date
    ) throws -> UsageSnapshot {
        let html =
            try OpenCodeDashboardHTML
            .normalized(data)
        guard
            let balanceInMicrocents =
                OpenCodeDashboardHTML.number(
                    named: "balance",
                    in: html
                ),
            let balance = UsageBalance(
                id: "opencode-zen-balance",
                label: "Zen balance",
                remainingAmount:
                    balanceInMicrocents
                    / 100_000_000,
                unit: "USD"
            )
        else {
            throw ProviderClientError
                .unsupportedResponse
        }

        let windows: [UsageWindow]
        if let monthlyLimit =
            OpenCodeDashboardHTML.number(
                named: "monthlyLimit",
                in: html
            ),
            monthlyLimit > 0,
            let cycle = monthCycle(
                containing: fetchedAt
            )
        {
            let reportedUsage =
                OpenCodeDashboardHTML.number(
                    named: "monthlyUsage",
                    in: html
                ) ?? 0
            let updatedAt =
                OpenCodeDashboardHTML.date(
                    named:
                        "timeMonthlyUsageUpdated",
                    in: html
                )
            let usageInMicrocents =
                updatedAt.map {
                    cycle.range.contains($0)
                } == false
                ? 0
                : max(0, reportedUsage)
            guard
                let monthly = UsageWindow(
                    id: "opencode-zen-monthly",
                    kind: .monthly,
                    duration:
                        cycle.end
                        .timeIntervalSince(
                            cycle.start
                        ),
                    resetAt: cycle.end,
                    consumedFraction: min(
                        usageInMicrocents
                            / 100_000_000
                            / monthlyLimit,
                        1
                    )
                )
            else {
                throw ProviderClientError
                    .unsupportedResponse
            }
            windows = [monthly]
        } else {
            windows = []
        }

        return UsageSnapshot(
            accountID: accountID,
            fetchedAt: fetchedAt,
            windows: windows,
            balances: [balance]
        )
    }

    private func monthCycle(
        containing date: Date
    ) -> (
        start: Date,
        end: Date,
        range: Range<Date>
    )? {
        var calendar = Calendar(
            identifier: .gregorian
        )
        calendar.timeZone =
            TimeZone(secondsFromGMT: 0)!
        guard
            let interval = calendar.dateInterval(
                of: .month,
                for: date
            )
        else {
            return nil
        }
        return (
            interval.start,
            interval.end,
            interval.start..<interval.end
        )
    }
}
