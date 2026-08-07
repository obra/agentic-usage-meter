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
        displayOrder: 0,
    )
    let stateStore = TestAppStateStore(
        state: PersistedAppState(
            accounts: [account],
            snapshots: [:],
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
    let model = AppModel(
        stateStore: stateStore,
        credentialStore: credentials,
        adapters: [
            CredentialUsageAdapter(
                provider: .codex,
                credentialStore: credentials,
                client: TestUsageProviderClient(
                    provider: .codex,
                    snapshots: [:]
                )
            ),
        ],
        now: { Date(timeIntervalSince1970: 2_000_000_000) },
    )
    await model.start()

    try await model.removeAccount(id: account.id)

    #expect(model.accounts.isEmpty)
    #expect(await credentials.loadCredential(for: account.id) == nil)
    #expect(await stateStore.state.accounts.isEmpty)
}

@Test
@MainActor
func removingAccountDelegatesAuthenticationCleanup() async throws {
    let account = SubscriptionAccount(
        provider: .minimax,
        displayName: "MiniMax",
        displayOrder: 0,
    )
    let adapter = TestProviderAccountAdapter(provider: .minimax)
    let model = AppModel(
        stateStore: TestAppStateStore(
            state: PersistedAppState(
                accounts: [account],
                snapshots: [:],
            ),
        ),
        credentialStore: TestCredentialStore(),
        adapters: [adapter],
        now: { Date(timeIntervalSince1970: 2_000_000_000) },
    )
    await model.start()

    try await model.removeAccount(id: account.id)

    #expect(await adapter.removedAccountIDs == [account.id])
}

@Test
@MainActor
func connectingAccountValidatesBeforePersisting() async throws {
    let reference = Date(timeIntervalSince1970: 2_000_000_000)
    let account = SubscriptionAccount(
        provider: .kimi,
        displayName: "Kimi",
        displayOrder: 0,
    )
    let snapshot = UsageSnapshot(
        accountID: account.id,
        fetchedAt: reference,
        windows: [
            makeTestWindow(
                id: "weekly",
                resetAt: reference.addingTimeInterval(10000),
                consumedFraction: 0.4,
            ),
        ],
    )
    let stateStore = TestAppStateStore(state: .empty)
    let credentials = TestCredentialStore()
    let provider = TestUsageProviderClient(
        provider: .kimi,
        snapshots: [account.id: snapshot],
    )
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
    let credential = ProviderCredential.kimi(
        OAuthCredential(
            accessToken: "access",
            refreshToken: "refresh",
        ),
    )

    try await model.connectAccount(
        account,
        credential: credential,
    )

    #expect(model.accounts.map(\.account) == [account])
    #expect(model.accounts.first?.snapshot == snapshot)
    #expect(await credentials.loadCredential(for: account.id) == credential)
    #expect(await stateStore.state.accounts == [account])
    #expect(await stateStore.state.snapshots[account.id] == snapshot)
}

@Test
@MainActor
func failedFirstUsageKeepsSuccessfulAuthenticationAndAccount() async throws {
    let reference = Date(timeIntervalSince1970: 2_000_000_000)
    let account = SubscriptionAccount(
        provider: .codex,
        displayName: "Work",
        displayOrder: 0,
    )
    let stateStore = TestAppStateStore(state: .empty)
    let credentials = TestCredentialStore()
    let adapter = TestProviderAccountAdapter(
        provider: .codex,
        result: .failure(ProviderClientError.temporaryFailure),
    )
    let model = AppModel(
        stateStore: stateStore,
        credentialStore: credentials,
        adapters: [adapter],
        now: { reference },
    )
    await model.start()
    let credential = ProviderCredential.codex(
        OAuthCredential(
            accessToken: "access",
            accountID: "provider-account",
        ),
    )

    try await model.connectAccount(account, credential: credential)

    #expect(model.accounts.map(\.account) == [account])
    #expect(model.accounts[0].snapshot == nil)
    #expect(model.accounts[0].error == .temporarilyUnavailable)
    #expect(await credentials.loadCredential(for: account.id) == credential)
    #expect(await stateStore.state.accounts == [account])
}

@Test
@MainActor
func inactiveSubscriptionIsReportedAfterConnection()
    async throws
{
    let account = SubscriptionAccount(
        provider: .openCodeGo,
        displayName: "OpenCode Go",
        displayOrder: 0
    )
    let model = AppModel(
        stateStore: TestAppStateStore(
            state: .empty
        ),
        credentialStore: TestCredentialStore(),
        adapters: [
            TestProviderAccountAdapter(
                provider: .openCodeGo,
                result: .failure(
                    ProviderClientError
                        .subscriptionRequired
                )
            )
        ]
    )
    await model.start()

    try await model.connectAccount(
        account,
        credential:
            OpenCodeDashboardCredential(
                workspaceID: "wrk_personal",
                authCookie: "session"
            )
    )

    #expect(
        model.accounts.first?.error
            == .subscriptionRequired
    )
}

