import Foundation

public struct SuperGrokUsageDecoder:
    Sendable
{
    public init() {}

    public func decode(
        _ data: Data,
        accountID: UUID,
        fetchedAt: Date
    ) throws -> UsageSnapshot {
        let response: BillingResponse
        do {
            response = try JSONDecoder()
                .decode(
                    BillingResponse.self,
                    from: data
                )
        } catch {
            throw ProviderClientError
                .unsupportedResponse
        }

        guard
            let config = response.config,
            let usedPercent =
                config.creditUsagePercent,
            usedPercent.isFinite,
            (0 ... 100).contains(
                usedPercent
            ),
            let period = config.currentPeriod,
            period.type
                == "USAGE_PERIOD_TYPE_WEEKLY",
            let resetAt = parseDate(period.end),
            let reportedStartAt =
                parseDate(period.start),
            resetAt > reportedStartAt,
            let weekly = UsageWindow(
                id: "supergrok-weekly",
                kind: .weekly,
                duration:
                    resetAt.timeIntervalSince(
                        reportedStartAt
                    ),
                resetAt: resetAt,
                consumedFraction:
                    usedPercent / 100,
                reportedStartAt:
                    reportedStartAt
            )
        else {
            throw ProviderClientError
                .unsupportedResponse
        }

        return UsageSnapshot(
            accountID: accountID,
            fetchedAt: fetchedAt,
            windows: [weekly],
            balances: try balances(
                from: config
            )
        )
    }

    private func balances(
        from config: BillingConfig
    ) throws -> [UsageBalance] {
        guard
            let prepaidBalance =
                config.prepaidBalance
        else {
            return []
        }
        guard prepaidBalance.val >= 0 else {
            throw ProviderClientError
                .unsupportedResponse
        }
        guard
            let cents = Decimal(
                string: String(
                    prepaidBalance.val
                ),
                locale: Locale(
                    identifier: "en_US_POSIX"
                )
            ),
            let balance = UsageBalance(
                id: "supergrok-prepaid",
                label: "Extra usage",
                value: .available(
                    amount: cents / 100,
                    unit: "USD"
                )
            )
        else {
            throw ProviderClientError
                .unsupportedResponse
        }
        return [balance]
    }

    private func parseDate(
        _ value: String?
    ) -> Date? {
        guard let value else {
            return nil
        }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        if let date = fractional.date(
            from: value
        ) {
            return date
        }

        let internet = ISO8601DateFormatter()
        internet.formatOptions = [
            .withInternetDateTime
        ]
        return internet.date(from: value)
    }
}

private struct BillingResponse:
    Decodable
{
    let config: BillingConfig?
}

private struct BillingConfig:
    Decodable
{
    let creditUsagePercent: Double?
    let currentPeriod: UsagePeriod?
    let prepaidBalance: Cent?
}

private struct UsagePeriod:
    Decodable
{
    let type: String?
    let start: String?
    let end: String?
}

private struct Cent:
    Decodable
{
    let val: Int64

    private enum CodingKeys:
        String,
        CodingKey
    {
        case val
    }

    init(from decoder: Decoder) throws {
        let container = try decoder
            .container(
                keyedBy: CodingKeys.self
            )
        val = try container
            .decodeIfPresent(
                Int64.self,
                forKey: .val
            ) ?? 0
    }
}
