import Foundation

public struct OpenCodeGoUsageDecoder:
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
        let candidates: [WindowCandidate] = [
            candidate(
                field: "rollingUsage",
                id: "opencode-go-rolling",
                kind: .short,
                duration: 5 * 60 * 60,
                html: html,
                fetchedAt: fetchedAt
            ),
            candidate(
                field: "weeklyUsage",
                id: "opencode-go-weekly",
                kind: .weekly,
                duration: 7 * 24 * 60 * 60,
                html: html,
                fetchedAt: fetchedAt
            ),
            candidate(
                field: "monthlyUsage",
                id: "opencode-go-monthly",
                kind: .monthly,
                duration: nil,
                html: html,
                fetchedAt: fetchedAt
            ),
        ].compactMap { $0 }

        let windows = candidates.compactMap {
            candidate -> UsageWindow? in
            let duration =
                candidate.duration
                ?? monthDuration(
                    endingAt:
                        candidate.resetAt
                )
            guard let duration else {
                return nil
            }
            return UsageWindow(
                id: candidate.id,
                kind: candidate.kind,
                duration: duration,
                resetAt: candidate.resetAt,
                consumedFraction:
                    candidate.usedPercent / 100
            )
        }
        guard
            windows.count == candidates.count,
            !windows.isEmpty
        else {
            throw ProviderClientError
                .unsupportedResponse
        }
        return UsageSnapshot(
            accountID: accountID,
            fetchedAt: fetchedAt,
            windows: windows
        )
    }

    private func candidate(
        field: String,
        id: String,
        kind: UsageWindowKind,
        duration: TimeInterval?,
        html: String,
        fetchedAt: Date
    ) -> WindowCandidate? {
        guard
            let body =
                OpenCodeDashboardHTML.objectBody(
                    named: field,
                    in: html
                ),
            let usedPercent =
                OpenCodeDashboardHTML.number(
                    named: "usagePercent",
                    in: body
                ),
            (0...100).contains(usedPercent),
            let resetSeconds =
                OpenCodeDashboardHTML.number(
                    named: "resetInSec",
                    in: body
                ),
            resetSeconds.isFinite,
            resetSeconds >= 0
        else {
            return nil
        }
        return WindowCandidate(
            id: id,
            kind: kind,
            duration: duration,
            resetAt:
                fetchedAt.addingTimeInterval(
                    resetSeconds.rounded()
                ),
            usedPercent: usedPercent
        )
    }

    private func monthDuration(
        endingAt resetAt: Date
    ) -> TimeInterval? {
        var calendar = Calendar(
            identifier: .gregorian
        )
        calendar.timeZone =
            TimeZone(secondsFromGMT: 0)!
        guard
            let startAt = calendar.date(
                byAdding: .month,
                value: -1,
                to: resetAt
            )
        else {
            return nil
        }
        let duration =
            resetAt.timeIntervalSince(startAt)
        return duration > 0 ? duration : nil
    }
}

private struct WindowCandidate {
    let id: String
    let kind: UsageWindowKind
    let duration: TimeInterval?
    let resetAt: Date
    let usedPercent: Double
}
