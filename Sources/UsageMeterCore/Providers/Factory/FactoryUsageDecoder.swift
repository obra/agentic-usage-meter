import Foundation

public struct FactoryUsageDecoder: Sendable {
    public init() {}

    public func decode(
        _ data: Data,
        accountID: UUID,
        fetchedAt: Date
    ) throws -> UsageSnapshot {
        let response: FactoryLimitsResponse
        do {
            response = try JSONDecoder().decode(
                FactoryLimitsResponse.self,
                from: data
            )
        } catch {
            throw ProviderClientError.unsupportedResponse
        }

        guard response.usesTokenRateLimitsBilling else {
            throw ProviderClientError.unsupportedResponse
        }

        var windows: [UsageWindow] = []
        if let standard = response.limits?.standard {
            try appendWindows(
                from: standard,
                poolID: "standard",
                poolLabel: "Standard",
                to: &windows
            )
        }
        if let core = response.limits?.core {
            try appendWindows(
                from: core,
                poolID: "core",
                poolLabel: "Droid Core",
                to: &windows
            )
        }

        var balances: [UsageBalance] = []
        if let cents = response.extraUsageBalanceCents {
            guard
                cents.isFinite,
                cents >= 0,
                let balance = UsageBalance(
                    id: "factory-extra-usage",
                    label: "Extra usage",
                    remainingAmount: cents / 100,
                    unit: "USD"
                )
            else {
                throw ProviderClientError.unsupportedResponse
            }
            balances.append(balance)
        }

        guard !windows.isEmpty || !balances.isEmpty else {
            throw ProviderClientError.unsupportedResponse
        }
        return UsageSnapshot(
            accountID: accountID,
            fetchedAt: fetchedAt,
            windows: windows,
            balances: balances
        )
    }

    private func appendWindows(
        from pool: FactoryLimitsResponse.Pool,
        poolID: String,
        poolLabel: String,
        to windows: inout [UsageWindow]
    ) throws {
        let candidates:
            [(
                name: String,
                kind: UsageWindowKind,
                duration: TimeInterval,
                value: FactoryLimitsResponse.Window?
            )] = [
                ("five-hour", .short, 18_000, pool.fiveHour),
                ("weekly", .weekly, 604_800, pool.weekly),
                ("monthly", .monthly, 2_592_000, pool.monthly),
            ]

        for candidate in candidates {
            guard let value = candidate.value else {
                continue
            }
            guard
                value.usedPercent.isFinite,
                (0...100).contains(value.usedPercent)
            else {
                throw ProviderClientError.unsupportedResponse
            }
            guard let windowEnd = value.windowEnd else {
                guard value.usedPercent == 0 else {
                    throw ProviderClientError.unsupportedResponse
                }
                continue
            }
            guard let resetAt = Self.parseDate(windowEnd) else {
                throw ProviderClientError.unsupportedResponse
            }
            guard
                let window = UsageWindow(
                    id:
                        "factory-\(poolID)-\(candidate.name)",
                    kind: candidate.kind,
                    duration: candidate.duration,
                    resetAt: resetAt,
                    consumedFraction:
                        value.usedPercent / 100,
                    label: poolLabel
                )
            else {
                throw ProviderClientError.unsupportedResponse
            }
            windows.append(window)
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

}

private struct FactoryLimitsResponse: Decodable {
    let usesTokenRateLimitsBilling: Bool
    let limits: Limits?
    let extraUsageBalanceCents: Double?

    struct Limits: Decodable {
        let standard: Pool?
        let core: Pool?
    }

    struct Pool: Decodable {
        let fiveHour: Window?
        let weekly: Window?
        let monthly: Window?
    }

    struct Window: Decodable {
        let usedPercent: Double
        let windowEnd: String?
    }
}