@Test
@MainActor
func reconnectValidatesReplacementBeforeClearingError() async throws {
    let reference = Date(timeIntervalSince1970: 2_000_000_000)
    let account = SubscriptionAccount(
        provider: .codex,
        displayName: "Work",
        displayOrder: 0,
    )
    let fresh = UsageSnapshot(
        accountID: account.id,
        fetchedAt: reference,
        windows: [],
    )
    let stateStore = TestAppStateStore(
        state: PersistedAppState(
            accounts: [account],
            snapshots: [:],
            refreshStates: [
                account.id: AccountRefreshState(
                    requiresReauthentication: true,
                ),
            ],
        ),
    )
    let credentials = TestCredentialStore()
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
    #expect(model.accounts[0].error == .authenticationRequired)
    let replacement = ProviderCredential.codex(
        OAuthCredential(
            accessToken: "replacement",
            accountID: "provider-account",
        ),
    )

    try await model.reconnectAccount(
        id: account.id,
        credential: replacement,
    )

    #expect(model.accounts[0].error == nil)
    #expect(model.accounts[0].snapshot == fresh)
    #expect(await credentials.loadCredential(for: account.id) == replacement)
    #expect(
        await stateStore.state.refreshStates[account.id]?
            .requiresReauthentication == false,
    )
}

@Test
@MainActor
func claudeConnectionPersistsProfileAndRemovalDeletesIt() async throws {
    let reference = Date(timeIntervalSince1970: 2_000_000_000)
    let profileID = UUID()
    let organizationID = UUID()
    let account = SubscriptionAccount(
        provider: .claude,
        displayName: "Work Claude",
        authenticatedIdentity: "Work organization",
        displayOrder: 0,
        claudeProfileID: profileID,
        claudeOrganizationID: organizationID,
    )
    let snapshot = UsageSnapshot(
        accountID: account.id,
        fetchedAt: reference,
        windows: [],
    )
    let stateStore = TestAppStateStore(state: .empty)
    let credentials = TestCredentialStore()
    let profileRemover = TestClaudeProfileRemover()
    let model = AppModel(
        stateStore: stateStore,
        credentialStore: credentials,
        adapters: [profileRemover],
        now: { reference },
    )
    await model.start()

    try await model.connectClaudeAccount(
        account,
        snapshot: snapshot,
    )

    #expect(model.accounts.map(\.account) == [account])
    #expect(await credentials.loadCredential(for: account.id) == nil)

    try await model.removeAccount(id: account.id)

    #expect(profileRemover.removedProfileIDs == [profileID])
    #expect(model.accounts.isEmpty)
    #expect(await stateStore.state.accounts.isEmpty)
}

@Test
@MainActor
func claudeConnectionCanPersistBeforeInitialUsageSucceeds() async throws {
    let reference = Date(timeIntervalSince1970: 2_000_000_000)
    let account = SubscriptionAccount(
        provider: .claude,
        displayName: "Work Claude",
        authenticatedIdentity: "Work organization",
        displayOrder: 0,
        claudeProfileID: UUID(),
        claudeOrganizationID: UUID(),
    )
    let stateStore = TestAppStateStore(state: .empty)
    let adapter = TestProviderAccountAdapter(provider: .claude)
    let model = AppModel(
        stateStore: stateStore,
        credentialStore: TestCredentialStore(),
        adapters: [adapter],
        now: { reference },
    )
    await model.start()

    try await model.connectClaudeAccount(account)

    #expect(model.accounts.map(\.account) == [account])
    #expect(model.accounts[0].snapshot == nil)
    #expect(model.accounts[0].error == .temporarilyUnavailable)
    #expect(await stateStore.state.accounts == [account])
}

@Test
@MainActor
func reconnectingClaudeReplacesItsIsolatedBrowserProfile() async throws {
    let reference = Date(timeIntervalSince1970: 2_000_000_000)
    let oldProfileID = UUID()
    let newProfileID = UUID()
    let account = SubscriptionAccount(
        provider: .claude,
        displayName: "Work Claude",
        authenticatedIdentity: "Old organization",
        displayOrder: 0,
        claudeProfileID: oldProfileID,
        claudeOrganizationID: UUID(),
    )
    let replacement = SubscriptionAccount(
        id: account.id,
        provider: .claude,
        displayName: account.displayName,
        authenticatedIdentity: "New organization",
        displayOrder: account.displayOrder,
        claudeProfileID: newProfileID,
        claudeOrganizationID: UUID(),
    )
    let snapshot = UsageSnapshot(
        accountID: account.id,
        fetchedAt: reference,
        windows: [],
    )
    let stateStore = TestAppStateStore(
        state: PersistedAppState(
            accounts: [account],
            snapshots: [:],
            refreshStates: [
                account.id: AccountRefreshState(
                    requiresReauthentication: true,
                ),
            ],
        ),
    )
    let profileRemover = TestClaudeProfileRemover()
    let model = AppModel(
        stateStore: stateStore,
        credentialStore: TestCredentialStore(),
        adapters: [profileRemover],
        now: { reference },
    )
    await model.start()

    try await model.reconnectClaudeAccount(
        id: account.id,
        replacement: replacement,
        snapshot: snapshot,
    )

    #expect(profileRemover.removedProfileIDs == [oldProfileID])
    #expect(model.accounts[0].account == replacement)
    #expect(model.accounts[0].snapshot == snapshot)
    #expect(model.accounts[0].error == nil)
    #expect(await stateStore.state.accounts == [replacement])
}

