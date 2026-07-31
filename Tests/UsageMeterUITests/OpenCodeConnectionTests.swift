import Foundation
import Testing
import UsageMeterCore

@testable import UsageMeterUI

@Test
func openCodeLoginDetectorRequiresAnOpenCodeWorkspaceURL() {
    #expect(
        OpenCodeLoginDetector.workspaceID(
            in: URL(
                string:
                    "https://opencode.ai/workspace/wrk_personal/go",
            )!,
        ) == "wrk_personal",
    )
    #expect(
        OpenCodeLoginDetector.workspaceID(
            in: URL(
                string:
                    "https://console.opencode.ai/workspace/wrk_team/billing",
            )!,
        ) == "wrk_team",
    )
    #expect(
        OpenCodeLoginDetector.workspaceID(
            in: URL(string: "https://opencode.ai/workspace")!,
        ) == nil,
    )
    #expect(
        OpenCodeLoginDetector.workspaceID(
            in: URL(
                string:
                    "https://example.com/workspace/wrk_personal/go",
            )!,
        ) == nil,
    )
}

@Test
func openCodeLoginDetectorSelectsOnlyTheAccountCookie() throws {
    let auth = try #require(
        HTTPCookie(
            properties: [
                .name: "auth",
                .value: "account-session",
                .domain: ".opencode.ai",
                .path: "/",
            ],
        ),
    )
    let unrelated = try #require(
        HTTPCookie(
            properties: [
                .name: "theme",
                .value: "dark",
                .domain: "opencode.ai",
                .path: "/",
            ],
        ),
    )
    let foreign = try #require(
        HTTPCookie(
            properties: [
                .name: "auth",
                .value: "foreign-session",
                .domain: "example.com",
                .path: "/",
            ],
        ),
    )

    #expect(
        OpenCodeLoginDetector.authCookie(
            in: [unrelated, foreign, auth],
        ) == "account-session",
    )
}

@Test
@MainActor
func openCodeConnectionSavesItsSelectedWorkspace() async throws {
    let reference = Date(
        timeIntervalSince1970: 2_000_000_000,
    )
    let accountID = UUID()
    let credential = OpenCodeDashboardCredential(
        workspaceID: "wrk_personal",
        authCookie: "account-session",
    )
    let credentialStore = TestCredentialStore()
    let appModel = AppModel(
        stateStore: TestAppStateStore(state: .empty),
        credentialStore: credentialStore,
        adapters: [
            TestProviderAccountAdapter(
                provider: .openCodeGo,
                result: .success(
                    UsageSnapshot(
                        accountID: accountID,
                        fetchedAt: reference,
                        windows: [],
                    ),
                ),
            )
        ],
        now: { reference },
    )
    await appModel.start()
    let connection = OpenCodeConnectionModel(
        provider: .openCodeGo,
        appModel: appModel,
        accountID: accountID,
        authenticate: { credential },
        removeProfile: { _ in },
    )

    await connection.start()

    #expect(
        connection.phase
            == .readyToSave(
                workspaceID: "wrk_personal",
            ),
    )

    try await connection.save(
        displayName: "Personal Go",
    )

    #expect(connection.phase == .complete)
    #expect(
        appModel.accounts[0].account.authenticatedIdentity
            == "wrk_personal",
    )
    #expect(
        try await credentialStore.load(
            OpenCodeDashboardCredential.self,
            for: accountID,
        ) == credential,
    )
}

