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
        let solidCandidates =
            definitions.compactMap {
                definition in
                candidate(
                    field: definition.field,
                    id: definition.id,
                    kind: definition.kind,
                    duration:
                        definition.duration,
                    html: html,
                    fetchedAt: fetchedAt
                )
            }
        let candidates =
            solidCandidates.isEmpty
            ? dataSlotCandidates(
                in: html,
                fetchedAt: fetchedAt
            )
            : solidCandidates

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
        if
            candidates.isEmpty,
            requiresSubscription(in: html)
        {
            throw ProviderClientError
                .subscriptionRequired
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

    private func requiresSubscription(
        in html: String
    ) -> Bool {
        html.range(
            of:
                #"["']?subscriptionPlan["']?\s*:\s*null"#,
            options: [
                .regularExpression,
                .caseInsensitive,
            ]
        ) != nil
            && html.range(
                of:
                    #"data-slot\s*=\s*["']subscribe-button["']"#,
                options: [
                    .regularExpression,
                    .caseInsensitive,
                ]
            ) != nil
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

    private func dataSlotCandidates(
        in html: String,
        fetchedAt: Date
    ) -> [WindowCandidate] {
        dataSlotUsageItems(in: html)
            .compactMap { item in
                guard
                    let label = dataSlotValue(
                        named: "usage-label",
                        in: item
                    )?.lowercased(),
                    let definition =
                        definitions.first(
                            where: {
                                label.contains(
                                    $0.label
                                )
                            }
                        ),
                    let value = dataSlotValue(
                        named: "usage-value",
                        in: item
                    ),
                    let usedPercent = firstNumber(
                        in: value
                    ),
                    (0...100).contains(
                        usedPercent
                    ),
                    let resetSeconds =
                        dataSlotResetSeconds(
                            in: item
                        )
                else {
                    return nil
                }
                return WindowCandidate(
                    id: definition.id,
                    kind: definition.kind,
                    duration:
                        definition.duration,
                    resetAt:
                        fetchedAt
                        .addingTimeInterval(
                            resetSeconds
                        ),
                    usedPercent: usedPercent
                )
            }
    }

    private var definitions: [WindowDefinition] {
        [
            WindowDefinition(
                field: "rollingUsage",
                label: "rolling",
                id: "opencode-go-rolling",
                kind: .short,
                duration: 5 * 60 * 60
            ),
            WindowDefinition(
                field: "weeklyUsage",
                label: "weekly",
                id: "opencode-go-weekly",
                kind: .weekly,
                duration: 7 * 24 * 60 * 60
            ),
            WindowDefinition(
                field: "monthlyUsage",
                label: "monthly",
                id: "opencode-go-monthly",
                kind: .monthly,
                duration: nil
            ),
        ]
    }

    private func dataSlotUsageItems(
        in html: String
    ) -> [String] {
        guard
            let expression = try? NSRegularExpression(
                pattern:
                    #"data-slot\s*=\s*["']usage-item["']"#,
                options: [.caseInsensitive]
            )
        else {
            return []
        }
        let matches = expression.matches(
            in: html,
            range: NSRange(
                html.startIndex...,
                in: html
            )
        )
        return matches.enumerated().compactMap {
            index,
            match in
            guard
                let start = Range(
                    match.range,
                    in: html
                )?.lowerBound
            else {
                return nil
            }
            let end: String.Index
            if index + 1 < matches.count,
                let next = Range(
                    matches[index + 1].range,
                    in: html
                )
            {
                end = next.lowerBound
            } else {
                end = html.endIndex
            }
            return String(html[start..<end])
        }
    }

    private func dataSlotValue(
        named slotName: String,
        in html: String
    ) -> String? {
        let escaped =
            NSRegularExpression
            .escapedPattern(for: slotName)
        let pattern =
            #"<[^>]*data-slot\s*=\s*["']\#(escaped)["'][^>]*>(?<value>[\s\S]*?)</[^>]+>"#
        guard
            let expression = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            ),
            let match = expression.firstMatch(
                in: html,
                range: NSRange(
                    html.startIndex...,
                    in: html
                )
            ),
            let range = Range(
                match.range(
                    withName: "value"
                ),
                in: html
            )
        else {
            return nil
        }
        return String(html[range])
            .replacingOccurrences(
                of: #"<!--[\s\S]*?-->"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"<[^>]+>"#,
                with: "",
                options: .regularExpression
            )
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func firstNumber(
        in text: String
    ) -> Double? {
        guard
            let range = text.range(
                of: #"-?\d+(?:\.\d+)?"#,
                options: .regularExpression
            )
        else {
            return nil
        }
        return Double(text[range])
    }

    private func dataSlotResetSeconds(
        in item: String
    ) -> TimeInterval? {
        if dataSlotValue(
            named: "reset-now",
            in: item
        ) != nil {
            return 0
        }
        guard
            let reset = dataSlotValue(
                named: "reset-time",
                in: item
            )
        else {
            return nil
        }
        return durationSeconds(in: reset)
    }

    private func durationSeconds(
        in text: String
    ) -> TimeInterval? {
        let pattern =
            #"(\d+(?:\.\d+)?)\s*(day|hour|minute|second)s?"#
        guard
            let expression = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            )
        else {
            return nil
        }
        let matches = expression.matches(
            in: text,
            range: NSRange(
                text.startIndex...,
                in: text
            )
        )
        guard !matches.isEmpty else {
            return nil
        }
        return matches.reduce(0) {
            result,
            match in
            guard
                let valueRange = Range(
                    match.range(at: 1),
                    in: text
                ),
                let unitRange = Range(
                    match.range(at: 2),
                    in: text
                ),
                let value = Double(
                    text[valueRange]
                )
            else {
                return result
            }
            let multiplier: TimeInterval =
                switch text[unitRange]
                    .lowercased()
                {
                case "day": 24 * 60 * 60
                case "hour": 60 * 60
                case "minute": 60
                default: 1
                }
            return result
                + value * multiplier
        }
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

private struct WindowDefinition {
    let field: String
    let label: String
    let id: String
    let kind: UsageWindowKind
    let duration: TimeInterval?
}