@Test
@MainActor
func codexConnectionConfirmsIdentityBeforeSavingLabel() async throws {
    let reference = Date(timeIntervalSince1970: 2_000_000_000)
    let accountID = UUID()
    let snapshot = UsageSnapshot(
        accountID: accountID,
        fetchedAt: reference,
        windows: [],
    )
    let credentials = TestCredentialStore()
    let appModel = AppModel(
        stateStore: TestAppStateStore(state: .empty),
        credentialStore: credentials,
        adapters: [
            CredentialUsageAdapter(
                provider: .codex,
                credentialStore: credentials,
                client: TestUsageProviderClient(
                    provider: .codex,
                    snapshots: [accountID: snapshot]
                )
            ),
        ],
        now: { reference },
    )
    await appModel.start()
    let result = CodexOAuthResult(
        credential: OAuthCredential(
            accessToken: "access",
            refreshToken: "refresh",
            accountID: "provider-account",
        ),
        identity: CodexOAuthIdentity(
            email: "work@example.com",
            plan: "pro",
            userID: "user",
            accountID: "provider-account",
        ),
    )
    let connection = CodexConnectionModel(
        appModel: appModel,
        accountID: accountID,
        authenticate: { result },
    )

    await connection.start()

    #expect(
        connection.phase
            == .confirmingIdentity(
                email: "work@example.com",
                plan: "pro",
            ),
    )

    try await connection.save(displayName: "Work Codex")

    #expect(connection.phase == .complete)
    #expect(appModel.accounts[0].account.displayName == "Work Codex")
    #expect(
        appModel.accounts[0].account.authenticatedIdentity
            == "work@example.com",
    )
    #expect(
        await credentials.loadCredential(for: accountID)
            == .codex(result.credential),
    )
}

@Test
@MainActor
func codexConnectionBlocksAnAlreadyConnectedIdentity() async throws {
    let reference = Date(timeIntervalSince1970: 2_000_000_000)
    let existingAccount = SubscriptionAccount(
        provider: .codex,
        displayName: "Work Codex",
        authenticatedIdentity: "work@example.com",
        displayOrder: 0,
    )
    let credentials = TestCredentialStore(
        credentials: [
            existingAccount.id: .codex(
                OAuthCredential(
                    accessToken: "existing",
                    refreshToken: "refresh",
                    accountID: "provider-account",
                ),
            ),
        ],
    )
    let provider = TestUsageProviderClient(
        provider: .codex,
        snapshots: [
            existingAccount.id: UsageSnapshot(
                accountID: existingAccount.id,
                fetchedAt: reference,
                windows: [],
            ),
        ],
    )
    let appModel = AppModel(
        stateStore: TestAppStateStore(
            state: PersistedAppState(
                accounts: [existingAccount],
                snapshots: [:],
                refreshStates: [
                    existingAccount.id: AccountRefreshState(
                        lastRequestStartedAt: reference,
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
        now: { reference },
    )
    await appModel.start()
    let connection = CodexConnectionModel(
        appModel: appModel,
        authenticate: {
            CodexOAuthResult(
                credential: OAuthCredential(
                    accessToken: "replacement",
                    refreshToken: "replacement-refresh",
                    accountID: "provider-account",
                ),
                identity: CodexOAuthIdentity(
                    email: "work@example.com",
                    plan: "pro",
                    userID: "user",
                    accountID: "provider-account",
                ),
            )
        },
    )

    await connection.start()

    #expect(
        connection.phase
            == .duplicateIdentity(email: "work@example.com"),
    )
    await #expect(
        throws: ProviderConnectionInputError
            .authorizationNotComplete,
    ) {
        try await connection.save(displayName: "Duplicate")
    }
    #expect(appModel.accounts.count == 1)
}

@Test
@MainActor
func kimiConnectionPublishesDevicePromptBeforeSaving() async throws {
    let reference = Date(timeIntervalSince1970: 2_000_000_000)
    let accountID = UUID()
    let prompt = KimiAuthorizationPrompt(
        verificationURL: URL(
            string: "https://www.kimi.com/code/authorize_device?user_code=ABCD",
        )!,
        userCode: "ABCD",
        expiresAt: reference.addingTimeInterval(600),
    )
    let credential = OAuthCredential(
        accessToken: "access",
        refreshToken: "refresh",
    )
    let credentials = TestCredentialStore()
    let appModel = AppModel(
        stateStore: TestAppStateStore(state: .empty),
        credentialStore: credentials,
        adapters: [
            CredentialUsageAdapter(
                provider: .kimi,
                credentialStore: credentials,
                client: TestUsageProviderClient(
                    provider: .kimi,
                    snapshots: [
                        accountID: UsageSnapshot(
                            accountID: accountID,
                            fetchedAt: reference,
                            windows: []
                        ),
                    ]
                )
            ),
        ],
        now: { reference },
    )
    await appModel.start()
    let connection = KimiConnectionModel(
        appModel: appModel,
        accountID: accountID,
        authenticate: { onPrompt in
            await onPrompt(prompt)
            return credential
        },
    )

    await connection.start()

    #expect(connection.prompt == prompt)
    #expect(connection.phase == .readyToSave)

    try await connection.save(displayName: "Personal Kimi")

    #expect(connection.phase == .complete)
    #expect(appModel.accounts[0].account.displayName == "Personal Kimi")
    #expect(
        await credentials.loadCredential(for: accountID)
            == .kimi(credential),
    )
}

@Test
@MainActor
func claudeConnectionQualifiesProfileBeforeSaving() async throws {
    let reference = Date(timeIntervalSince1970: 2_000_000_000)
    let accountID = UUID()
    let profileID = UUID()
    let organizationID = UUID()
    let snapshot = UsageSnapshot(
        accountID: accountID,
        fetchedAt: reference,
        windows: [],
    )
    let appModel = AppModel(
        stateStore: TestAppStateStore(state: .empty),
        credentialStore: TestCredentialStore(),
        adapters: [TestClaudeProfileRemover()],
        now: { reference },
    )
    await appModel.start()
    let connection = ClaudeConnectionModel(
        appModel: appModel,
        accountID: accountID,
        profileID: profileID,
        qualify: {
            ClaudeQualifiedConnection(
                organizationID: organizationID,
                organizationName: "Work organization",
                organizationCount: 2,
                snapshot: snapshot,
            )
        },
        removeProfile: { _ in },
    )

    await connection.start()

    #expect(
        connection.phase
            == .readyToSave(
                organizationName: "Work organization",
                organizationCount: 2,
            ),
    )

    try await connection.save(displayName: "Work Claude")

    #expect(connection.phase == .complete)
    #expect(
        appModel.accounts[0].account.claudeProfileID
            == profileID,
    )
    #expect(
        appModel.accounts[0].account.claudeOrganizationID
            == organizationID,
    )
}

