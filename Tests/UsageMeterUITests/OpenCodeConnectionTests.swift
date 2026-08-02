import Foundation
import Testing
import UsageMeterCore
import UsageMeterWeb

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
func openCodeLoginCompletionWaitsForFinishedWorkspace()
    throws
{
    let preliminary = try #require(
        HTTPCookie(
            properties: [
                .name: "auth",
                .value: "preliminary-session",
                .domain: "opencode.ai",
                .path: "/",
            ]
        )
    )
    let final = try #require(
        HTTPCookie(
            properties: [
                .name: "auth",
                .value: "final-session",
                .domain: "opencode.ai",
                .path: "/",
            ]
        )
    )
    var completion =
        OpenCodeLoginCompletionGate()

    #expect(
        completion.credential(
            in: [preliminary]
        ) == nil
    )

    completion.didFinish(
        URL(
            string:
                "https://opencode.ai/workspace/wrk_personal/go"
        )!
    )

    #expect(
        completion.credential(in: [final])
            == OpenCodeDashboardCredential(
                workspaceID: "wrk_personal",
                authCookie: "final-session"
            )
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
func openCodeRefreshUsesTheProfilesCurrentAuthCookie()
    async throws
{
    let account = SubscriptionAccount(
        provider: .openCodeGo,
        displayName: "OpenCode Go",
        authenticatedIdentity: "wrk_personal",
        displayOrder: 0
    )
    let credentialStore = TestCredentialStore()
    try await credentialStore.save(
        OpenCodeDashboardCredential(
            workspaceID: "wrk_personal",
            authCookie: "preliminary-session"
        ),
        for: account.id
    )
    let base = TestProviderAccountAdapter(
        provider: .openCodeGo,
        result: .success(
            UsageSnapshot(
                accountID: account.id,
                fetchedAt: Date(),
                windows: []
            )
        )
    )
    let adapter = OpenCodeWebAccountUsageClient(
        base: base,
        credentialStore: credentialStore,
        loadAuthCookie: { accountID in
            #expect(accountID == account.id)
            return "final-session"
        },
        removeProfile: { _ in }
    )

    #expect(
        adapter
            .canRecoverAuthenticationWithoutReconnect
    )

    _ = try await adapter.fetchUsage(
        for: account,
        now: Date()
    )

    let stored = try #require(
        await credentialStore.load(
            OpenCodeDashboardCredential.self,
            for: account.id
        )
    )
    #expect(stored.authCookie == "final-session")
    #expect(
        await base.fetchedAccountIDs
            == [account.id]
    )
}

@Test
@MainActor
func openCodeCookieSourceWarmsAColdProfile()
    async throws
{
    let cookie = try #require(
        HTTPCookie(
            properties: [
                .name: "auth",
                .value: "profile-session",
                .domain: "opencode.ai",
                .path: "/",
            ]
        )
    )
    let profile = TestOpenCodeCookieProfile(
        responses: [[], [cookie]]
    )
    let source = OpenCodeProfileAuthCookieSource(
        retryDelays: [.zero],
        profileFactory: { _ in profile }
    )

    let authCookie = await source.authCookie(
        accountID: UUID()
    )

    #expect(authCookie == "profile-session")
    #expect(profile.warmCount == 1)
    #expect(profile.readCount == 2)
}

@Test
@MainActor
func openCodeCookieSourceReleasesAnEvictedProfile() async {
    let accountID = UUID()
    var createdProfiles = 0
    weak var retainedProfile: TestOpenCodeCookieProfile?
    let source = OpenCodeProfileAuthCookieSource(
        retryDelays: [],
        profileFactory: { _ in
            createdProfiles += 1
            let profile = TestOpenCodeCookieProfile(
                responses: [[]]
            )
            retainedProfile = profile
            return profile
        }
    )

    _ = await source.authCookie(accountID: accountID)
    #expect(createdProfiles == 1)
    #expect(retainedProfile != nil)

    await source.prepareForRemoval(accountID: accountID)

    #expect(retainedProfile == nil)
    source.finishRemoval(accountID: accountID)
    _ = await source.authCookie(accountID: accountID)
    #expect(createdProfiles == 2)
}

