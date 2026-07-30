import Foundation

public struct ClaudeUsageClient: UsageProviderClient {
    public let provider = Provider.claude

    private let transport: any HTTPTransport
    private let decoder: ClaudeUsageDecoder

    public init(
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        decoder: ClaudeUsageDecoder = ClaudeUsageDecoder()
    ) {
        self.transport = transport
        self.decoder = decoder
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
            return try decoder.decode(
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