@Test
@MainActor
func cancellingClaudeConnectionDeletesProvisionalProfile() async {
    let profileID = UUID()
    let profileRemover = TestClaudeProfileRemover()
    let appModel = AppModel(
        stateStore: TestAppStateStore(state: .empty),
        credentialStore: TestCredentialStore(),
        adapters: [],
    )
    await appModel.start()
    let connection = ClaudeConnectionModel(
        appModel: appModel,
        profileID: profileID,
        qualify: {
            throw CancellationError()
        },
        removeProfile: { profileID in
            profileRemover.remove(profileID)
        },
    )

    await connection.start()
    await connection.cancel()

    #expect(profileRemover.removedProfileIDs == [profileID])
    #expect(appModel.accounts.isEmpty)
}

@Test
@MainActor
func githubCopilotConnectionShowsDevicePromptAndSavesIdentity()
    async throws
{
    let reference = Date(
        timeIntervalSince1970: 2_000_000_000
    )
    let accountID = UUID()
    let prompt = GitHubCopilotAuthorizationPrompt(
        verificationURL: URL(
            string: "https://github.com/login/device"
        )!,
        userCode: "ABCD-EFGH",
        expiresAt:
            reference.addingTimeInterval(600)
    )
    let credential = GitHubCopilotCredential(
        accessToken: "github-token",
        userID: "42",
        login: "octocat"
    )
    let credentials = TestCredentialStore()
    let adapter = TestProviderAccountAdapter(
        provider: .githubCopilot,
        result: .success(
            UsageSnapshot(
                accountID: accountID,
                fetchedAt: reference,
                windows: []
            )
        )
    )
    let appModel = AppModel(
        stateStore: TestAppStateStore(
            state: .empty
        ),
        credentialStore: credentials,
        adapters: [adapter],
        now: { reference }
    )
    await appModel.start()
    let connection =
        GitHubCopilotConnectionModel(
            appModel: appModel,
            accountID: accountID,
            authenticate: { onPrompt in
                await onPrompt(prompt)
                return GitHubCopilotOAuthResult(
                    credential: credential
                )
            }
        )

    await connection.start()

    #expect(connection.prompt == prompt)
    #expect(
        connection.phase
            == .readyToSave(login: "octocat")
    )

    try await connection.save(
        displayName: "Personal Copilot"
    )

    #expect(connection.phase == .complete)
    #expect(
        appModel.accounts[0].account
            .authenticatedIdentity == "octocat"
    )
    #expect(
        try await credentials.load(
            GitHubCopilotCredential.self,
            for: accountID
        ) == credential
    )
}

