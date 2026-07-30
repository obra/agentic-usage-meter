import Foundation
import UsageMeterClaudeWeb
import UsageMeterCore

@MainActor
public final class ClaudeWebAccountUsageClient:
    ProviderAccountAdapter
{
    public nonisolated let provider = Provider.claude

    private let client: ClaudeWebUsageClient

    public init(
        client: ClaudeWebUsageClient = ClaudeWebUsageClient(),
    ) {
        self.client = client
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
        try await Self.removeProfile(profileID)
    }

    public static func removeProfile(
        _ profileID: UUID,
    ) async throws {
        try await ClaudeWebProfileStore.remove(
            profileID: profileID,
        )
    }
}
