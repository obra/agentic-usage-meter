import AppKit
import Foundation
import SwiftUI
import Testing
import UsageMeterCore

@testable import AgenticUsageMeter
@testable import UsageMeterUI

@Suite
@MainActor
struct AppModelTests {
    private let reference = Date(
        timeIntervalSince1970: 2_000_000_000,
    )

    @Test
    func refreshUsesTheAccountsAdapterWithoutProviderBranch() async {
        let account = SubscriptionAccount(
            provider: .minimax,
            displayName: "MiniMax",
            displayOrder: 0,
        )
        let snapshot = UsageSnapshot(
            accountID: account.id,
            fetchedAt: reference,
            windows: [],
        )
        let adapter = TestProviderAccountAdapter(
            provider: .minimax,
            result: .success(snapshot),
        )
        let model = AppModel(
            stateStore: TestAppStateStore(
                state: PersistedAppState(
                    accounts: [account],
                    snapshots: [:],
                ),
            ),
            credentialStore: TestCredentialStore(),
            adapters: [adapter],
            now: { self.reference },
        )

        await model.start()

        #expect(await adapter.fetchedAccountIDs == [account.id])
        #expect(model.accounts.first?.snapshot == snapshot)
    }

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
            adapters: [
                CredentialUsageAdapter(
                    provider: .codex,
                    credentialStore: credentials,
                    client: provider
                ),
            ],
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
        let credentials = TestCredentialStore()
        let model = AppModel(
            stateStore: stateStore,
            credentialStore: credentials,
            adapters: [
                CredentialUsageAdapter(
                    provider: .kimi,
                    credentialStore: credentials,
                    client: provider
                ),
            ],
            now: { reference },
        )

        await model.start()

