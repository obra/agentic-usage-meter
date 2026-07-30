import AppKit
import Foundation
import Testing
import UsageMeterCore

@testable import UsageMeterUI

@Suite
@MainActor
struct AppModelTests {
    private let reference = Date(
        timeIntervalSince1970: 2_000_000_000,
    )

    @Test
    func launchShowsCacheThenRefreshesEligibleAccount() async throws {
        let account = SubscriptionAccount(
            provider: .codex,
            displayName: "Work",
            displayOrder: 0,
        )
        let cached = UsageSnapshot(
            accountID: account.id,
            fetchedAt: reference.addingTimeInterval(-1000),
            windows: [
                makeTestWindow(
                    id: "cached",
                    resetAt: reference.addingTimeInterval(10000),
                    consumedFraction: 0.2,
                ),
            ],
        )
        let fresh = UsageSnapshot(
            accountID: account.id,
            fetchedAt: reference,
            windows: [
                makeTestWindow(
                    id: "fresh",
                    resetAt: reference.addingTimeInterval(20000),
                    consumedFraction: 0.3,
                ),
            ],
        )
        let stateStore = TestAppStateStore(
            state: PersistedAppState(
                accounts: [account],
                snapshots: [account.id: cached],
                refreshStates: [
                    account.id: AccountRefreshState(
                        lastRequestStartedAt:
                        reference.addingTimeInterval(-601),
                    ),
                ],
            ),
        )
        let credentials = TestCredentialStore(
            credentials: [
                account.id: .codex(
                    OAuthCredential(
                        accessToken: "token",
                        accountID: "provider-account",
                    ),
                ),
            ],
        )
        let provider = TestUsageProviderClient(
            provider: .codex,
            snapshots: [account.id: fresh],
        )
        let model = AppModel(
            stateStore: stateStore,
            credentialStore: credentials,
            clients: [provider],
            now: { reference },
        )

        await model.start()

        #expect(model.accounts.count == 1)
        #expect(model.accounts[0].snapshot == fresh)
        #expect(await provider.requestedAccountIDs == [account.id])
        #expect(
            await stateStore.state.snapshots[account.id]
                == fresh,
        )
    }

    @Test
    func launchDoesNotRefreshAccountInsideHardFloor() async {
        let account = SubscriptionAccount(
            provider: .kimi,
            displayName: "Kimi",
            displayOrder: 0,
        )
        let cached = UsageSnapshot(
            accountID: account.id,
            fetchedAt: reference.addingTimeInterval(-599),
            windows: [],
        )
        let stateStore = TestAppStateStore(
            state: PersistedAppState(
                accounts: [account],
                snapshots: [account.id: cached],
                refreshStates: [
                    account.id: AccountRefreshState(
                        lastRequestStartedAt:
                        reference.addingTimeInterval(-599),
                    ),
                ],
            ),
        )
        let provider = TestUsageProviderClient(
            provider: .kimi,
            snapshots: [:],
        )
        let model = AppModel(
            stateStore: stateStore,
            credentialStore: TestCredentialStore(),
            clients: [provider],
            now: { reference },
        )

        await model.start()

        #expect(model.accounts[0].snapshot == cached)
        #expect(await provider.requestedAccountIDs.isEmpty)
    }

    @Test
    func launchRechecksEligibleClaudeSessionMarkedForReconnect() async {
        let profileID = UUID()
        let organizationID = UUID()
        let account = SubscriptionAccount(
            provider: .claude,
            displayName: "Claude",
            displayOrder: 0,
            claudeProfileID: profileID,
            claudeOrganizationID: organizationID,
        )
        let cached = UsageSnapshot(
            accountID: account.id,
            fetchedAt: reference.addingTimeInterval(-1_000),
            windows: [],
        )
        let fresh = UsageSnapshot(
            accountID: account.id,
            fetchedAt: reference,
            windows: [],
        )
        let stateStore = TestAppStateStore(
            state: PersistedAppState(
                accounts: [account],
                snapshots: [account.id: cached],
                refreshStates: [
                    account.id: AccountRefreshState(
                        lastRequestStartedAt:
                        reference.addingTimeInterval(-600),
                        requiresReauthentication: true,
                    ),
                ],
            ),
        )
        let claudeClient = TestClaudeAccountUsageClient(
            snapshots: [account.id: fresh],
        )
        let model = AppModel(
            stateStore: stateStore,
            credentialStore: TestCredentialStore(),
            clients: [],
            claudeClient: claudeClient,
            now: { reference },
        )

        await model.start()

        #expect(await claudeClient.requestedAccountIDs == [account.id])
        #expect(model.accounts[0].snapshot == fresh)
        #expect(model.accounts[0].error == nil)
        #expect(
            await stateStore.state.refreshStates[account.id]?
                .requiresReauthentication == false,
        )
    }

    @Test
    func renamePersistsTrimmedAccountLabel() async throws {
        let account = SubscriptionAccount(
            provider: .codex,
            displayName: "Old label",
            displayOrder: 0,
        )
        let stateStore = TestAppStateStore(
            state: PersistedAppState(
                accounts: [account],
                snapshots: [:],
            ),
        )
        let model = AppModel(
            stateStore: stateStore,
            credentialStore: TestCredentialStore(),
            clients: [],
            now: { reference },
        )
        await model.start()

        try await model.renameAccount(
            id: account.id,
            displayName: "  Work Codex  ",
        )

        #expect(model.accounts[0].account.displayName == "Work Codex")
        #expect(
            await stateStore.state.accounts[0].displayName
                == "Work Codex",
        )
    }

    @Test
    func reorderChangesOnlyTheRequestedProviderStack() async throws {
        let claude = SubscriptionAccount(
            provider: .claude,
            displayName: "Claude",
            displayOrder: 0,
        )
        let work = SubscriptionAccount(
            provider: .codex,
            displayName: "Work",
            displayOrder: 0,
        )
        let personal = SubscriptionAccount(
            provider: .codex,
            displayName: "Personal",
            displayOrder: 1,
        )
        let stateStore = TestAppStateStore(
            state: PersistedAppState(
                accounts: [personal, claude, work],
                snapshots: [:],
            ),
        )
        let model = AppModel(
            stateStore: stateStore,
            credentialStore: TestCredentialStore(),
            clients: [],
            now: { reference },
        )
        await model.start()

        try await model.reorderAccounts(
            provider: .codex,
            orderedIDs: [personal.id, work.id],
        )

        #expect(
            model.accounts.map(\.id)
                == [claude.id, personal.id, work.id],
        )
        let saved = await stateStore.state.accounts
        #expect(
            saved.first(where: { $0.id == claude.id })?.displayOrder
                == 0,
        )
        #expect(
            saved.first(where: { $0.id == personal.id })?.displayOrder
                == 0,
        )
        #expect(
            saved.first(where: { $0.id == work.id })?.displayOrder
                == 1,
        )
    }

    @Test
    func oneAccountAuthenticationFailureDoesNotBlockAnother() async {
        let missingCredential = SubscriptionAccount(
            provider: .codex,
            displayName: "Missing",
            displayOrder: 0,
        )
        let connected = SubscriptionAccount(
            provider: .codex,
            displayName: "Connected",
            displayOrder: 1,
        )
        let fresh = UsageSnapshot(
            accountID: connected.id,
            fetchedAt: reference,
            windows: [],
        )
        let stateStore = TestAppStateStore(
            state: PersistedAppState(
                accounts: [missingCredential, connected],
                snapshots: [:],
            ),
        )
        let credentials = TestCredentialStore(
            credentials: [
                connected.id: .codex(
                    OAuthCredential(
                        accessToken: "token",
                        accountID: "provider-account",
                    ),
                ),
            ],
        )
        let provider = TestUsageProviderClient(
            provider: .codex,
            snapshots: [connected.id: fresh],
        )
        let model = AppModel(
            stateStore: stateStore,
            credentialStore: credentials,
            clients: [provider],
            now: { reference },
        )

        await model.start()

        #expect(
            model.accounts.first(where: {
                $0.id == missingCredential.id
            })?.error == .authenticationRequired,
        )
        #expect(
            model.accounts.first(where: {
                $0.id == connected.id
            })?.snapshot == fresh,
        )
        #expect(
            await provider.requestedAccountIDs
                == [connected.id],
        )
    }

    @Test
    func menuBarSummaryUsesTightestRemainingWindow() async throws {
        let account = SubscriptionAccount(
            provider: .codex,
            displayName: "Work",
            displayOrder: 0,
        )
        let weekly = try #require(
            UsageWindow(
                id: "weekly",
                kind: .weekly,
                duration: 604_800,
                resetAt: reference.addingTimeInterval(20000),
                consumedFraction: 0.66,
            ),
        )
        let short = try #require(
            UsageWindow(
                id: "short",
                kind: .short,
                duration: 18000,
                resetAt: reference.addingTimeInterval(10000),
                consumedFraction: 0.42,
            ),
        )
        let model = AppModel(
            stateStore: TestAppStateStore(
                state: PersistedAppState(
                    accounts: [account],
                    snapshots: [
                        account.id: UsageSnapshot(
                            accountID: account.id,
                            fetchedAt: reference,
                            windows: [short, weekly],
                        ),
                    ],
                    refreshStates: [
                        account.id: AccountRefreshState(
                            lastRequestStartedAt: reference,
                        ),
                    ],
                ),
            ),
            credentialStore: TestCredentialStore(),
            clients: [],
            now: { reference },
        )

        await model.start()

        #expect(model.menuBarSummary.text == "34%")
        #expect(model.menuBarSummary.systemImage == "gauge.with.needle")
    }

    @Test
    func menuBarSummaryIsNeutralWithoutUsageData() async {
        let model = AppModel(
            stateStore: TestAppStateStore(state: .empty),
            credentialStore: TestCredentialStore(),
            clients: [],
            now: { reference },
        )

        await model.start()

        #expect(model.menuBarSummary.text == nil)
        #expect(model.menuBarSummary.systemImage == "gauge.with.needle")
    }

    @Test
    func sampleDataStateRemainsVisibleToTheUI() {
        let model = AppModel(
            stateStore: TestAppStateStore(state: .empty),
            credentialStore: TestCredentialStore(),
            clients: [],
            isSampleData: true,
            now: { reference },
        )

        #expect(model.isSampleData)
    }

    @Test
    func floatingWidgetPreferenceAndPlacementPersist() async throws {
        let stateStore = TestAppStateStore(state: .empty)
        let model = AppModel(
            stateStore: stateStore,
            credentialStore: TestCredentialStore(),
            clients: [],
            now: { reference },
        )
        await model.start()
        let placement = FloatingWidgetPlacement(
            x: 120,
            y: 240,
            width: 520,
            height: 360,
        )

        try await model.setFloatingWidgetVisible(true)
        try await model.setFloatingWidgetPlacement(placement)

        #expect(model.isFloatingWidgetVisible)
        #expect(model.floatingWidgetPlacement == placement)
        #expect(await stateStore.state.isFloatingWidgetVisible)
        #expect(
            await stateStore.state.floatingWidgetPlacement
                == placement,
        )
    }

    @Test
    func floatingWidgetOpensAtItsIntendedSize() async throws {
        let accounts = [
            SubscriptionAccount(
                provider: .claude,
                displayName: "Work",
                displayOrder: 0,
            ),
            SubscriptionAccount(
                provider: .claude,
                displayName: "Personal",
                displayOrder: 1,
            ),
            SubscriptionAccount(
                provider: .codex,
                displayName: "Work",
                displayOrder: 0,
            ),
            SubscriptionAccount(
                provider: .codex,
                displayName: "Personal",
                displayOrder: 1,
            ),
            SubscriptionAccount(
                provider: .kimi,
                displayName: "Kimi",
                displayOrder: 0,
            ),
        ]
        var snapshots: [UUID: UsageSnapshot] = [:]
        for (index, account) in accounts.enumerated() {
            let weekly = try #require(
                UsageWindow(
                    id: "weekly",
                    kind: .weekly,
                    duration: 604_800,
                    resetAt: reference.addingTimeInterval(
                        Double(180_000 + index * 72000),
                    ),
                    consumedFraction: 0.31,
                ),
            )
            var windows = [weekly]
            if account.provider == .claude {
                windows.insert(
                    try #require(
                        UsageWindow(
                            id: "short",
                            kind: .short,
                            duration: 18000,
                            resetAt: reference.addingTimeInterval(
                                Double(3000 + index * 1500),
                            ),
                            consumedFraction: 0.22,
                        ),
                    ),
                    at: 0,
                )
            }
            snapshots[account.id] = UsageSnapshot(
                accountID: account.id,
                fetchedAt: reference,
                windows: windows,
            )
        }
        let stateStore = TestAppStateStore(
            state: PersistedAppState(
                accounts: accounts,
                snapshots: snapshots,
                refreshStates: Dictionary(
                    uniqueKeysWithValues: accounts.map {
                        (
                            $0.id,
                            AccountRefreshState(
                                lastRequestStartedAt: reference,
                            ),
                        )
                    },
                ),
                isFloatingWidgetVisible: true,
            ),
        )
        let model = AppModel(
            stateStore: stateStore,
            credentialStore: TestCredentialStore(),
            clients: [],
            now: { reference },
        )
        await model.start()
        let existingWindows = Set(
            NSApplication.shared.windows.map(ObjectIdentifier.init),
        )
        let controller = FloatingWidgetController(model: model)

        controller.synchronize()

        let panel = try #require(
            NSApplication.shared.windows.first {
                !existingWindows.contains(ObjectIdentifier($0))
                    && $0.title == "Agentic Usage"
            },
        )
        let screen = try #require(panel.screen)
        #expect(panel.frame.width == 520)
        #expect(panel.frame.height > 360)
        #expect(
            panel.frame.height
                <= screen.visibleFrame.height,
        )
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.floatingWidgetPlacement == nil)

        try await model.setFloatingWidgetVisible(false)
        controller.synchronize()
    }

    @Test
    func launchRefreshesClaudeFromItsIsolatedProfile() async {
        let account = SubscriptionAccount(
            provider: .claude,
            displayName: "Claude",
            displayOrder: 0,
            claudeProfileID: UUID(),
            claudeOrganizationID: UUID(),
        )
        let fresh = UsageSnapshot(
            accountID: account.id,
            fetchedAt: reference,
            windows: [],
        )
        let claudeClient = TestClaudeAccountUsageClient(
            snapshots: [account.id: fresh],
        )
        let model = AppModel(
            stateStore: TestAppStateStore(
                state: PersistedAppState(
                    accounts: [account],
                    snapshots: [:],
                ),
            ),
            credentialStore: TestCredentialStore(),
            clients: [],
            claudeClient: claudeClient,
            now: { reference },
        )

        await model.start()

        #expect(model.accounts[0].snapshot == fresh)
        #expect(
            await claudeClient.requestedAccountIDs
                == [account.id],
        )
    }
}
