import Foundation

public struct MiMoUsageDecoder: Sendable {
    public init() {}

    public func decode(
        _ data: Data,
        accountID: UUID,
        fetchedAt: Date
    ) throws -> UsageSnapshot {
        let response: MiMoUsageResponse
        do {
            response = try JSONDecoder().decode(
                MiMoUsageResponse.self,
                from: data
            )
        } catch {
            throw ProviderClientError.unsupportedResponse
        }

        if response.code == 401 || response.code == 403 {
            throw ProviderClientError.reauthenticationRequired
        }
        guard
            response.code == 0,
            let bundle = response.data?.monthUsage?.items?
                .first(where: {
                    $0.name == "month_total_token"
                }),
            let limit = bundle.limit,
            limit.isFinite,
            limit > 0,
            let used = bundle.used,
            used.isFinite,
            used >= 0
        else {
            throw ProviderClientError.unsupportedResponse
        }

        // The plan renews monthly but the response carries no reset
        // timestamp, so the bundle is presented as a remaining balance
        // rather than a timed window with an invented reset.
        let remaining = max(limit - used, 0)
        guard
            let balance = UsageBalance(
                id: "mimo-monthly-tokens",
                label: "Monthly tokens",
                remainingAmount: remaining,
                unit: "tokens"
            )
        else {
            throw ProviderClientError.unsupportedResponse
        }

        return UsageSnapshot(
            accountID: accountID,
            fetchedAt: fetchedAt,
            windows: [],
            balances: [balance]
        )
    }
}

private struct MiMoUsageResponse: Decodable {
    let code: Int?
    let data: UsageData?

    struct UsageData: Decodable {
        let monthUsage: MonthUsage?
    }

    struct MonthUsage: Decodable {
        let items: [Item]?
    }

    struct Item: Decodable {
        let name: String?
        let used: Double?
        let limit: Double?
    }
}
