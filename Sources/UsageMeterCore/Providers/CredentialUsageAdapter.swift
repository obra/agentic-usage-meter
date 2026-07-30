import Foundation

public typealias ProviderCredentialRefresh =
    @Sendable (
        UUID,
        ProviderCredential
    ) async throws -> ProviderCredential

public struct CredentialUsageAdapter: ProviderAccountAdapter {
    public let provider: Provider

    private let credentialStore: any CredentialStore
    private let client: any UsageProviderClient
    private let refreshCredential: ProviderCredentialRefresh?

    public init(
        provider: Provider,
        credentialStore: any CredentialStore,
        client: any UsageProviderClient,
        refreshCredential: ProviderCredentialRefresh? = nil
    ) {
        precondition(client.provider == provider)
        self.provider = provider
        self.credentialStore = credentialStore
        self.client = client
        self.refreshCredential = refreshCredential
    }

    public var canRecoverAuthenticationWithoutReconnect: Bool {
        refreshCredential != nil
    }

    public func fetchUsage(
        for account: SubscriptionAccount,
        now: Date
    ) async throws -> UsageSnapshot {
        guard account.provider == provider else {
            throw ProviderClientError.credentialMismatch
        }
        guard
            var credential = try await credentialStore.load(
                for: account.id
            )
        else {
            throw ProviderClientError.reauthenticationRequired
        }

        var didRefreshCredential = false
        if
            let refreshCredential,
            credential.isExpired(at: now)
        {
            credential = try await refreshCredential(
                account.id,
                credential
            )
            try await credentialStore.save(
                credential,
                for: account.id
            )
            didRefreshCredential = true
        }

        do {
            return try await client.fetchUsage(
                accountID: account.id,
                credential: credential,
                now: now
            )
        } catch let error as ProviderClientError {
            guard
                error == .reauthenticationRequired,
                !didRefreshCredential,
                let refreshCredential
            else {
                throw error
            }

            credential = try await refreshCredential(
                account.id,
                credential
            )
            try await credentialStore.save(
                credential,
                for: account.id
            )
            return try await client.fetchUsage(
                accountID: account.id,
                credential: credential,
                now: now
            )
        }
    }

    public func removeAuthentication(
        for account: SubscriptionAccount
    ) async throws {
        try await credentialStore.delete(for: account.id)
    }
}

private extension ProviderCredential {
    func isExpired(at date: Date) -> Bool {
        switch self {
        case .claude:
            false
        case let .codex(credential), let .kimi(credential):
            credential.expiresAt.map { $0 <= date } ?? false
        }
    }
}