@Test
@MainActor
func githubCopilotConnectionBlocksAnExistingGitHubIdentity()
    async throws
{
    let existing = SubscriptionAccount(
        provider: .githubCopilot,
        displayName: "Existing",
        authenticatedIdentity: "octocat",
        displayOrder: 0
    )
    let credentials = TestCredentialStore()
    try await credentials.save(
        GitHubCopilotCredential(
            accessToken: "existing-token",
            userID: "42",
            login: "octocat"
        ),
        for: existing.id
    )
    let appModel = AppModel(
        stateStore: TestAppStateStore(
            state: PersistedAppState(
                accounts: [existing],
                snapshots: [:]
            )
        ),
        credentialStore: credentials,
        adapters: [
            TestProviderAccountAdapter(
                provider: .githubCopilot
            )
        ]
    )
    await appModel.start()
    let connection =
        GitHubCopilotConnectionModel(
            appModel: appModel,
            authenticate: { _ in
                GitHubCopilotOAuthResult(
                    credential:
                        GitHubCopilotCredential(
                            accessToken:
                                "replacement-token",
                            userID: "42",
                            login: "octocat"
                        )
                )
            }
        )

    await connection.start()

    #expect(
        connection.phase
            == .duplicateIdentity(
                login: "octocat"
            )
    )
    await #expect(
        throws:
            ProviderConnectionInputError
                .authorizationNotComplete
    ) {
        try await connection.save(
            displayName: "Duplicate"
        )
    }
    #expect(appModel.accounts.count == 1)
}

@Test
@MainActor
func superGrokConnectionShowsDevicePromptAndSavesIdentity()
    async throws
{
    let reference = Date(
        timeIntervalSince1970: 2_000_000_000
    )
    let accountID = UUID()
    let prompt = SuperGrokAuthorizationPrompt(
        verificationURL: URL(
            string: "https://auth.x.ai/device"
        )!,
        userCode: "ABCD-EFGH"
    )
    let credential = SuperGrokCredential(
        accessToken: "grok-token",
        email: "user@example.com",
        teamID: "team-1",
        userID: "user-1",
        authMode: "oidc",
        expiresAt: nil
    )
    let credentials = TestCredentialStore()
    let snapshot = UsageSnapshot(
        accountID: accountID,
        fetchedAt: reference,
        windows: [
            UsageWindow(
                id: "supergrok-weekly",
                kind: .weekly,
                duration: 604_800,
                resetAt:
                    reference.addingTimeInterval(
                        604_800
                    ),
                consumedFraction: 0
            )!
        ]
    )
    let adapter = TestProviderAccountAdapter(
        provider: .superGrok,
        result: .success(snapshot)
    )
    let appModel = AppModel(
        stateStore: TestAppStateStore(
            state: .empty
        ),
        credentialStore: credentials,
        adapters: [adapter],
        now: { reference }
    )
    await appModel.start()
    let connection =
        SuperGrokConnectionModel(
            appModel: appModel,
            accountID: accountID,
            authenticate: { onPrompt in
                await onPrompt(prompt)
                return credential
            }
        )

    await connection.start()

    #expect(connection.prompt == prompt)
    #expect(
        connection.phase
            == .readyToSave(
                identity:
                    "user@example.com"
            )
    )

    try await connection.save(
        displayName: "Personal Grok"
    )

    #expect(connection.phase == .complete)
    #expect(
        appModel.accounts[0].account
            .authenticatedIdentity
            == "user@example.com"
    )
    #expect(
        appModel.accounts[0].snapshot
            == snapshot
    )
    #expect(
        try await credentials.load(
            SuperGrokCredential.self,
            for: accountID
        ) == credential
    )
}

@Test
@MainActor
func superGrokConnectionBlocksAnExistingBillingIdentity()
    async throws
{
    let existing = SubscriptionAccount(
        provider: .superGrok,
        displayName: "Existing",
        authenticatedIdentity:
            "user@example.com",
        displayOrder: 0
    )
    let credentials = TestCredentialStore()
    let existingCredential =
        SuperGrokCredential(
            accessToken: "existing-token",
            email: "user@example.com",
            teamID: "team-1",
            userID: "user-1",
            authMode: "oidc",
            expiresAt: nil
        )
    try await credentials.save(
        existingCredential,
        for: existing.id
    )
    let appModel = AppModel(
        stateStore: TestAppStateStore(
            state: PersistedAppState(
                accounts: [existing],
                snapshots: [:]
            )
        ),
        credentialStore: credentials,
        adapters: [
            TestProviderAccountAdapter(
                provider: .superGrok
            )
        ]
    )
    await appModel.start()
    let connection =
        SuperGrokConnectionModel(
            appModel: appModel,
            authenticate: { _ in
                SuperGrokCredential(
                    accessToken:
                        "replacement-token",
                    email: "user@example.com",
                    teamID: "team-1",
                    userID: "user-1",
                    authMode: "oidc",
                    expiresAt: nil
                )
            }
        )

    await connection.start()

    #expect(
        connection.phase
            == .duplicateIdentity(
                identity:
                    "user@example.com"
            )
    )
    await #expect(
        throws:
            ProviderConnectionInputError
                .authorizationNotComplete
    ) {
        try await connection.save(
            displayName: "Duplicate"
        )
    }
    #expect(appModel.accounts.count == 1)
}

