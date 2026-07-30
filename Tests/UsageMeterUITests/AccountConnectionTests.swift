import Foundation
import Testing
import UsageMeterCore

@testable import UsageMeterUI

@Test
@MainActor
func removingAccountDeletesCredentialAndState() async throws {
    let account = SubscriptionAccount(
        provider: .codex,
        displayName: "Personal",
        displayOrder: 0
    )
    let stateStore = TestAppStateStore(
        state: PersistedAppState(
            accounts: [account],
            snapshots: [:]
        )
    )
    let credentials = TestCredentialStore(
        credentials: [
            account.id: .codex(
                OAuthCredential(
                    accessToken: "token",
                    accountID: "provider-account"
                )
            ),
        ]
    )
    let model = AppModel(
        stateStore: stateStore,
        credentialStore: credentials,
        clients: [],
        now: { Date(timeIntervalSince1970: 2_000_000_000) }
    )
    await model.start()

    try await model.removeAccount(id: account.id)

    #expect(model.accounts.isEmpty)
    #expect(await credentials.load(for: account.id) == nil)
    #expect(await stateStore.state.accounts.isEmpty)
}

@Test
@MainActor
func connectingAccountValidatesBeforePersisting() async throws {
    let reference = Date(timeIntervalSince1970: 2_000_000_000)
    let account = SubscriptionAccount(
        provider: .kimi,
        displayName: "Kimi",
        displayOrder: 0
    )
    let snapshot = UsageSnapshot(
        accountID: account.id,
        fetchedAt: reference,
        windows: [
            makeTestWindow(
                id: "weekly",
                resetAt: reference.addingTimeInterval(10000),
                consumedFraction: 0.4
            ),
        ]
    )
    let stateStore = TestAppStateStore(state: .empty)
    let credentials = TestCredentialStore()
    let provider = TestUsageProviderClient(
        provider: .kimi,
        snapshots: [account.id: snapshot]
    )
    let model = AppModel(
        stateStore: stateStore,
        credentialStore: credentials,
        clients: [provider],
        now: { reference }
    )
    await model.start()
    let credential = ProviderCredential.kimi(
        OAuthCredential(
            accessToken: "access",
            refreshToken: "refresh"
        )
    )

    try await model.connectAccount(
        account,
        credential: credential
    )

    #expect(model.accounts.map(\.account) == [account])
    #expect(model.accounts.first?.snapshot == snapshot)
    #expect(await credentials.load(for: account.id) == credential)
    #expect(await stateStore.state.accounts == [account])
    #expect(await stateStore.state.snapshots[account.id] == snapshot)
}

@Test
@MainActor
func failedConnectionLeavesNoCredentialOrMetadata() async {
    let reference = Date(timeIntervalSince1970: 2_000_000_000)
    let account = SubscriptionAccount(
        provider: .codex,
        displayName: "Work",
        displayOrder: 0
    )
    let stateStore = TestAppStateStore(state: .empty)
    let credentials = TestCredentialStore()
    let model = AppModel(
        stateStore: stateStore,
        credentialStore: credentials,
        clients: [
            TestUsageProviderClient(
                provider: .codex,
                snapshots: [:]
            ),
        ],
        now: { reference }
    )
    await model.start()

    await #expect(throws: ProviderClientError.temporaryFailure) {
        try await model.connectAccount(
            account,
            credential: .codex(
                OAuthCredential(
                    accessToken: "access",
                    accountID: "provider-account"
                )
            )
        )
    }

    #expect(model.accounts.isEmpty)
    #expect(await credentials.load(for: account.id) == nil)
    #expect(await stateStore.state == .empty)
}

@Test
@MainActor
func reconnectValidatesReplacementBeforeClearingError() async throws {
    let reference = Date(timeIntervalSince1970: 2_000_000_000)
    let account = SubscriptionAccount(
        provider: .codex,
        displayName: "Work",
        displayOrder: 0
    )
    let fresh = UsageSnapshot(
        accountID: account.id,
        fetchedAt: reference,
        windows: []
    )
    let stateStore = TestAppStateStore(
        state: PersistedAppState(
            accounts: [account],
            snapshots: [:],
            refreshStates: [
                account.id: AccountRefreshState(
                    requiresReauthentication: true
                ),
            ]
        )
    )
    let credentials = TestCredentialStore()
    let provider = TestUsageProviderClient(
        provider: .codex,
        snapshots: [account.id: fresh]
    )
    let model = AppModel(
        stateStore: stateStore,
        credentialStore: credentials,
        clients: [provider],
        now: { reference }
    )
    await model.start()
    #expect(model.accounts[0].error == .authenticationRequired)
    let replacement = ProviderCredential.codex(
        OAuthCredential(
            accessToken: "replacement",
            accountID: "provider-account"
        )
    )

    try await model.reconnectAccount(
        id: account.id,
        credential: replacement
    )

    #expect(model.accounts[0].error == nil)
    #expect(model.accounts[0].snapshot == fresh)
    #expect(await credentials.load(for: account.id) == replacement)
    #expect(
        await stateStore.state.refreshStates[account.id]?
            .requiresReauthentication == false
    )
}
