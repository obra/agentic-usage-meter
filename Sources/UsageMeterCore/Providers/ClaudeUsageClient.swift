import Foundation

public struct ClaudeUsageClient: UsageProviderClient {
    public let provider = Provider.claude

    private let transport: any HTTPTransport

    public init(transport: any HTTPTransport = URLSessionHTTPTransport()) {
        self.transport = transport
    }

    public func fetchUsage(
        accountID: UUID,
        credential: ProviderCredential,
        now: Date
    ) async throws -> UsageSnapshot {
        guard case let .claude(token) = credential, !token.isEmpty else {
            throw ProviderClientError.credentialMismatch
        }

        var request = URLRequest(
            url: URL(string: "https://api.anthropic.com/api/oauth/usage")!
        )
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "oauth-2025-04-20",
            forHTTPHeaderField: "anthropic-beta"
        )

        let response = try await transport.send(request)
        switch response.statusCode {
        case 200 ... 299:
            return try decodeSnapshot(
                response.data,
                accountID: accountID,
                fetchedAt: now
            )
        case 401, 403:
            throw ProviderClientError.reauthenticationRequired
        case 429:
            throw ProviderClientError.retryAfter(
                retryDate(from: response, relativeTo: now)
            )
        default:
            throw ProviderClientError.temporaryFailure
        }
    }

    private func decodeSnapshot(
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

    private func retryDate(
        from response: HTTPResponse,
        relativeTo now: Date
    ) -> Date? {
        guard let value = response.header(named: "Retry-After") else {
            return nil
        }
        if let seconds = TimeInterval(value), seconds.isFinite, seconds >= 0 {
            return now.addingTimeInterval(seconds)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value)
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