        #expect(model.accounts[0].snapshot == cached)
        #expect(await provider.requestedAccountIDs.isEmpty)
    }

    @Test
    func automaticRefreshUsesReleasePolicy() async {
        let result = await automaticRefreshResult(
            refreshPolicy: .release,
        )

        #expect(result.requestCount == 2)
        #expect(result.interval == 600)
    }

    @Test
    func automaticRefreshUsesDevelopmentPolicy() async {
        let result = await automaticRefreshResult(
            refreshPolicy: .development,
        )

        #expect(result.requestCount == 2)
        #expect(result.interval == 60)
    }

    private func automaticRefreshResult(
        refreshPolicy: RefreshPolicy,
    ) async -> (requestCount: Int, interval: TimeInterval?) {
        let account = SubscriptionAccount(
            provider: .codex,
            displayName: "Work",
            displayOrder: 0,
        )
        let snapshot = UsageSnapshot(
            accountID: account.id,
            fetchedAt: reference,
            windows: [
                makeTestWindow(
                    id: "weekly",
                    resetAt: reference.addingTimeInterval(10_000),
                    consumedFraction: 0.2,
                ),
            ],
        )
        let provider = TestUsageProviderClient(
            provider: .codex,
            snapshots: [account.id: snapshot],
        )
        let clock = TestMutableDate(reference)
        let sleeper = TestAutomaticRefreshSleeper(clock: clock)
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
            stateStore: TestAppStateStore(
                state: PersistedAppState(
                    accounts: [account],
                    snapshots: [:],
                    refreshStates: [
                        account.id: AccountRefreshState(
                            lastRequestStartedAt:
                                reference.addingTimeInterval(
                                    -refreshPolicy.minimumProviderInterval,
                                ),
                        ),
                    ],
                ),
            ),
            credentialStore: credentials,
            adapters: [
                CredentialUsageAdapter(
                    provider: .codex,
                    credentialStore: credentials,
                    client: provider
                ),
            ],
            refreshPolicy: refreshPolicy,
            now: { clock.current },
        )
        await model.start()

        await model.runAutomaticRefresh { interval in
            try await sleeper.sleep(interval: interval)
        }

        return (
            requestCount: await provider.requestedAccountIDs.count,
            interval: await sleeper.intervals.first,
        )
    }

    @Test
    func wakeRefreshStillObservesTheTenMinuteFloor() async {
        let account = SubscriptionAccount(
            provider: .minimax,
            displayName: "MiniMax",
            displayOrder: 0,
        )
        let initialTime = reference
        let clock = TestMutableDate(initialTime)
        let adapter = TestProviderAccountAdapter(
            provider: .minimax,
            result: .success(
                UsageSnapshot(
                    accountID: account.id,
                    fetchedAt: initialTime.addingTimeInterval(60),
                    windows: [],
                )
            ),
        )
        let model = AppModel(
            stateStore: TestAppStateStore(
                state: PersistedAppState(
                    accounts: [account],
                    snapshots: [:],
                    refreshStates: [
                        account.id: AccountRefreshState(
                            lastRequestStartedAt:
                                initialTime.addingTimeInterval(-540),
                        ),
                    ],
                )
            ),
            credentialStore: TestCredentialStore(),
            adapters: [adapter],
            now: { clock.current },
        )
        await model.start()

        await model.refreshAfterWake()
        #expect(await adapter.fetchedAccountIDs.isEmpty)

        clock.advance(by: 60)
        await model.refreshAfterWake()

        #expect(await adapter.fetchedAccountIDs == [account.id])
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
            adapters: [claudeClient],
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
    func launchRefreshesKimiCredentialInsteadOfRequiringReconnect()
        async throws
    {
        let account = SubscriptionAccount(
            provider: .kimi,
            displayName: "Kimi",
            displayOrder: 0,
        )
        let cached = UsageSnapshot(
            accountID: account.id,
            fetchedAt: reference.addingTimeInterval(-1_000),
            windows: [],
        )
        let fresh = UsageSnapshot(
            accountID: account.id,
            fetchedAt: reference,
            windows: [
                makeTestWindow(
                    id: "weekly",
                    resetAt: reference.addingTimeInterval(10_000),
                    consumedFraction: 0.2,
                ),
            ],
        )
        let expired = OAuthCredential(
            accessToken: "expired",
            refreshToken: "refresh",
            expiresAt: reference.addingTimeInterval(-1),
        )
        let replacement = OAuthCredential(
            accessToken: "replacement",
            refreshToken: "rotated-refresh",
            expiresAt: reference.addingTimeInterval(3_600),
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
        let credentialStore = TestCredentialStore(
            credentials: [account.id: .kimi(expired)],
        )
        let provider = TestUsageProviderClient(
            provider: .kimi,
            snapshots: [account.id: fresh],
        )
        let refreshRecorder = TestCredentialRefreshRecorder(
            replacement: .kimi(replacement),
        )
        let model = AppModel(
            stateStore: stateStore,
            credentialStore: credentialStore,
            adapters: [
                CredentialUsageAdapter(
                    provider: .kimi,
                    credentialStore: credentialStore,
                    client: provider,
                    refreshCredential: { accountID, credential in
                    try await refreshRecorder.refresh(
                        accountID: accountID,
                        credential: credential,
                    )
                    }
                ),
            ],
            now: { self.reference },
        )

        await model.start()

        #expect(model.accounts[0].snapshot == fresh)
        #expect(model.accounts[0].error == nil)
        #expect(
            await refreshRecorder.requests
                == [
                    CredentialRefreshRequest(
                        accountID: account.id,
                        credential: .kimi(expired),
                    ),
                ],
        )
        #expect(
            await credentialStore.loadCredential(for: account.id)
                == .kimi(replacement),
        )
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
            adapters: [],
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
            adapters: [],
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
            adapters: [
                CredentialUsageAdapter(
                    provider: .codex,
                    credentialStore: credentials,
                    client: provider
                ),
            ],
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
            adapters: [],
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
            adapters: [],
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
            adapters: [],
            isSampleData: true,
            now: { reference },
        )

        #expect(model.isSampleData)
    }

    @Test
    func sampleDataIncludesKimiFiveHourWindow() throws {
        let state = AppEnvironment.sampleState(showWidget: false)
        let account = try #require(
            state.accounts.first { $0.provider == .kimi },
        )
        let snapshot = try #require(state.snapshots[account.id])
        let short = try #require(
            snapshot.windows.first { $0.kind == .short },
        )

        #expect(short.duration == 18_000)
    }

    @Test
    func sampleDataContainsNoAuthenticatedIdentitiesOrOrganizations() {
        let state = AppEnvironment.sampleState(showWidget: false)
        let allowedNames = Set([
            "Work",
            "Personal",
            "Kimi",
            "Factory",
        ])

        #expect(state.accounts.allSatisfy {
            allowedNames.contains($0.displayName)
        })
        #expect(state.accounts.allSatisfy {
            $0.authenticatedIdentity == nil
                && $0.claudeProfileID == nil
                && $0.claudeOrganizationID == nil
        })
    }

    @Test
    func floatingWidgetPreferenceAndPlacementPersist() async throws {
        let stateStore = TestAppStateStore(state: .empty)
        let model = AppModel(
            stateStore: stateStore,
            credentialStore: TestCredentialStore(),
            adapters: [],
            now: { reference },
        )
        await model.start()
        let placement = FloatingWidgetPlacement(
            x: 120,
            y: 240,
            width: 460,
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
    func collapsedUsageSectionsLoadAndPersist() async throws {
        let stateStore = TestAppStateStore(
            state: PersistedAppState(
                accounts: [],
                snapshots: [:],
                collapsedUsageSections: [.weekly],
            ),
        )
        let model = AppModel(
            stateStore: stateStore,
            credentialStore: TestCredentialStore(),
            adapters: [],
            now: { self.reference },
        )

        await model.start()

        #expect(model.collapsedUsageSections == [.weekly])

        try await model.toggleUsageSection(.short)

        #expect(
            model.collapsedUsageSections
                == [.short, .weekly],
        )
        #expect(
            await stateStore.state.collapsedUsageSections
                == [.short, .weekly],
        )
    }

    @Test
    func rejectedCollapseSaveRollsBackObservableState() async {
        let stateStore = TestAppStateStore(
            state: .empty,
            saveError: .saveRejected,
        )
        let model = AppModel(
            stateStore: stateStore,
            credentialStore: TestCredentialStore(),
            adapters: [],
            now: { self.reference },
        )

        await model.start()

        await #expect(
            throws: TestAppStateStoreError.saveRejected,
        ) {
            try await model.toggleUsageSection(.weekly)
        }

        #expect(model.collapsedUsageSections.isEmpty)
        #expect(
            await stateStore.state.collapsedUsageSections
                .isEmpty,
        )
    }

    @Test
    func floatingWidgetOpensAtItsIntendedSize() async throws {
        let stateStore = TestAppStateStore(
            state: try populatedState(
                isFloatingWidgetVisible: true,
            ),
        )
        let model = AppModel(
            stateStore: stateStore,
            credentialStore: TestCredentialStore(),
            adapters: [],
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
        #expect(panel.frame.width == 411)
        #expect(panel.frame.height >= 240)
        #expect(panel.frame.height < 360)
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
    func floatingWidgetShrinksWhenASectionCollapses() async throws {
        let stateStore = TestAppStateStore(
            state: try populatedState(
                isFloatingWidgetVisible: true,
            ),
        )
        let model = AppModel(
            stateStore: stateStore,
            credentialStore: TestCredentialStore(),
            adapters: [],
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
        let expandedHeight = panel.frame.height
        let expandedWidth = panel.frame.width

        try await model.toggleUsageSection(.weekly)
        try await Task.sleep(for: .milliseconds(300))

        #expect(panel.frame.height < expandedHeight)
        #expect(panel.frame.width == expandedWidth)
        let collapsedHeight = panel.frame.height

        try await model.toggleUsageSection(.weekly)
        try await Task.sleep(for: .milliseconds(300))

        #expect(panel.frame.height > collapsedHeight)
        #expect(panel.frame.width == expandedWidth)

        try await model.setFloatingWidgetVisible(false)
        controller.synchronize()
    }

    @Test
    func menuBarContentExpandsWhenAccountsFinishLoading() async throws {
        let model = AppModel(
            stateStore: TestAppStateStore(
                state: try populatedState(),
            ),
            credentialStore: TestCredentialStore(),
            adapters: [],
            now: { self.reference },
        )
        let emptyHostingView = NSHostingView(
            rootView: MenuBarContentView(model: model),
        )
        let emptyHeight = emptyHostingView.fittingSize.height

        await model.start()
        var renderedHeight: CGFloat = 0
        let hostingView = NSHostingView(
            rootView: MenuBarContentView(model: model)
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    renderedHeight = $0
                }
                .frame(height: emptyHeight),
        )
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: 411,
            height: emptyHeight,
        )
        hostingView.layoutSubtreeIfNeeded()
        await Task.yield()

        #expect(renderedHeight > emptyHeight)
    }

    @Test
    func collapsedTimelineHasSmallerIntrinsicHeight() throws {
        let accounts = try (0 ..< 5).map { index in
            let account = SubscriptionAccount(
                provider: .claude,
                displayName: "Account \(index + 1)",
                displayOrder: index,
            )
            let window = try #require(
                UsageWindow(
                    id: "short-\(index)",
                    kind: .short,
                    duration: 18_000,
                    resetAt:
                        reference.addingTimeInterval(18_000),
                    consumedFraction: Double(index) / 10,
                ),
            )
            return AccountViewState(
                account: account,
                snapshot: UsageSnapshot(
                    accountID: account.id,
                    fetchedAt: reference,
                    windows: [window],
                ),
            )
        }
        let expanded = NSHostingView(
            rootView: UsageTimelineView(
                accounts: accounts,
                now: reference,
            )
            .frame(width: UsageTimelineMetrics.naturalWidth),
        )
        let collapsed = NSHostingView(
            rootView: UsageTimelineView(
                accounts: accounts,
                now: reference,
                collapsedSections: [.short],
                onToggleSection: { _ in },
            )
            .frame(width: UsageTimelineMetrics.naturalWidth),
        )

        #expect(
            collapsed.fittingSize.height
                < expanded.fittingSize.height,
        )
    }

    @Test
    func weeklyCollapseDoesNotAnimateRowsIntoTheShelf() async throws {
        let model = AppModel(
            stateStore: TestAppStateStore(
                state: try populatedState(
                    isFloatingWidgetVisible: true,
                ),
            ),
            credentialStore: TestCredentialStore(),
            adapters: [],
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
        let contentView = try #require(panel.contentView)

        try await model.toggleUsageSection(.weekly)
        try await Task.sleep(for: .milliseconds(50))
        contentView.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        let transitionPixels = try renderedPixels(
            in: contentView,
        )

        try await Task.sleep(for: .milliseconds(200))
        contentView.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        let settledPixels = try renderedPixels(
            in: contentView,
        )

        #expect(
            pixelDifferenceFraction(
                transitionPixels,
                settledPixels,
            ) < 0.005,
        )

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
            adapters: [claudeClient],
            now: { reference },
        )

        await model.start()

        #expect(model.accounts[0].snapshot == fresh)
        #expect(
            await claudeClient.requestedAccountIDs
                == [account.id],
        )
    }

    private func populatedState(
        isFloatingWidgetVisible: Bool = false,
    ) throws -> PersistedAppState {
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
                        Double(180_000 + index * 72_000),
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
                            duration: 18_000,
                            resetAt: reference.addingTimeInterval(
                                Double(3_000 + index * 1_500),
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
        return PersistedAppState(
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
            isFloatingWidgetVisible: isFloatingWidgetVisible,
        )
    }

    private func renderedPixels(
        in view: NSView,
    ) throws -> Data {
        let bounds = view.bounds
        let representation = try #require(
            view.bitmapImageRepForCachingDisplay(in: bounds),
        )
        view.cacheDisplay(
            in: bounds,
            to: representation,
        )
        let bitmapData = try #require(representation.bitmapData)
        return Data(
            bytes: bitmapData,
            count:
                representation.bytesPerRow
                * representation.pixelsHigh,
        )
    }

    private func pixelDifferenceFraction(
        _ first: Data,
        _ second: Data,
    ) -> Double {
        guard first.count == second.count else {
            return 1
        }
        let differences = zip(first, second).count {
            $0 != $1
        }
        return Double(differences) / Double(first.count)
    }
}