@Test
@MainActor
func sharedProfileSurvivesUntilItsLastAccountIsRemoved() async throws {
    let profileID = UUID()
    let first = SubscriptionAccount(
        provider: .claude,
        displayName: "Personal",
        displayOrder: 0,
        claudeProfileID: profileID,
        claudeOrganizationID: UUID(),
    )
    let second = SubscriptionAccount(
        provider: .claude,
        displayName: "Team",
        displayOrder: 1,
        claudeProfileID: profileID,
        claudeOrganizationID: UUID(),
    )
    let profileRemover = TestClaudeProfileRemover()
    let model = AppModel(
        stateStore: TestAppStateStore(
            state: PersistedAppState(
                accounts: [first, second],
                snapshots: [:],
            ),
        ),
        credentialStore: TestCredentialStore(),
        adapters: [profileRemover],
        now: { Date(timeIntervalSince1970: 2_000_000_000) },
    )
    await model.start()

    try await model.removeAccount(id: first.id)

    #expect(profileRemover.removedProfileIDs.isEmpty)
    #expect(model.accounts.map(\.id) == [second.id])

    try await model.removeAccount(id: second.id)

    #expect(profileRemover.removedProfileIDs == [profileID])
    #expect(model.accounts.isEmpty)
}

@Test
@MainActor
func reconnectRepointsSiblingAccountsToTheReplacementProfile() async throws {
    let oldProfileID = UUID()
    let newProfileID = UUID()
    let organizationID = UUID()
    let reconnecting = SubscriptionAccount(
        provider: .claude,
        displayName: "Personal",
        displayOrder: 0,
        claudeProfileID: oldProfileID,
        claudeOrganizationID: organizationID,
    )
    let sibling = SubscriptionAccount(
        provider: .claude,
        displayName: "Team",
        displayOrder: 1,
        claudeProfileID: oldProfileID,
        claudeOrganizationID: UUID(),
    )
    let profileRemover = TestClaudeProfileRemover()
    let stateStore = TestAppStateStore(
        state: PersistedAppState(
            accounts: [reconnecting, sibling],
            snapshots: [:],
        ),
    )
    let model = AppModel(
        stateStore: stateStore,
        credentialStore: TestCredentialStore(),
        adapters: [profileRemover],
        now: { Date(timeIntervalSince1970: 2_000_000_000) },
    )
    await model.start()

    let replacement = SubscriptionAccount(
        id: reconnecting.id,
        provider: .claude,
        displayName: "Personal",
        displayOrder: 0,
        claudeProfileID: newProfileID,
        claudeOrganizationID: organizationID,
    )
    try await model.reconnectClaudeAccount(
        id: reconnecting.id,
        replacement: replacement,
        qualifiedOrganizationIDs: [
            organizationID,
            sibling.claudeOrganizationID!,
        ],
    )

    let profileIDs = model.accounts.map(\.account.claudeProfileID)
    #expect(profileIDs == [newProfileID, newProfileID])
    let persistedProfileIDs = await stateStore.state.accounts
        .map(\.claudeProfileID)
    #expect(persistedProfileIDs == [newProfileID, newProfileID])
    #expect(profileRemover.removedProfileIDs == [oldProfileID])
}

@Test
@MainActor
func reconnectLeavesSiblingsWhoseOrganizationTheLoginLacks() async throws {
    let oldProfileID = UUID()
    let newProfileID = UUID()
    let organizationID = UUID()
    let reconnecting = SubscriptionAccount(
        provider: .claude,
        displayName: "Personal",
        displayOrder: 0,
        claudeProfileID: oldProfileID,
        claudeOrganizationID: organizationID,
    )
    let sibling = SubscriptionAccount(
        provider: .claude,
        displayName: "Team",
        displayOrder: 1,
        claudeProfileID: oldProfileID,
        claudeOrganizationID: UUID(),
    )
    let profileRemover = TestClaudeProfileRemover()
    let stateStore = TestAppStateStore(
        state: PersistedAppState(
            accounts: [reconnecting, sibling],
            snapshots: [:],
        ),
    )
    let model = AppModel(
        stateStore: stateStore,
        credentialStore: TestCredentialStore(),
        adapters: [profileRemover],
        now: { Date(timeIntervalSince1970: 2_000_000_000) },
    )
    await model.start()

    let replacement = SubscriptionAccount(
        id: reconnecting.id,
        provider: .claude,
        displayName: "Personal",
        displayOrder: 0,
        claudeProfileID: newProfileID,
        claudeOrganizationID: organizationID,
    )
    try await model.reconnectClaudeAccount(
        id: reconnecting.id,
        replacement: replacement,
        qualifiedOrganizationIDs: [organizationID],
    )

    let profileIDs = model.accounts.map(\.account.claudeProfileID)
    #expect(profileIDs == [newProfileID, oldProfileID])
    #expect(profileRemover.removedProfileIDs.isEmpty)
}

