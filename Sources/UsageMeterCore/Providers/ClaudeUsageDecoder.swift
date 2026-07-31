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
        let balances = try normalizedBalances(from: payload)

        return UsageSnapshot(
            accountID: accountID,
            fetchedAt: fetchedAt,
            windows: [shortWindow, weeklyWindow],
            balances: balances,
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

    private func normalizedBalances(
        from payload: UsagePayload,
    ) throws -> [UsageBalance] {
        if payload.extraUsage?.isEnabled == false
            || payload.extraUsage?.userDisabled == true
            || payload.spend?.enabled == false
        {
            guard
                let disabled = UsageBalance(
                    id: "claude-usage-credits",
                    label: "Usage credits",
                    value: .disabled,
                )
            else {
                throw ProviderClientError.unsupportedResponse
            }
            return [disabled]
        }

        guard let money = payload.spend?.balance else {
            return []
        }
        let currency = money.currency.trimmingCharacters(
            in: .whitespacesAndNewlines,
        )
        guard
            money.amountMinor >= 0,
            (0 ... 18).contains(money.exponent),
            !currency.isEmpty
        else {
            throw ProviderClientError.unsupportedResponse
        }
        let divisor = (0 ..< money.exponent).reduce(Decimal(1)) {
            value,
            _ in
            value * 10
        }
        guard
            let balance = UsageBalance(
                id: "claude-usage-credits",
                label: "Usage credits",
                value: .available(
                    amount: money.amountMinor / divisor,
                    unit: currency,
                ),
            )
        else {
            throw ProviderClientError.unsupportedResponse
        }
        return [balance]
    }
}

private struct UsagePayload: Decodable {
    let fiveHour: WindowPayload
    let sevenDay: WindowPayload
    let extraUsage: ExtraUsagePayload?
    let spend: SpendPayload?

    private enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case extraUsage = "extra_usage"
        case spend
    }
}

private struct WindowPayload: Decodable {
    let utilization: Double
    let resetsAt: Date?

    private enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

private struct ExtraUsagePayload: Decodable {
    let isEnabled: Bool
    let userDisabled: Bool

    private enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case userDisabled = "user_disabled"
    }
}

private struct SpendPayload: Decodable {
    let enabled: Bool
    let balance: MoneyPayload?
}

private struct MoneyPayload: Decodable {
    let amountMinor: Decimal
    let currency: String
    let exponent: Int

    private enum CodingKeys: String, CodingKey {
        case amountMinor = "amount_minor"
        case currency
        case exponent
    }
}
