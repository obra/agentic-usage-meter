import Foundation
import Testing
import UsageMeterCore

@testable import UsageMeterUI

@Suite
@MainActor
struct AppModelTests {
    private let reference = Date(
        timeIntervalSince1970: 2_000_000_000
    )

    @Test
    func launchShowsCacheThenRefreshesEligibleAccount() async throws {
        let account = SubscriptionAccount(
            provider: .codex,
            displayName: "Work",
            displayOrder: 0
        )
        let cached = UsageSnapshot(
            accountID: account.id,
            fetchedAt: reference.addingTimeInterval(-1000),
            windows: [
                makeTestWindow(
                    id: "cached",
                    resetAt: reference.addingTimeInterval(10000),
                    consumedFraction: 0.2
                ),
            ]
        )
        let fresh = UsageSnapshot(
            accountID: account.id,
            fetchedAt: reference,
            windows: [
                makeTestWindow(
                    id: "fresh",
                    resetAt: reference.addingTimeInterval(20000),
                    consumedFraction: 0.3
                ),
            ]
        )
        let stateStore = TestAppStateStore(
            state: PersistedAppState(
                accounts: [account],
                snapshots: [account.id: cached],
                refreshStates: [
                    account.id: AccountRefreshState(
                        lastRequestStartedAt:
                        reference.addingTimeInterval(-601)
                    ),
                ]
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
        let provider = TestUsageProviderClient(
            provider: .codex,
            snapshots: [account.id: fresh]
        )
        let model = AppModel(
            stateStore: stateStore,
            credentialStore: credentials,
            clients: [provider],
            now: { self.reference }
        )

        await model.start()

        #expect(model.accounts.count == 1)
        #expect(model.accounts[0].snapshot == fresh)
        #expect(await provider.requestedAccountIDs == [account.id])
        #expect(
            await stateStore.state.snapshots[account.id]
                == fresh
        )
    }

    @Test
    func launchDoesNotRefreshAccountInsideHardFloor() async {
        let account = SubscriptionAccount(
            provider: .kimi,
            displayName: "Kimi",
            displayOrder: 0
        )
        let cached = UsageSnapshot(
            accountID: account.id,
            fetchedAt: reference.addingTimeInterval(-599),
            windows: []
        )
        let stateStore = TestAppStateStore(
            state: PersistedAppState(
                accounts: [account],
                snapshots: [account.id: cached],
                refreshStates: [
                    account.id: AccountRefreshState(
                        lastRequestStartedAt:
                        reference.addingTimeInterval(-599)
                    ),
                ]
            )
        )
        let provider = TestUsageProviderClient(
            provider: .kimi,
            snapshots: [:]
        )
        let model = AppModel(
            stateStore: stateStore,
            credentialStore: TestCredentialStore(),
            clients: [provider],
            now: { self.reference }
        )

        await model.start()

        #expect(model.accounts[0].snapshot == cached)
        #expect(await provider.requestedAccountIDs.isEmpty)
    }

    @Test
    func renamePersistsTrimmedAccountLabel() async throws {
        let account = SubscriptionAccount(
            provider: .codex,
            displayName: "Old label",
            displayOrder: 0
        )
        let stateStore = TestAppStateStore(
            state: PersistedAppState(
                accounts: [account],
                snapshots: [:]
            )
        )
        let model = AppModel(
            stateStore: stateStore,
            credentialStore: TestCredentialStore(),
            clients: [],
            now: { self.reference }
        )
        await model.start()

        try await model.renameAccount(
            id: account.id,
            displayName: "  Work Codex  "
        )

        #expect(model.accounts[0].account.displayName == "Work Codex")
        #expect(
            await stateStore.state.accounts[0].displayName
                == "Work Codex"
        )
    }

    @Test
    func reorderChangesOnlyTheRequestedProviderStack() async throws {
        let claude = SubscriptionAccount(
            provider: .claude,
            displayName: "Claude",
            displayOrder: 0
        )
        let work = SubscriptionAccount(
            provider: .codex,
            displayName: "Work",
            displayOrder: 0
        )
        let personal = SubscriptionAccount(
            provider: .codex,
            displayName: "Personal",
            displayOrder: 1
        )
        let stateStore = TestAppStateStore(
            state: PersistedAppState(
                accounts: [personal, claude, work],
                snapshots: [:]
            )
        )
        let model = AppModel(
            stateStore: stateStore,
            credentialStore: TestCredentialStore(),
            clients: [],
            now: { self.reference }
        )
        await model.start()

        try await model.reorderAccounts(
            provider: .codex,
            orderedIDs: [personal.id, work.id]
        )

        #expect(
            model.accounts.map(\.id)
                == [claude.id, personal.id, work.id]
        )
        let saved = await stateStore.state.accounts
        #expect(
            saved.first(where: { $0.id == claude.id })?.displayOrder
                == 0
        )
        #expect(
            saved.first(where: { $0.id == personal.id })?.displayOrder
                == 0
        )
        #expect(
            saved.first(where: { $0.id == work.id })?.displayOrder
                == 1
        )
    }

    @Test
    func oneAccountAuthenticationFailureDoesNotBlockAnother() async {
        let missingCredential = SubscriptionAccount(
            provider: .codex,
            displayName: "Missing",
            displayOrder: 0
        )
        let connected = SubscriptionAccount(
            provider: .codex,
            displayName: "Connected",
            displayOrder: 1
        )
        let fresh = UsageSnapshot(
            accountID: connected.id,
            fetchedAt: reference,
            windows: []
        )
        let stateStore = TestAppStateStore(
            state: PersistedAppState(
                accounts: [missingCredential, connected],
                snapshots: [:]
            )
        )
        let credentials = TestCredentialStore(
            credentials: [
                connected.id: .codex(
                    OAuthCredential(
                        accessToken: "token",
                        accountID: "provider-account"
                    )
                ),
            ]
        )
        let provider = TestUsageProviderClient(
            provider: .codex,
            snapshots: [connected.id: fresh]
        )
        let model = AppModel(
            stateStore: stateStore,
            credentialStore: credentials,
            clients: [provider],
            now: { self.reference }
        )

        await model.start()

        #expect(
            model.accounts.first(where: {
                $0.id == missingCredential.id
            })?.error == .authenticationRequired
        )
        #expect(
            model.accounts.first(where: {
                $0.id == connected.id
            })?.snapshot == fresh
        )
        #expect(
            await provider.requestedAccountIDs
                == [connected.id]
        )
    }
}
