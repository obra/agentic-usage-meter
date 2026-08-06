import Foundation
import OSLog

private let claudeLogger = Logger(
    subsystem:
        "com.fsck.agentic-usage-meter",
    category: "Claude"
)

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
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let value = try container.decode(String.self)
                guard let date = Self.parseDate(value) else {
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription:
                        "Expected date string to be ISO8601-formatted."
                    )
                }
                return date
            }
            payload = try decoder.decode(UsagePayload.self, from: data)
        } catch {
            claudeLogger.error(
                "Rejected usage response: \(Self.structuralDescription(of: error), privacy: .public)"
            )
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
            claudeLogger.error(
                "Rejected usage response: fiveHourUtilizationValid=\(Self.isValidUtilization(payload.fiveHour.utilization), privacy: .public) sevenDayUtilizationValid=\(Self.isValidUtilization(payload.sevenDay.utilization), privacy: .public)"
            )
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

    // Diagnostics name only field paths and JSON structure, never
    // payload values, so logs stay safe to share in bug reports.
    private static func structuralDescription(
        of error: any Error
    ) -> String {
        guard let error = error as? DecodingError else {
            return "not JSON"
        }
        switch error {
        case let .keyNotFound(key, context):
            return "missing key \(path(context, trailing: key))"
        case let .valueNotFound(_, context):
            return "null value at \(path(context))"
        case let .typeMismatch(_, context):
            return "unexpected type at \(path(context))"
        case .dataCorrupted(let context):
            guard context.codingPath.isEmpty else {
                return "unreadable value at \(path(context))"
            }
            return "not JSON"
        @unknown default:
            return "undecodable JSON"
        }
    }

    private static func path(
        _ context: DecodingError.Context,
        trailing key: (any CodingKey)? = nil
    ) -> String {
        let components =
            (context.codingPath + [key].compactMap { $0 })
                .map(\.stringValue)
        guard !components.isEmpty else {
            return "top level"
        }
        return components.joined(separator: ".")
    }

    private static func isValidUtilization(
        _ utilization: Double
    ) -> Bool {
        utilization.isFinite && (0 ... 100).contains(utilization)
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        if let date = fractional.date(from: value) {
            return date
        }

        let internet = ISO8601DateFormatter()
        internet.formatOptions = [
            .withInternetDateTime
        ]
        return internet.date(from: value)
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
            claudeLogger.error(
                "Rejected usage response: balanceAmountNonNegative=\(money.amountMinor >= 0, privacy: .public) balanceExponentSupported=\((0 ... 18).contains(money.exponent), privacy: .public) balanceCurrencyPresent=\(!currency.isEmpty, privacy: .public)"
            )
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