@Test
@MainActor
func openCodeConnectionBlocksDuplicateWorkspaceForOneProduct()
    async throws
{
    let existing = SubscriptionAccount(
        provider: .openCodeZen,
        displayName: "Existing Zen",
        authenticatedIdentity: "wrk_team",
        displayOrder: 0,
    )
    let credentialStore = TestCredentialStore()
    try await credentialStore.save(
        OpenCodeDashboardCredential(
            workspaceID: "wrk_team",
            authCookie: "old-session",
        ),
        for: existing.id,
    )
    let appModel = AppModel(
        stateStore: TestAppStateStore(
            state: PersistedAppState(
                accounts: [existing],
                snapshots: [:],
            ),
        ),
        credentialStore: credentialStore,
        adapters: [
            TestProviderAccountAdapter(
                provider: .openCodeZen,
            )
        ],
    )
    await appModel.start()
    let connection = OpenCodeConnectionModel(
        provider: .openCodeZen,
        appModel: appModel,
        authenticate: {
            OpenCodeDashboardCredential(
                workspaceID: "wrk_team",
                authCookie: "new-session",
            )
        },
        removeProfile: { _ in },
    )

    await connection.start()

    #expect(
        connection.phase
            == .duplicateIdentity(
                workspaceID: "wrk_team",
            ),
    )
    await #expect(
        throws:
            ProviderConnectionInputError
            .authorizationNotComplete,
    ) {
        try await connection.save(
            displayName: "Duplicate",
        )
    }
}

@Test
@MainActor
func goAndZenCanTrackTheSameWorkspace() async throws {
    let existing = SubscriptionAccount(
        provider: .openCodeZen,
        displayName: "Team Zen",
        authenticatedIdentity: "wrk_team",
        displayOrder: 0,
    )
    let credentialStore = TestCredentialStore()
    try await credentialStore.save(
        OpenCodeDashboardCredential(
            workspaceID: "wrk_team",
            authCookie: "zen-session",
        ),
        for: existing.id,
    )
    let appModel = AppModel(
        stateStore: TestAppStateStore(
            state: PersistedAppState(
                accounts: [existing],
                snapshots: [:],
            ),
        ),
        credentialStore: credentialStore,
        adapters: [
            TestProviderAccountAdapter(
                provider: .openCodeZen,
            ),
            TestProviderAccountAdapter(
                provider: .openCodeGo,
            ),
        ],
    )
    await appModel.start()
    let connection = OpenCodeConnectionModel(
        provider: .openCodeGo,
        appModel: appModel,
        authenticate: {
            OpenCodeDashboardCredential(
                workspaceID: "wrk_team",
                authCookie: "go-session",
            )
        },
        removeProfile: { _ in },
    )

    await connection.start()

    #expect(
        connection.phase
            == .readyToSave(
                workspaceID: "wrk_team",
            ),
    )
}

@Test
@MainActor
func cancellingNewOpenCodeAccountDeletesItsWebProfile()
    async
{
    let accountID = UUID()
    let removal = OpenCodeProfileRemovalRecorder()
    let appModel = AppModel(
        stateStore: TestAppStateStore(state: .empty),
        credentialStore: TestCredentialStore(),
        adapters: [
            TestProviderAccountAdapter(
                provider: .openCodeGo,
            )
        ],
    )
    await appModel.start()
    let connection = OpenCodeConnectionModel(
        provider: .openCodeGo,
        appModel: appModel,
        accountID: accountID,
        authenticate: {
            OpenCodeDashboardCredential(
                workspaceID: "wrk_personal",
                authCookie: "session",
            )
        },
        removeProfile: { profileID in
            removal.remove(profileID)
        },
    )

    await connection.start()
    await connection.cancel()

    #expect(removal.profileIDs == [accountID])
    #expect(appModel.accounts.isEmpty)
}

@Test
@MainActor
func removingOpenCodeAccountDeletesCredentialAndWebProfile()
    async throws
{
    let account = SubscriptionAccount(
        provider: .openCodeGo,
        displayName: "OpenCode",
        displayOrder: 0,
    )
    let base = TestProviderAccountAdapter(
        provider: .openCodeGo,
    )
    let removal = OpenCodeProfileRemovalRecorder()
    let adapter = OpenCodeWebAccountUsageClient(
        base: base,
        removeProfile: { profileID in
            removal.remove(profileID)
        },
    )

    try await adapter.removeAuthentication(
        for: account,
    )

    #expect(
        await base.removedAccountIDs
            == [account.id],
    )
    #expect(removal.profileIDs == [account.id])
}

@MainActor
private final class OpenCodeProfileRemovalRecorder {
    private(set) var profileIDs: [UUID] = []

    func remove(_ profileID: UUID) {
        profileIDs.append(profileID)
    }
}
