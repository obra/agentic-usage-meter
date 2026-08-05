import Foundation

public struct ZaiUsageDecoder: Sendable {
    public init() {}

    public func decode(
        _ data: Data,
        accountID: UUID,
        fetchedAt: Date
    ) throws -> UsageSnapshot {
        let response: ZaiQuotaResponse
        do {
            response = try JSONDecoder().decode(
                ZaiQuotaResponse.self,
                from: data
            )
        } catch {
            throw ProviderClientError.unsupportedResponse
        }

        if response.code == 401 || response.code == 403 {
            throw ProviderClientError.reauthenticationRequired
        }
        guard
            response.success != false,
            response.success == true || response.code == 200,
            let limits = response.data?.limits
        else {
            throw ProviderClientError.unsupportedResponse
        }

        let windows = try [
            makeWindow(
                limit: limits.first {
                    $0.isTokenLimit(unit: 3, number: 5)
                },
                id: "zai-short",
                kind: .short,
                duration: 18_000
            ),
            makeWindow(
                limit: limits.first {
                    $0.isTokenLimit(unit: 6, number: 1)
                },
                id: "zai-weekly",
                kind: .weekly,
                duration: 604_800
            ),
        ].compactMap(\.self)

        guard !windows.isEmpty else {
            throw ProviderClientError.unsupportedResponse
        }
        return UsageSnapshot(
            accountID: accountID,
            fetchedAt: fetchedAt,
            windows: windows
        )
    }

    private func makeWindow(
        limit: ZaiQuotaResponse.Limit?,
        id: String,
        kind: UsageWindowKind,
        duration: TimeInterval
    ) throws -> UsageWindow? {
        guard let limit else {
            return nil
        }
        guard
            let percentage = limit.percentage,
            percentage.isFinite,
            (0 ... 100).contains(percentage)
        else {
            throw ProviderClientError.unsupportedResponse
        }

        let resetAt: Date?
        if
            let nextResetTime = limit.nextResetTime,
            nextResetTime.isFinite,
            nextResetTime > 0
        {
            resetAt = Date(
                timeIntervalSince1970: nextResetTime / 1_000
            )
        } else {
            resetAt = nil
        }

        guard
            let window = UsageWindow(
                id: id,
                kind: kind,
                duration: duration,
                resetAt: resetAt,
                consumedFraction: percentage / 100
            )
        else {
            throw ProviderClientError.unsupportedResponse
        }
        return window
    }
}

private struct ZaiQuotaResponse: Decodable {
    let code: Int?
    let success: Bool?
    let data: QuotaData?

    struct QuotaData: Decodable {
        let limits: [Limit]?
    }

    struct Limit: Decodable {
        let type: String?
        let unit: Double?
        let number: Double?
        let percentage: Double?
        let nextResetTime: Double?

        func isTokenLimit(
            unit: Double,
            number: Double
        ) -> Bool {
            type == "TOKENS_LIMIT"
                && self.unit == unit
                && self.number == number
        }
    }
}
