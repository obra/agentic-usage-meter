import Foundation

public struct FactoryUsageAdapter: ProviderAccountAdapter {
    public let provider = Provider.factory

    private let credentialStore: any CredentialStore
    private let transport: any HTTPTransport
    private let decoder: FactoryUsageDecoder

    public init(
        credentialStore: any CredentialStore,
        transport: any HTTPTransport =
            URLSessionHTTPTransport(),
        decoder: FactoryUsageDecoder =
            FactoryUsageDecoder()
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

        let credential: FactoryCredential?
        do {
            credential = try await credentialStore.load(
                FactoryCredential.self,
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
                    "https://api.factory.ai/api/billing/limits"
            )!
        )
        request.httpMethod = "GET"
        request.setValue(
            "Bearer \(credential.apiKey)",
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
