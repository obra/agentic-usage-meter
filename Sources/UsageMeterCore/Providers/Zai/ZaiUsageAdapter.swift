import Foundation

public struct ZaiUsageAdapter: ProviderAccountAdapter {
    public let provider = Provider.zai

    private let credentialStore: any CredentialStore
    private let transport: any HTTPTransport
    private let decoder: ZaiUsageDecoder

    public init(
        credentialStore: any CredentialStore,
        transport: any HTTPTransport =
            URLSessionHTTPTransport(),
        decoder: ZaiUsageDecoder =
            ZaiUsageDecoder()
    ) {
        self.credentialStore = credentialStore
        self.transport = transport
        self.decoder = decoder
    }

    public func fetchUsage(
        for account: SubscriptionAccount,
        now: Date
    ) async throws -> UsageSnapshot {
        guard account.provider == provider else {
            throw ProviderClientError.credentialMismatch
        }

        let credential: ZaiCredential?
        do {
            credential = try await credentialStore.load(
                ZaiCredential.self,
                for: account.id
            )
        } catch {
            throw ProviderClientError.credentialMismatch
        }
        guard
            let credential,
            !credential.apiKey.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        else {
            throw ProviderClientError.reauthenticationRequired
        }

        var request = URLRequest(
            url: URL(
                string:
                    "https://api.z.ai/api/monitor/usage/quota/limit"
            )!
        )
        request.httpMethod = "GET"
        // Z.ai's monitor API expects the raw Coding Plan key
        // without a Bearer prefix.
        request.setValue(
            credential.apiKey,
            forHTTPHeaderField: "Authorization"
        )

        let response = try await transport.send(request)
        switch response.statusCode {
        case 200...299:
            return try decoder.decode(
                response.data,
                accountID: account.id,
                fetchedAt: now
            )
        case 401, 403:
            throw ProviderClientError
                .reauthenticationRequired
        case 429:
            throw ProviderClientError.retryAfter(
                response.retryDate(relativeTo: now)
            )
        default:
            throw ProviderClientError.temporaryFailure
        }
    }

    public func removeAuthentication(
        for account: SubscriptionAccount
    ) async throws {
        try await credentialStore.delete(for: account.id)
    }
}
