import Foundation
import UsageMeterClaudeWeb
import UsageMeterCore

@MainActor
public final class ClaudeWebAccountUsageClient:
    ClaudeAccountUsageFetching
{
    private let client: ClaudeWebUsageClient

    public init(
        client: ClaudeWebUsageClient = ClaudeWebUsageClient(),
    ) {
        self.client = client
    }

    public func fetchUsage(
        accountID: UUID,
        profileID: UUID,
        organizationID: UUID,
        now: Date,
    ) async throws -> UsageSnapshot {
        try await client.fetchUsage(
            accountID: accountID,
            profileID: profileID,
            organizationID: organizationID,
            now: now,
        )
    }

    public static func removeProfile(
        _ profileID: UUID,
    ) async throws {
        try await ClaudeWebProfileStore.remove(
            profileID: profileID,
        )
    }
}
