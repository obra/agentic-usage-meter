import Foundation
import UsageMeterCore
import UsageMeterWeb

@MainActor
public final class OpenCodeWebAccountUsageClient:
    ProviderAccountAdapter
{
    public nonisolated let provider: Provider

    public typealias RemoveProfile =
        @MainActor @Sendable (
            UUID
        ) async throws -> Void

    private let base: any ProviderAccountAdapter
    private let removeProfile: RemoveProfile

    public init(
        base: any ProviderAccountAdapter,
        removeProfile:
            @escaping RemoveProfile = {
                try await AccountWebProfileStore
                    .remove(accountID: $0)
            }
    ) {
        provider = base.provider
        precondition(
            provider == .openCodeGo
                || provider == .openCodeZen
        )
        self.base = base
        self.removeProfile = removeProfile
    }

    public func fetchUsage(
        for account: SubscriptionAccount,
        now: Date
    ) async throws -> UsageSnapshot {
        try await base.fetchUsage(
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
        try await removeProfile(account.id)
    }
}
