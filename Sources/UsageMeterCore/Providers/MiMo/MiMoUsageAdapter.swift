import Foundation

public struct MiMoUsageAdapter: ProviderAccountAdapter {
    public let provider = Provider.mimo

    private let credentialStore: any CredentialStore
    private let transport: any HTTPTransport
    private let decoder: MiMoUsageDecoder

    public init(
        credentialStore: any CredentialStore,
        transport: any HTTPTransport =
            URLSessionHTTPTransport(
                configuration: .ephemeral,
                followsRedirects: false
            ),
        decoder: MiMoUsageDecoder =
            MiMoUsageDecoder()
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

        let credential: MiMoWebCredential?
        do {
            credential = try await credentialStore.load(
                MiMoWebCredential.self,
                for: account.id
            )
        } catch {
            throw ProviderClientError.credentialMismatch
        }
        guard
            let credential,
            !credential.cookieHeader.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        else {
            throw ProviderClientError.reauthenticationRequired
        }

        var request = URLRequest(
            url: URL(
                string:
                    "https://platform.xiaomimimo.com/api/v1/tokenPlan/usage"
            )!
        )
        request.httpMethod = "GET"
        request.setValue(
            credential.cookieHeader,
            forHTTPHeaderField: "Cookie"
        )
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )

        let response = try await transport.send(request)
        switch response.statusCode {
        case 200...299:
            return try decoder.decode(
                response.data,
                accountID: account.id,
                fetchedAt: now
            )
        case 300...399, 401, 403:
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
