import Foundation
import UsageMeterCore
import UsageMeterWeb
import WebKit

@MainActor
public final class MiMoWebAccountUsageClient:
    ProviderAccountAdapter
{
    public nonisolated let provider = Provider.mimo

    public nonisolated var canRecoverAuthenticationWithoutReconnect: Bool {
        true
    }

    public typealias RemoveProfile =
        @MainActor @Sendable (
            UUID
        ) async throws -> Void
    public typealias LoadCookieHeader =
        @MainActor @Sendable (
            UUID
        ) async -> String?
    public typealias EvictCookieProfile =
        @MainActor @Sendable (UUID) async -> Void
    public typealias FinishCookieProfile =
        @MainActor @Sendable (UUID) -> Void

    private let base: any ProviderAccountAdapter
    private let credentialStore:
        any CredentialStore
    private let loadCookieHeader: LoadCookieHeader
    private let evictCookieProfile:
        EvictCookieProfile
    private let finishCookieProfile:
        FinishCookieProfile
    private let removeProfile: RemoveProfile

    public init(
        base: any ProviderAccountAdapter,
        credentialStore: any CredentialStore,
        loadCookieHeader: LoadCookieHeader? = nil,
        evictCookieProfile:
            EvictCookieProfile? = nil,
        finishCookieProfile:
            FinishCookieProfile? = nil,
        removeProfile:
            @escaping RemoveProfile = {
                try await AccountWebProfileStore
                    .remove(accountID: $0)
            }
    ) {
        precondition(base.provider == .mimo)
        self.base = base
        self.credentialStore = credentialStore
        if let loadCookieHeader {
            self.loadCookieHeader =
                loadCookieHeader
            self.evictCookieProfile =
                evictCookieProfile ?? { _ in }
            self.finishCookieProfile =
                finishCookieProfile ?? { _ in }
        } else {
            let source = ProfileAuthCookieSource.mimo()
            self.loadCookieHeader = {
                accountID in
                await source.authCookie(
                    accountID: accountID
                )
            }
            self.evictCookieProfile = {
                await source.prepareForRemoval(
                    accountID: $0
                )
            }
            self.finishCookieProfile = {
                source.finishRemoval(accountID: $0)
            }
        }
        self.removeProfile = removeProfile
    }

    public func fetchUsage(
        for account: SubscriptionAccount,
        now: Date
    ) async throws -> UsageSnapshot {
        if
            let profileCookieHeader =
                await loadCookieHeader(account.id),
            let storedCredential =
                try await credentialStore.load(
                    MiMoWebCredential.self,
                    for: account.id
                ),
            storedCredential.cookieHeader
                != profileCookieHeader,
            let refreshed = MiMoWebCredential(
                cookieHeader: profileCookieHeader
            )
        {
            try await credentialStore.save(
                refreshed,
                for: account.id
            )
        }
        return try await base.fetchUsage(
            for: account,
            now: now
        )
    }

    public func removeAuthentication(
        for account: SubscriptionAccount
    ) async throws {
        try await base.removeAuthentication(
            for: account
        )
        await evictCookieProfile(account.id)
        defer {
            finishCookieProfile(account.id)
        }
        try await removeProfile(account.id)
    }
}

extension ProfileAuthCookieSource {
    static func mimo() -> ProfileAuthCookieSource {
        ProfileAuthCookieSource(
            retryDelays: [
                .milliseconds(250),
                .milliseconds(500),
                .seconds(1),
            ],
            extract: {
                MiMoLoginDetector.cookieHeader(in: $0)
            },
            profileFactory: {
                WebKitProfileCookieLoader(
                    accountID: $0,
                    warmupURL: URL(
                        string:
                            "https://platform.xiaomimimo.com/robots.txt"
                    )!,
                    hasAuthentication: {
                        MiMoLoginDetector.cookieHeader(
                            in: $0
                        ) != nil
                    }
                )
            }
        )
    }
}
