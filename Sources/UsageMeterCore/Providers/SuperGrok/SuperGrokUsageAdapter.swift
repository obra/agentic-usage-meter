import Foundation

public struct SuperGrokUsageAdapter:
    ProviderAccountAdapter
{
    private static let clientVersion = "0.2.118"

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
            let userID = credential.userID,
            !userID.isEmpty
        else {
            throw ProviderClientError
                .reauthenticationRequired
        }

        var request = URLRequest(
            url: URL(
                string:
                    "https://cli-chat-proxy.grok.com/v1/billing?format=credits"
            )!
        )
        request.httpMethod = "GET"
        request.setValue(
            "Bearer \(credential.accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "xai-grok-cli",
            forHTTPHeaderField: "X-XAI-Token-Auth"
        )
        request.setValue(
            userID,
            forHTTPHeaderField: "x-userid"
        )
        request.setValue(
            Self.clientVersion,
            forHTTPHeaderField:
                "x-grok-client-version"
        )
        request.setValue(
            "headless",
            forHTTPHeaderField:
                "x-grok-client-mode"
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
