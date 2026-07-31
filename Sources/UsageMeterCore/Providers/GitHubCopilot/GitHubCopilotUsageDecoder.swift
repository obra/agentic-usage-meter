import Foundation

public struct GitHubCopilotUsageResult:
    Equatable,
    Sendable
{
    public let snapshot: UsageSnapshot
    public let plan: String?
    public let userID: String?

    public init(
        snapshot: UsageSnapshot,
        plan: String?,
        userID: String?
    ) {
        self.snapshot = snapshot
        self.plan = plan
        self.userID = userID
    }
}

public struct GitHubCopilotUsageDecoder: Sendable {
    public init() {}

    public func decode(
        _ data: Data,
        accountID: UUID,
        fetchedAt: Date
    ) throws -> GitHubCopilotUsageResult {
        let response: GitHubCopilotUsageResponse
        do {
            response = try JSONDecoder().decode(
                GitHubCopilotUsageResponse.self,
                from: data
            )
        } catch {
            throw ProviderClientError
                .unsupportedResponse
        }

        let limitedQuotas =
            response.quotaSnapshots
            .filter { _, quota in
                quota.unlimited != true
                    && (quota.entitlement ?? 0) > 0
            }
            .sorted { $0.key < $1.key }

        let windows: [UsageWindow]
        if limitedQuotas.isEmpty {
            windows = []
        } else {
            guard
                let resetAt = response.resetAt,
                let duration = Self.monthDuration(
                    endingAt: resetAt
                )
            else {
                throw ProviderClientError
                    .unsupportedResponse
            }
            windows = try limitedQuotas.map {
                key, quota in
                guard
                    let entitlement =
                        quota.entitlement,
                    let remaining = quota.remaining,
                    remaining.isFinite
                else {
                    throw ProviderClientError
                        .unsupportedResponse
                }
                let clampedRemaining = min(
                    max(remaining, 0),
                    entitlement
                )
                guard
                    let window = UsageWindow(
                        id:
                            "github-copilot-"
                            + key.replacingOccurrences(
                                of: "_",
                                with: "-"
                            ),
                        kind: .monthly,
                        duration: duration,
                        resetAt: resetAt,
                        consumedFraction: (entitlement
                            - clampedRemaining)
                            / entitlement,
                        label: Self.label(for: key)
                    )
                else {
                    throw ProviderClientError
                        .unsupportedResponse
                }
                return window
            }
        }

        return GitHubCopilotUsageResult(
            snapshot: UsageSnapshot(
                accountID: accountID,
                fetchedAt: fetchedAt,
                windows: windows
            ),
            plan: response.plan,
            userID: response.userID
        )
    }

    private static func monthDuration(
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

    private static func label(
        for key: String
    ) -> String {
        let words = key.replacingOccurrences(
            of: "_",
            with: " "
        )
        return words.prefix(1).uppercased()
            + words.dropFirst()
    }
}

private struct GitHubCopilotUsageResponse:
    Decodable
{
    let plan: String?
    let userID: String?
    let resetAt: Date?
    let quotaSnapshots: [String: Quota]

    enum CodingKeys: String, CodingKey {
        case copilotPlan = "copilot_plan"
        case plan
        case userID = "user_id"
        case id
        case quotaResetDateUTC =
            "quota_reset_date_utc"
        case quotaResetDate = "quota_reset_date"
        case limitedUserResetDate =
            "limited_user_reset_date"
        case quotaSnapshots = "quota_snapshots"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        plan =
            try container.decodeIfPresent(
                String.self,
                forKey: .copilotPlan
            )
            ?? container.decodeIfPresent(
                String.self,
                forKey: .plan
            )
        userID =
            try container.flexibleString(
                forKey: .userID
            )
            ?? container.flexibleString(
                forKey: .id
            )
        let resetString =
            try container.decodeIfPresent(
                String.self,
                forKey: .quotaResetDateUTC
            )
            ?? container.decodeIfPresent(
                String.self,
                forKey: .quotaResetDate
            )
            ?? container.decodeIfPresent(
                String.self,
                forKey: .limitedUserResetDate
            )
        resetAt = resetString.flatMap(
            Self.parseDate
        )
        quotaSnapshots =
            try container.decodeIfPresent(
                [String: Quota].self,
                forKey: .quotaSnapshots
            ) ?? [:]
    }

    private static func parseDate(
        _ value: String
    ) -> Date? {
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
        if let date = internet.date(from: value) {
            return date
        }

        let dateOnly = DateFormatter()
        dateOnly.locale = Locale(
            identifier: "en_US_POSIX"
        )
        dateOnly.calendar = Calendar(
            identifier: .gregorian
        )
        dateOnly.timeZone =
            TimeZone(secondsFromGMT: 0)
        dateOnly.dateFormat = "yyyy-MM-dd"
        return dateOnly.date(from: value)
    }

    struct Quota: Decodable {
        let unlimited: Bool?
        let entitlement: Double?
        let remaining: Double?

        enum CodingKeys: String, CodingKey {
            case unlimited
            case entitlement
            case remaining
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(
                keyedBy: CodingKeys.self
            )
            unlimited = try container.decodeIfPresent(
                Bool.self,
                forKey: .unlimited
            )
            entitlement = try container.flexibleDouble(
                forKey: .entitlement
            )
            remaining = try container.flexibleDouble(
                forKey: .remaining
            )
        }
    }
}

extension KeyedDecodingContainer {
    fileprivate func flexibleDouble(
        forKey key: Key
    ) throws -> Double? {
        if let value = try? decode(
            Double.self,
            forKey: key
        ) {
            return value
        }
        if let value = try? decode(
            String.self,
            forKey: key
        ) {
            return Double(value)
        }
        return nil
    }

    fileprivate func flexibleString(
        forKey key: Key
    ) throws -> String? {
        if let value = try? decode(
            String.self,
            forKey: key
        ) {
            return value
        }
        if let value = try? decode(
            Int.self,
            forKey: key
        ) {
            return String(value)
        }
        return nil
    }
}