@Test
@MainActor
func batchConnectPersistsAllAccountsOrNone() async throws {
    let profileID = UUID()
    let stateStore = TestAppStateStore(state: .empty)
    let model = AppModel(
        stateStore: stateStore,
        credentialStore: TestCredentialStore(),
        adapters: [TestClaudeProfileRemover()],
        now: { Date(timeIntervalSince1970: 2_000_000_000) },
    )
    await model.start()

    let valid = SubscriptionAccount(
        provider: .claude,
        displayName: "Personal",
        displayOrder: 0,
        claudeProfileID: profileID,
        claudeOrganizationID: UUID(),
    )
    let invalid = SubscriptionAccount(
        provider: .claude,
        displayName: "Broken",
        displayOrder: 1,
        claudeProfileID: profileID,
        claudeOrganizationID: nil,
    )

    await #expect(throws: AppModelError.invalidSnapshot) {
        try await model.connectClaudeAccounts([
            (account: valid, snapshot: nil),
            (account: invalid, snapshot: nil),
        ])
    }

    #expect(model.accounts.isEmpty)
    #expect(await stateStore.state.accounts.isEmpty)

    try await model.connectClaudeAccounts([
        (account: valid, snapshot: nil),
    ])
    #expect(model.accounts.map(\.id) == [valid.id])
    #expect(await stateStore.state.accounts.map(\.id) == [valid.id])
}

@Test
@MainActor
func reconnectClearsMigratedSiblingsAuthenticationState() async throws {
    let oldProfileID = UUID()
    let newProfileID = UUID()
    let organizationID = UUID()
    let siblingOrganizationID = UUID()
    let reconnecting = SubscriptionAccount(
        provider: .claude,
        displayName: "Personal",
        displayOrder: 0,
        claudeProfileID: oldProfileID,
        claudeOrganizationID: organizationID,
    )
    let sibling = SubscriptionAccount(
        provider: .claude,
        displayName: "Team",
        displayOrder: 1,
        claudeProfileID: oldProfileID,
        claudeOrganizationID: siblingOrganizationID,
    )
    let stateStore = TestAppStateStore(
        state: PersistedAppState(
            accounts: [reconnecting, sibling],
            snapshots: [:],
            refreshStates: [
                sibling.id: AccountRefreshState(
                    lastRequestStartedAt:
                    Date(timeIntervalSince1970: 1_999_999_000),
                    requiresReauthentication: true,
                ),
            ],
        ),
    )
    let model = AppModel(
        stateStore: stateStore,
        credentialStore: TestCredentialStore(),
        adapters: [TestClaudeProfileRemover()],
        now: { Date(timeIntervalSince1970: 2_000_000_000) },
    )
    await model.start()
    #expect(
        model.accounts.first { $0.id == sibling.id }?.error
            == .authenticationRequired,
    )

    let replacement = SubscriptionAccount(
        id: reconnecting.id,
        provider: .claude,
        displayName: "Personal",
        displayOrder: 0,
        claudeProfileID: newProfileID,
        claudeOrganizationID: organizationID,
    )
    try await model.reconnectClaudeAccount(
        id: reconnecting.id,
        replacement: replacement,
        qualifiedOrganizationIDs: [
            organizationID,
            siblingOrganizationID,
        ],
    )

    let siblingState = model.accounts.first { $0.id == sibling.id }
    #expect(siblingState?.error == nil)
    #expect(siblingState?.account.claudeProfileID == newProfileID)
    let persistedSiblingState = await stateStore.state
        .refreshStates[sibling.id]
    #expect(persistedSiblingState?.requiresReauthentication == false)
}

@MainActor
private final class GatedClaudeAdapter: ProviderAccountAdapter {
    nonisolated let provider = Provider.claude
    private var gate: CheckedContinuation<Void, Never>?
    private var waitingForGate: CheckedContinuation<Void, Never>?

    func fetchUsage(
        for _: SubscriptionAccount,
        now _: Date,
    ) async throws -> UsageSnapshot {
        waitingForGate?.resume()
        waitingForGate = nil
        await withCheckedContinuation { continuation in
            gate = continuation
        }
        throw ProviderClientError.reauthenticationRequired
    }

    private var removalGate: CheckedContinuation<Void, Never>?
    private var waitingForRemoval: CheckedContinuation<Void, Never>?
    var gateNextRemoval = false

    func removeAuthentication(
        for _: SubscriptionAccount,
    ) async throws {
        guard gateNextRemoval else {
            return
        }
        gateNextRemoval = false
        waitingForRemoval?.resume()
        waitingForRemoval = nil
        await withCheckedContinuation { continuation in
            removalGate = continuation
        }
    }

