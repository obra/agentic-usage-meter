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
    private var credentials: [UUID: Data]

    init(credentials: [UUID: ProviderCredential] = [:]) {
        self.credentials = Dictionary(
            uniqueKeysWithValues: credentials.map { accountID, credential in
                (
                    accountID,
                    try! JSONEncoder().encode(credential)
                )
            }
        )
    }

    func saveData(
        _ data: Data,
        for accountID: UUID,
    ) {
        credentials[accountID] = data
    }

    func loadData(for accountID: UUID) -> Data? {
        credentials[accountID]
    }

    func loadCredential(for accountID: UUID) -> ProviderCredential? {
        guard let data = credentials[accountID] else {
            return nil
        }
        return try? JSONDecoder().decode(
            ProviderCredential.self,
            from: data
        )
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

struct CredentialRefreshRequest: Equatable, Sendable {
    let accountID: UUID
    let credential: ProviderCredential
}

actor TestCredentialRefreshRecorder {
    private let replacement: ProviderCredential
    private(set) var requests: [CredentialRefreshRequest] = []

    init(replacement: ProviderCredential) {
        self.replacement = replacement
    }

    func refresh(
        accountID: UUID,
        credential: ProviderCredential,
    ) throws -> ProviderCredential {
        requests.append(
            CredentialRefreshRequest(
                accountID: accountID,
                credential: credential,
            ),
        )
        return replacement
    }
}

final class TestMutableDate: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    var current: Date {
        lock.withLock { value }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock {
            value = value.addingTimeInterval(interval)
        }
    }
}

actor TestAutomaticRefreshSleeper {
    private let clock: TestMutableDate
    private(set) var intervals: [TimeInterval] = []

    init(clock: TestMutableDate) {
        self.clock = clock
    }

    func sleep(interval: TimeInterval) throws {
        intervals.append(interval)
        guard intervals.count == 1 else {
            throw CancellationError()
        }
        clock.advance(by: interval)
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
