import Foundation
import UsageMeterCore

@testable import UsageMeterUI

actor TestAppStateStore: AppStatePersisting {
    private(set) var state: PersistedAppState

    init(state: PersistedAppState) {
        self.state = state
    }

    func load() -> PersistedAppState {
        state
    }

    func save(_ state: PersistedAppState) {
        self.state = state
    }
}

actor TestCredentialStore: CredentialStore {
    private var credentials: [UUID: ProviderCredential]

    init(credentials: [UUID: ProviderCredential] = [:]) {
        self.credentials = credentials
    }

    func save(
        _ credential: ProviderCredential,
        for accountID: UUID,
    ) {
        credentials[accountID] = credential
    }

    func load(for accountID: UUID) -> ProviderCredential? {
        credentials[accountID]
    }

    func delete(for accountID: UUID) {
        credentials[accountID] = nil
    }
}

actor TestUsageProviderClient: UsageProviderClient {
    let provider: Provider
    private let snapshots: [UUID: UsageSnapshot]
    private(set) var requestedAccountIDs: [UUID] = []

    init(provider: Provider, snapshots: [UUID: UsageSnapshot]) {
        self.provider = provider
        self.snapshots = snapshots
    }

    func fetchUsage(
        accountID: UUID,
        credential _: ProviderCredential,
        now _: Date,
    ) throws -> UsageSnapshot {
        requestedAccountIDs.append(accountID)
        guard let snapshot = snapshots[accountID] else {
            throw ProviderClientError.temporaryFailure
        }
        return snapshot
    }
}

actor TestClaudeAccountUsageClient: ClaudeAccountUsageFetching {
    private let snapshots: [UUID: UsageSnapshot]
    private(set) var requestedAccountIDs: [UUID] = []

    init(snapshots: [UUID: UsageSnapshot]) {
        self.snapshots = snapshots
    }

    func fetchUsage(
        accountID: UUID,
        profileID _: UUID,
        organizationID _: UUID,
        now _: Date,
    ) throws -> UsageSnapshot {
        requestedAccountIDs.append(accountID)
        guard let snapshot = snapshots[accountID] else {
            throw ProviderClientError.temporaryFailure
        }
        return snapshot
    }
}

func makeTestWindow(
    id: String,
    resetAt: Date,
    consumedFraction: Double,
) -> UsageWindow {
    UsageWindow(
        id: id,
        kind: .weekly,
        duration: 604_800,
        resetAt: resetAt,
        consumedFraction: consumedFraction,
    )!
}

@MainActor
final class TestClaudeProfileRemover {
    private(set) var removedProfileIDs: [UUID] = []

    func remove(_ profileID: UUID) {
        removedProfileIDs.append(profileID)
    }
}
