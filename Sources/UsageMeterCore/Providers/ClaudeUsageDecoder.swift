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
            windows: [shortWindow, weeklyWindow] + scopedWindows(from: payload),
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

    // The `limits` array is the only place the provider reports
    // per-model pools (for example the Fable weekly share); the legacy
    // top-level windows never carry them. Scoped entries are optional
    // surface on top of the qualified legacy contract, so anything
    // unusable is skipped — never a reason to reject the response.
    // Unscoped entries mirror the legacy windows and would
    // double-render, and non-weekly groups are unqualified surface;
    // both are expected and pass silently. Only malformed entries are
    // counted and logged: an undecodable element, an out-of-range
    // percent, or a nonzero percent without a reset (which the
    // UsageWindow initializer drops per the no-invented-reset
    // invariant). Entries that collide on id resolve to the
    // higher-consumed one, so a duplicate can only tighten the
    // reported limit, never hide it.
    private func scopedWindows(
        from payload: UsagePayload
    ) -> [UsageWindow] {
        let limits: [LossyLimitPayload]
        switch payload.limits {
        case .absent:
            return []
        case .malformed:
            claudeLogger.error(
                "Skipped malformed scoped limit entries: count=\(1, privacy: .public)"
            )
            return []
        case .values(let decodedLimits):
            limits = decodedLimits
        }
        var windows: [UsageWindow] = []
        var indexByID: [String: Int] = [:]
        var malformedEntries = 0
        for entry in limits {
            guard let limit = entry.value else {
                malformedEntries += 1
                continue
            }
            guard
                limit.group == "weekly"
            else {
                continue
            }
            guard let scope = limit.scope else {
                continue
            }
            guard let model = scope.model else {
                malformedEntries += 1
                continue
            }
            let displayName = Self.normalizedText(model.displayName)
            let modelID = Self.normalizedText(model.id)
            guard
                let identity = modelID.map({ "id:\($0)" })
                    ?? displayName.map({ "name:\($0)" }),
                let label = displayName ?? modelID
            else {
                malformedEntries += 1
                continue
            }
            guard
                Self.isValidUtilization(limit.percent),
                let window = UsageWindow(
                    id: "claude-weekly-scoped-\(Self.stableIdentifierComponent(identity))",
                    kind: .weekly,
                    duration: 604_800,
                    resetAt: limit.resetsAt,
                    consumedFraction: limit.percent / 100,
                    label: label,
                )
            else {
                malformedEntries += 1
                continue
            }
            if let existing = indexByID[window.id] {
                if Self.shouldPrefer(window, over: windows[existing]) {
                    windows[existing] = window
                }
            } else {
                indexByID[window.id] = windows.count
                windows.append(window)
            }
        }
        if malformedEntries > 0 {
            claudeLogger.error(
                "Skipped malformed scoped limit entries: count=\(malformedEntries, privacy: .public)"
            )
        }
        return windows
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let normalized = value.trimmingCharacters(
            in: .whitespacesAndNewlines,
        )
        return normalized.isEmpty ? nil : normalized
    }

    private static func stableIdentifierComponent(_ value: String) -> String {
        Data(value.utf8)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func shouldPrefer(
        _ candidate: UsageWindow,
        over existing: UsageWindow,
    ) -> Bool {
        if candidate.consumedFraction != existing.consumedFraction {
            return candidate.consumedFraction > existing.consumedFraction
        }
        switch (candidate.resetAt, existing.resetAt) {
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (let candidateReset?, let existingReset?):
            return candidateReset < existingReset
        case (nil, nil):
            return false
        }
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
    let limits: LimitsPayload

    private enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case extraUsage = "extra_usage"
        case spend
        case limits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour = try container.decode(
            WindowPayload.self,
            forKey: .fiveHour
        )
        sevenDay = try container.decode(
            WindowPayload.self,
            forKey: .sevenDay
        )
        extraUsage = try container.decodeIfPresent(
            ExtraUsagePayload.self,
            forKey: .extraUsage
        )
        spend = try container.decodeIfPresent(
            SpendPayload.self,
            forKey: .spend
        )
        // A drifted `limits` container (present but not an array)
        // degrades like a drifted element: scoped limits are optional
        // surface and must never black out the legacy windows.
        if !container.contains(.limits) {
            limits = .absent
        } else if try container.decodeNil(forKey: .limits) {
            limits = .absent
        } else {
            do {
                limits = .values(
                    try container.decode(
                        [LossyLimitPayload].self,
                        forKey: .limits,
                    ),
                )
            } catch {
                limits = .malformed
            }
        }
    }
}

private enum LimitsPayload {
    case absent
    case malformed
    case values([LossyLimitPayload])
}

// A limit entry that fails to decode becomes nil instead of failing
// the whole response: scoped limits are optional surface, and one
// drifted entry must not black out an account's legacy windows.
private struct LossyLimitPayload: Decodable {
    let value: LimitPayload?

    init(from decoder: Decoder) {
        value = try? LimitPayload(from: decoder)
    }
}

private struct LimitPayload: Decodable {
    let group: String
    let percent: Double
    let resetsAt: Date?
    let scope: ScopePayload?

    private enum CodingKeys: String, CodingKey {
        case group
        case percent
        case resetsAt = "resets_at"
        case scope
    }
}

private struct ScopePayload: Decodable {
    let model: ModelScopePayload?
}

private struct ModelScopePayload: Decodable {
    let id: String?
    let displayName: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
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
