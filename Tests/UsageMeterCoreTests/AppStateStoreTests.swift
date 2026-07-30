import Foundation
import Testing
@testable import UsageMeterCore

@Test
func stateStoreRoundTripsAccountsAndSnapshots() async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStateStore(fileURL: directory.appending(path: "state.json"))
    let state = try makePersistedState()

    try await store.save(state)

    #expect(try await store.load() == state)
}

@Test
func stateStoreReturnsEmptyStateWhenFileDoesNotExist() async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStateStore(fileURL: directory.appending(path: "state.json"))

    #expect(try await store.load() == .empty)
}

@Test
func stateStoreAtomicallyReplacesExistingState() async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStateStore(fileURL: directory.appending(path: "state.json"))
    let original = try makePersistedState()
    let replacement = PersistedAppState(
        accounts: [
            SubscriptionAccount(
                provider: .kimi,
                displayName: "Kimi",
                authenticatedIdentity: "kimi@example.com",
                displayOrder: 0
            )
        ],
        snapshots: [:]
    )

    try await store.save(original)
    try await store.save(replacement)

    #expect(try await store.load() == replacement)
    #expect(
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            == ["state.json"]
    )
}

@Test
func stateStoreReportsCorruptDataWithoutOverwritingIt() async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appending(path: "state.json")
    let corruptData = Data(#"{"accounts":"not-an-array"}"#.utf8)
    try corruptData.write(to: fileURL)
    let store = AppStateStore(fileURL: fileURL)

    await #expect(throws: AppStateStoreError.corruptData) {
        _ = try await store.load()
    }
    #expect(try Data(contentsOf: fileURL) == corruptData)
}

private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "AgenticUsageMeterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    return directory
}

private func makePersistedState() throws -> PersistedAppState {
    let account = SubscriptionAccount(
        provider: .codex,
        displayName: "Work Codex",
        authenticatedIdentity: "jesse@example.com",
        displayOrder: 1
    )
    let window = try #require(
        UsageWindow(
            id: "weekly",
            kind: .weekly,
            duration: 604_800,
            resetAt: Date(timeIntervalSince1970: 2_000_000_000),
            consumedFraction: 0.42
        )
    )
    let snapshot = UsageSnapshot(
        accountID: account.id,
        fetchedAt: Date(timeIntervalSince1970: 1_999_999_000),
        windows: [window]
    )

    return PersistedAppState(
        accounts: [account],
        snapshots: [account.id: snapshot],
        refreshStates: [
            account.id: AccountRefreshState(
                lastRequestStartedAt: snapshot.fetchedAt,
                providerRetryAt: nil,
                failureBackoffUntil: nil,
                consecutiveTransientFailures: 0,
                requiresReauthentication: false
            )
        ]
    )
}