@Test
@MainActor
func cancelingOpenCodeCookieLoadReleasesItsProfile() async {
    let accountID = UUID()
    let warmupGate = OpenCodeWarmupGate()
    weak var retainedProfile: WarmupOpenCodeCookieProfile?
    let source = OpenCodeProfileAuthCookieSource(
        retryDelays: [.seconds(60)],
        profileFactory: { _ in
            let profile = WarmupOpenCodeCookieProfile(
                warmupGate: warmupGate
            )
            retainedProfile = profile
            return profile
        }
    )

    let load = Task {
        await source.authCookie(accountID: accountID)
    }
    await warmupGate.waitUntilWarmupStarts()

    load.cancel()
    #expect(await load.value == nil)
    #expect(retainedProfile == nil)
}

@Test
@MainActor
func overlappingOpenCodeRemovalLeasesKeepTheProfileFenced()
    async
{
    let accountID = UUID()
    var createdProfiles = 0
    let source = OpenCodeProfileAuthCookieSource(
        retryDelays: [],
        profileFactory: { _ in
            createdProfiles += 1
            return TestOpenCodeCookieProfile(responses: [[]])
        }
    )

    await source.prepareForRemoval(accountID: accountID)
    await source.prepareForRemoval(accountID: accountID)
    source.finishRemoval(accountID: accountID)

    _ = await source.authCookie(accountID: accountID)
    #expect(createdProfiles == 0)

    source.finishRemoval(accountID: accountID)
    _ = await source.authCookie(accountID: accountID)
    #expect(createdProfiles == 1)
}

@Test
@MainActor
func preparingOpenCodeProfileRemovalCancelsAndDrainsInFlightLoad()
    async throws
{
    let account = SubscriptionAccount(
        provider: .openCodeGo,
        displayName: "OpenCode",
        displayOrder: 0,
    )
    let lifecycle = OpenCodeProfileLifecycleRecorder()
    let readGate = OpenCodeCookieReadGate()
    var createdProfiles = 0
    weak var retainedProfile: SuspendedOpenCodeCookieProfile?
    let source = OpenCodeProfileAuthCookieSource(
        retryDelays: [],
        profileFactory: { _ in
            createdProfiles += 1
            let profile = SuspendedOpenCodeCookieProfile(
                readGate: readGate
            )
            retainedProfile = profile
            return profile
        }
    )
    let base = OpenCodeLifecycleTestAdapter(
        lifecycle: lifecycle
    )
    let adapter = OpenCodeWebAccountUsageClient(
        base: base,
        credentialStore: TestCredentialStore(),
        loadAuthCookie: { accountID in
            await source.authCookie(accountID: accountID)
        },
        evictAuthCookieProfile: { accountID in
            await source.prepareForRemoval(accountID: accountID)
            lifecycle.record("evict/drain")
        },
        finishAuthCookieProfile: { accountID in
            source.finishRemoval(accountID: accountID)
        },
        removeProfile: { accountID in
            #expect(accountID == account.id)
            #expect(retainedProfile == nil)
            lifecycle.record("remove")
        },
    )

    let fetch = Task {
        try? await adapter.fetchUsage(for: account, now: Date())
    }
    await readGate.waitUntilReadStarts()

    let removal = Task {
        try await adapter.removeAuthentication(for: account)
    }
    await lifecycle.waitForEvent("credential")
    while !source.isPreparingRemoval(accountID: account.id) {
        await Task.yield()
    }

    _ = await source.authCookie(accountID: account.id)
    #expect(createdProfiles == 1)
    #expect(lifecycle.events == ["credential"])

    readGate.resume()
    try await removal.value
    _ = await fetch.value

    #expect(lifecycle.events == ["credential", "evict/drain", "remove"])
}

@Test
@MainActor
func evictedOpenCodeProfileCanBeRemovedAndRecreatedWithoutCookies()
    async throws
{
    let accountID = UUID()
    weak var retainedProfile: RetainedOpenCodeCookieProfile?
    let source = OpenCodeProfileAuthCookieSource(
        retryDelays: [],
        profileFactory: { id in
            let profile = RetainedOpenCodeCookieProfile(
                accountID: id
            )
            retainedProfile = profile
            return profile
        }
    )
    let cookie = try #require(
        HTTPCookie(
            properties: [
                .name: "auth",
                .value: "session-to-delete",
                .domain: "opencode.ai",
                .path: "/",
            ]
        )
    )

    _ = await source.authCookie(accountID: accountID)
    var profile: RetainedOpenCodeCookieProfile? =
        retainedProfile
    #expect(profile != nil)
    await profile?.setCookie(cookie)
    #expect(
        await profile?.cookies().contains {
            $0.name == "auth"
        } == true
    )
    profile = nil

    await source.prepareForRemoval(accountID: accountID)
    #expect(retainedProfile == nil)
    try await AccountWebProfileStore.remove(accountID: accountID)
    source.finishRemoval(accountID: accountID)

    var recreated: RetainedOpenCodeCookieProfile? =
        RetainedOpenCodeCookieProfile(accountID: accountID)
    #expect(
        await recreated?.cookies().allSatisfy {
            $0.name != "auth"
        } == true
    )
    recreated = nil
    try await AccountWebProfileStore.remove(accountID: accountID)
}

