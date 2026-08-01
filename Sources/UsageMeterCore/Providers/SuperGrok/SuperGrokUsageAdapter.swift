import Foundation

public struct SuperGrokUsageAdapter:
    ProviderAccountAdapter
{
    private static let clientVersion = "0.2.118"

    public let provider = Provider.superGrok

    private let credentialStore: any CredentialStore
    private let transport: any HTTPTransport
    private let decoder: SuperGrokUsageDecoder
    private let refreshClient: SuperGrokOIDCRefreshClient

    public init(
        credentialStore: any CredentialStore,
        decoder: SuperGrokUsageDecoder =
            SuperGrokUsageDecoder()
    ) {
        self.init(
            credentialStore: credentialStore,
            transport: URLSessionHTTPTransport(),
            refreshTransport:
                URLSessionHTTPTransport(
                    configuration: .ephemeral,
                    followsRedirects: false
                ),
            decoder: decoder
        )
    }

    public init(
        credentialStore: any CredentialStore,
        transport: any HTTPTransport,
        decoder: SuperGrokUsageDecoder =
            SuperGrokUsageDecoder()
    ) {
        self.init(
            credentialStore: credentialStore,
            transport: transport,
            refreshTransport: transport,
            decoder: decoder
        )
    }

    private init(
        credentialStore: any CredentialStore,
        transport: any HTTPTransport,
        refreshTransport: any HTTPTransport,
        decoder: SuperGrokUsageDecoder
    ) {
        self.credentialStore = credentialStore
        self.transport = transport
        self.decoder = decoder
        refreshClient = SuperGrokOIDCRefreshClient(
            transport: refreshTransport
        )
    }

    public var canRecoverAuthenticationWithoutReconnect: Bool {
        true
    }

    public func fetchUsage(
        for account: SubscriptionAccount,
        now: Date
    ) async throws -> UsageSnapshot {
        guard account.provider == provider else {
            throw ProviderClientError
                .credentialMismatch
        }

        let storedCredential: SuperGrokCredential?
        do {
            storedCredential =
                try await credentialStore.load(
                    SuperGrokCredential.self,
                    for: account.id
                )
        } catch {
            throw ProviderClientError
                .credentialMismatch
        }
        guard
            var credential = storedCredential,
            !credential.accessToken.isEmpty,
            credential.userID?.isEmpty == false
        else {
            throw ProviderClientError
                .reauthenticationRequired
        }

        var didRefreshCredential = false
        if
            credential.hasRefreshMaterial,
            credential.needsRefresh(at: now)
        {
            credential = try await refreshClient
                .refresh(credential, now: now)
            try await credentialStore.save(
                credential,
                for: account.id
            )
            didRefreshCredential = true
        }

        var response = try await transport.send(
            billingRequest(for: credential)
        )
        if response.statusCode == 401
            || response.statusCode == 403
        {
            if !didRefreshCredential {
                credential = try await refreshClient
                    .refresh(credential, now: now)
                try await credentialStore.save(
                    credential,
                    for: account.id
                )
            }
            response = try await transport.send(
                billingRequest(for: credential)
            )
        }
        return try decode(
            response,
            accountID: account.id,
            now: now
        )
    }

    private func billingRequest(
        for credential: SuperGrokCredential
    ) -> URLRequest {
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
            credential.userID,
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
        return request
    }

    private func decode(
        _ response: HTTPResponse,
        accountID: UUID,
        now: Date
    ) throws -> UsageSnapshot {
        switch response.statusCode {
        case 200...299:
            return try decoder.decode(
                response.data,
                accountID: accountID,
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
