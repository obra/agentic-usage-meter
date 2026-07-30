import Foundation

public struct ClaudeUsageDecoder: Sendable {
    public init() {}

    public func decode(
        _ data: Data,
        accountID: UUID,
        fetchedAt: Date
    ) throws -> UsageSnapshot {
        let payload: UsagePayload
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            payload = try decoder.decode(UsagePayload.self, from: data)
        } catch {
            throw ProviderClientError.unsupportedResponse
        }

        guard
            let shortWindow = normalizedWindow(
                payload.fiveHour,
                id: "five-hour",
                kind: .short,
                duration: 18_000
            ),
            let weeklyWindow = normalizedWindow(
                payload.sevenDay,
                id: "seven-day",
                kind: .weekly,
                duration: 604_800
            )
        else {
            throw ProviderClientError.unsupportedResponse
        }

        return UsageSnapshot(
            accountID: accountID,
            fetchedAt: fetchedAt,
            windows: [shortWindow, weeklyWindow]
        )
    }

    private func normalizedWindow(
        _ payload: WindowPayload,
        id: String,
        kind: UsageWindowKind,
        duration: TimeInterval
    ) -> UsageWindow? {
        guard
            payload.utilization.isFinite,
            (0 ... 100).contains(payload.utilization)
        else {
            return nil
        }

        return UsageWindow(
            id: id,
            kind: kind,
            duration: duration,
            resetAt: payload.resetsAt,
            consumedFraction: payload.utilization / 100
        )
    }
}

private struct UsagePayload: Decodable {
    let fiveHour: WindowPayload
    let sevenDay: WindowPayload

    private enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

private struct WindowPayload: Decodable {
    let utilization: Double
    let resetsAt: Date

    private enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}