@Test
@MainActor
func removingOpenCodeAccountOrdersCredentialEvictionAndProfileDeletion()
    async throws
{
    let account = SubscriptionAccount(
        provider: .openCodeGo,
        displayName: "OpenCode",
        displayOrder: 0,
    )
    let lifecycle = OpenCodeProfileLifecycleRecorder()
    let base = OpenCodeLifecycleTestAdapter(
        lifecycle: lifecycle,
    )
    let adapter = OpenCodeWebAccountUsageClient(
        base: base,
        credentialStore: TestCredentialStore(),
        loadAuthCookie: { _ in nil },
        evictAuthCookieProfile: { profileID in
            #expect(profileID == account.id)
            lifecycle.record("evict/drain")
        },
        finishAuthCookieProfile: { profileID in
            #expect(profileID == account.id)
        },
        removeProfile: { profileID in
            #expect(profileID == account.id)
            lifecycle.record("remove")
        },
    )

    try await adapter.removeAuthentication(
        for: account,
    )

    #expect(lifecycle.events == ["credential", "evict/drain", "remove"])
}

@Test
@MainActor
func removingOpenCodeAccountStopsAfterCredentialDeletionFailure()
    async
{
    let account = SubscriptionAccount(
        provider: .openCodeGo,
        displayName: "OpenCode",
        displayOrder: 0,
    )
    let lifecycle = OpenCodeProfileLifecycleRecorder()
    let adapter = OpenCodeWebAccountUsageClient(
        base: OpenCodeLifecycleTestAdapter(
            lifecycle: lifecycle,
            removalError: .credential,
        ),
        credentialStore: TestCredentialStore(),
        loadAuthCookie: { _ in nil },
        evictAuthCookieProfile: { _ in
            lifecycle.record("evict/drain")
        },
        finishAuthCookieProfile: { _ in
            lifecycle.record("finish")
        },
        removeProfile: { _ in
            lifecycle.record("remove")
        },
    )

    await #expect(throws: OpenCodeLifecycleTestError.credential) {
        try await adapter.removeAuthentication(for: account)
    }

    #expect(lifecycle.events == ["credential"])
}

@Test
@MainActor
func removingOpenCodeAccountPropagatesProfileRemovalFailureAfterEviction()
    async
{
    let account = SubscriptionAccount(
        provider: .openCodeGo,
        displayName: "OpenCode",
        displayOrder: 0,
    )
    let lifecycle = OpenCodeProfileLifecycleRecorder()
    var createdProfiles = 0
    let source = OpenCodeProfileAuthCookieSource(
        retryDelays: [],
        profileFactory: { _ in
            createdProfiles += 1
            return TestOpenCodeCookieProfile(responses: [[]])
        }
    )
    let adapter = OpenCodeWebAccountUsageClient(
        base: OpenCodeLifecycleTestAdapter(
            lifecycle: lifecycle,
        ),
        credentialStore: TestCredentialStore(),
        loadAuthCookie: { accountID in
            await source.authCookie(accountID: accountID)
        },
        evictAuthCookieProfile: { accountID in
            await source.prepareForRemoval(accountID: accountID)
            lifecycle.record("evict/drain")
        },
        finishAuthCookieProfile: { accountID in
            source.finishRemoval(accountID: accountID)
            lifecycle.record("finish")
        },
        removeProfile: { _ in
            lifecycle.record("remove")
            throw OpenCodeLifecycleTestError.profile
        },
    )

    await #expect(throws: OpenCodeLifecycleTestError.profile) {
        try await adapter.removeAuthentication(for: account)
    }

    #expect(
        lifecycle.events
            == ["credential", "evict/drain", "remove", "finish"]
    )
    _ = await source.authCookie(accountID: account.id)
    #expect(createdProfiles == 1)
}

@MainActor
private final class OpenCodeProfileRemovalRecorder {
    private(set) var profileIDs: [UUID] = []

