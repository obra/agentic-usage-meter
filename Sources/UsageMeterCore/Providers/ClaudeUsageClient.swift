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
                response.retryDate(relativeTo: now)
            )
        default:
            throw ProviderClientError.temporaryFailure
        }
    }
}