    func waitUntilRemovalGated() async {
        await withCheckedContinuation { continuation in
            waitingForRemoval = continuation
        }
    }

    func releaseRemovalGate() {
        removalGate?.resume()
        removalGate = nil
    }

    func waitUntilFetching() async {
        await withCheckedContinuation { continuation in
            waitingForGate = continuation
        }
    }

    func releaseGate() {
        gate?.resume()
        gate = nil
    }
}

@Test
@MainActor
func staleRefreshCannotUndoAReconnectMigration() async throws {
    let oldProfileID = UUID()
    let newProfileID = UUID()
    let organizationID = UUID()
    let siblingOrganizationID = UUID()
    let reconnecting = SubscriptionAccount(
        provider: .claude,
        displayName: "Personal",
        displayOrder: 0,
        claudeProfileID: oldProfileID,
        claudeOrganizationID: organizationID,
    )
    let sibling = SubscriptionAccount(
        provider: .claude,
        displayName: "Team",
        displayOrder: 1,
        claudeProfileID: oldProfileID,
        claudeOrganizationID: siblingOrganizationID,
    )
    let adapter = GatedClaudeAdapter()
    let stateStore = TestAppStateStore(state: .empty)
    let model = AppModel(
        stateStore: stateStore,
        credentialStore: TestCredentialStore(),
        adapters: [adapter],
        now: { Date(timeIntervalSince1970: 2_000_000_000) },
    )
    await model.start()
    try await model.connectClaudeAccounts([
        (account: reconnecting, snapshot: nil),
        (account: sibling, snapshot: nil),
    ])

    let staleRefresh = Task { @MainActor in
        await model.refreshAccount(id: sibling.id)
    }
    await adapter.waitUntilFetching()

    let replacement = SubscriptionAccount(
        id: reconnecting.id,
        provider: .claude,
        displayName: "Personal",
        displayOrder: 0,
        claudeProfileID: newProfileID,
        claudeOrganizationID: organizationID,
    )
    try await model.reconnectClaudeAccount(
        id: reconnecting.id,
        replacement: replacement,
        qualifiedOrganizationIDs: [
            organizationID,
            siblingOrganizationID,
        ],
    )

    adapter.releaseGate()
    await staleRefresh.value

    let siblingState = model.accounts.first { $0.id == sibling.id }
    #expect(siblingState?.error == nil)
    #expect(siblingState?.isRefreshing == false)
    let persisted = await stateStore.state.refreshStates[sibling.id]
    #expect(persisted?.requiresReauthentication != true)
}

@Test
@MainActor
func staleRefreshCannotRevertAReconnectMidSave() async throws {
    let oldProfileID = UUID()
    let newProfileID = UUID()
    let organizationID = UUID()
    let siblingOrganizationID = UUID()
    let reconnecting = SubscriptionAccount(
        provider: .claude,
        displayName: "Personal",
        displayOrder: 0,
        claudeProfileID: oldProfileID,
        claudeOrganizationID: organizationID,
    )
    let sibling = SubscriptionAccount(
        provider: .claude,
        displayName: "Team",
        displayOrder: 1,
        claudeProfileID: oldProfileID,
        claudeOrganizationID: siblingOrganizationID,
    )
    let adapter = GatedClaudeAdapter()
    let stateStore = TestAppStateStore(state: .empty)
    let model = AppModel(
        stateStore: stateStore,
        credentialStore: TestCredentialStore(),
        adapters: [adapter],
        now: { Date(timeIntervalSince1970: 2_000_000_000) },
    )
    await model.start()
    try await model.connectClaudeAccounts([
        (account: reconnecting, snapshot: nil),
        (account: sibling, snapshot: nil),
    ])

    let staleRefresh = Task { @MainActor in
        await model.refreshAccount(id: sibling.id)
    }
    await adapter.waitUntilFetching()

    let replacement = SubscriptionAccount(
        id: reconnecting.id,
        provider: .claude,
        displayName: "Personal",
        displayOrder: 0,
        claudeProfileID: newProfileID,
        claudeOrganizationID: organizationID,
    )
    adapter.gateNextRemoval = true
    let reconnect = Task { @MainActor in
        try await model.reconnectClaudeAccount(
            id: reconnecting.id,
            replacement: replacement,
            qualifiedOrganizationIDs: [
                organizationID,
                siblingOrganizationID,
            ],
        )
    }
    await adapter.waitUntilRemovalGated()

    adapter.releaseGate()
    await staleRefresh.value
    adapter.releaseRemovalGate()
    try await reconnect.value

    let persistedAccounts = await stateStore.state.accounts
    #expect(
        persistedAccounts.map(\.claudeProfileID)
            == [newProfileID, newProfileID],
    )
    let persistedSibling = await stateStore.state
        .refreshStates[sibling.id]
    #expect(persistedSibling?.requiresReauthentication != true)
}