    func remove(_ profileID: UUID) {
        profileIDs.append(profileID)
    }
}

@MainActor
private final class OpenCodeProfileLifecycleRecorder {
    private(set) var events: [String] = []
    private var eventContinuations:
        [String: CheckedContinuation<Void, Never>] = [:]

    func record(_ event: String) {
        events.append(event)
        eventContinuations.removeValue(forKey: event)?
            .resume()
    }

    func waitForEvent(_ event: String) async {
        guard !events.contains(event) else {
            return
        }
        await withCheckedContinuation { continuation in
            eventContinuations[event] = continuation
        }
    }
}

private enum OpenCodeLifecycleTestError: Error, Equatable {
    case credential
    case profile
}

@MainActor
private final class OpenCodeLifecycleTestAdapter:
    ProviderAccountAdapter
{
    nonisolated let provider = Provider.openCodeGo

    private let lifecycle: OpenCodeProfileLifecycleRecorder
    private let removalError: OpenCodeLifecycleTestError?

    init(
        lifecycle: OpenCodeProfileLifecycleRecorder,
        removalError: OpenCodeLifecycleTestError? = nil,
    ) {
        self.lifecycle = lifecycle
        self.removalError = removalError
    }

    func fetchUsage(
        for _: SubscriptionAccount,
        now _: Date,
    ) throws -> UsageSnapshot {
        throw ProviderClientError.temporaryFailure
    }

    func removeAuthentication(
        for _: SubscriptionAccount,
    ) throws {
        lifecycle.record("credential")
        if let removalError {
            throw removalError
        }
    }
}

@MainActor
private final class OpenCodeCookieReadGate {
    private var readContinuation:
        CheckedContinuation<[HTTPCookie], Never>?
    private var startedContinuation:
        CheckedContinuation<Void, Never>?

    func readCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            readContinuation = continuation
            startedContinuation?.resume()
            startedContinuation = nil
        }
    }

    func waitUntilReadStarts() async {
        guard readContinuation == nil else {
            return
        }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func resume() {
        readContinuation?.resume(returning: [])
        readContinuation = nil
    }
}

@MainActor
private final class OpenCodeWarmupGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var didStartWarmup = false

    func warmupStarted() {
        didStartWarmup = true
        continuation?.resume()
        continuation = nil
    }

    func waitUntilWarmupStarts() async {
        guard !didStartWarmup else {
            return
        }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }
}

@MainActor
private final class WarmupOpenCodeCookieProfile:
    OpenCodeProfileCookieLoading
{
    private let warmupGate: OpenCodeWarmupGate

    init(warmupGate: OpenCodeWarmupGate) {
        self.warmupGate = warmupGate
    }

    func cookies() async -> [HTTPCookie] {
        []
    }

    func warmIfNeeded() {
        warmupGate.warmupStarted()
    }
}

@MainActor
private final class SuspendedOpenCodeCookieProfile:
    OpenCodeProfileCookieLoading
{
    private let readGate: OpenCodeCookieReadGate

    init(readGate: OpenCodeCookieReadGate) {
        self.readGate = readGate
    }

    func cookies() async -> [HTTPCookie] {
        await readGate.readCookies()
    }

    func warmIfNeeded() {}
}

@MainActor
private final class TestOpenCodeCookieProfile:
    OpenCodeProfileCookieLoading
{
    private var responses: [[HTTPCookie]]
    private(set) var readCount = 0
    private(set) var warmCount = 0

    init(responses: [[HTTPCookie]]) {
        self.responses = responses
    }

    func cookies() async -> [HTTPCookie] {
        let index = min(
            readCount,
            responses.count - 1
        )
        readCount += 1
        return responses[index]
    }

    func warmIfNeeded() {
        warmCount += 1
    }
}

@MainActor
private final class RetainedOpenCodeCookieProfile:
    OpenCodeProfileCookieLoading
{
    private let profileStore: AccountWebProfileStore

    init(accountID: UUID) {
        profileStore = AccountWebProfileStore(
            accountID: accountID
        )
    }

    func cookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            profileStore.dataStore.httpCookieStore
                .getAllCookies { cookies in
                    continuation.resume(returning: cookies)
                }
        }
    }

    func warmIfNeeded() {}

    func setCookie(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { continuation in
            profileStore.dataStore.httpCookieStore
                .setCookie(cookie) {
                    continuation.resume()
                }
        }
    }
}
