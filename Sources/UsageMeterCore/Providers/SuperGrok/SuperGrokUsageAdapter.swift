import Foundation

public struct SuperGrokUsageAdapter:
    ProviderAccountAdapter
{
    public let provider = Provider.superGrok

    private let credentialStore: any CredentialStore
    private let transport: any HTTPTransport
    private let decoder: SuperGrokUsageDecoder

    public init(
        credentialStore: any CredentialStore,
        transport: any HTTPTransport =
            URLSessionHTTPTransport(),
        decoder: SuperGrokUsageDecoder =
            SuperGrokUsageDecoder()
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
            throw ProviderClientError
                .credentialMismatch
        }

        let credential: SuperGrokCredential?
        do {
            credential =
                try await credentialStore.load(
                    SuperGrokCredential.self,
                    for: account.id
                )
        } catch {
            throw ProviderClientError
                .credentialMismatch
        }
        guard
            let credential,
            !credential.accessToken.isEmpty,
            credential.identityKey != nil
        else {
            throw ProviderClientError
                .reauthenticationRequired
        }

        var request = URLRequest(
            url: URL(
                string:
                    "https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig"
            )!
        )
        request.httpMethod = "POST"
        request.httpBody = Data(
            [0, 0, 0, 0, 0]
        )
        request.setValue(
            "Bearer \(credential.accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "https://grok.com",
            forHTTPHeaderField: "Origin"
        )
        request.setValue(
            "https://grok.com/?_s=usage",
            forHTTPHeaderField: "Referer"
        )
        request.setValue(
            "*/*",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(
            "application/grpc-web+proto",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            "1",
            forHTTPHeaderField: "x-grpc-web"
        )
        request.setValue(
            "connect-es/2.1.1",
            forHTTPHeaderField: "x-user-agent"
        )

        let response =
            try await transport
            .send(request)
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
            throw
                ProviderClientError
                .retryAfter(
                    response.retryDate(
                        relativeTo: now
                    )
                )
        default:
            throw ProviderClientError
                .temporaryFailure
        }
    }

    public func removeAuthentication(
        for account: SubscriptionAccount
    ) async throws {
        try await credentialStore.delete(
            for: account.id
        )
    }
}
