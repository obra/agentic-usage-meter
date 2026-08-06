import Foundation
import UsageMeterClaudeWeb
import UsageMeterCore

@MainActor
public final class ClaudeWebAccountUsageClient:
    ProviderAccountAdapter
{
    public nonisolated let provider = Provider.claude

    public typealias RemoveProfile =
        @MainActor @Sendable (UUID) async throws -> Void

    private let client: ClaudeWebUsageClient
    private let removeProfile: RemoveProfile

    public init(
        client: ClaudeWebUsageClient = ClaudeWebUsageClient(),
        removeProfile: @escaping RemoveProfile = {
            try await ClaudeWebProfileStore.remove(
                profileID: $0,
            )
        },
    ) {
        self.client = client
        self.removeProfile = removeProfile
    }

    public func fetchUsage(
        for account: SubscriptionAccount,
        now: Date
    ) async throws -> UsageSnapshot {
        guard
            account.provider == provider,
            let profileID = account.claudeProfileID,
            let organizationID = account.claudeOrganizationID
        else {
            throw ProviderClientError.credentialMismatch
        }
        return try await client.fetchUsage(
            accountID: account.id,
            profileID: profileID,
            organizationID: organizationID,
            now: now
        )
    }

    public nonisolated var canRecoverAuthenticationWithoutReconnect: Bool {
        true
    }

    public func removeAuthentication(
        for account: SubscriptionAccount
    ) async throws {
        guard
            account.provider == provider,
            let profileID = account.claudeProfileID
        else {
            throw ProviderClientError.credentialMismatch
        }
        await client.prepareProfileRemoval(profileID: profileID)
        defer {
            client.finishProfileRemoval(profileID: profileID)
        }
        try await removeProfile(profileID)
    }
}
