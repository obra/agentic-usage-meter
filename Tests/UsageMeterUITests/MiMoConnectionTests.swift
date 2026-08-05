import Foundation
import Testing
import UsageMeterCore
import UsageMeterWeb

@testable import UsageMeterUI

@Test
func mimoLoginDetectorBuildsACookieHeaderFromDomainCookies()
    throws
{
    let session = try #require(
        HTTPCookie(
            properties: [
                .name: "session",
                .value: "abc",
                .domain: "platform.xiaomimimo.com",
                .path: "/",
            ]
        )
    )
    let token = try #require(
        HTTPCookie(
            properties: [
                .name: "token",
                .value: "def",
                .domain: ".xiaomimimo.com",
                .path: "/",
            ]
        )
    )
    let foreign = try #require(
        HTTPCookie(
            properties: [
                .name: "session",
                .value: "foreign",
                .domain: "example.com",
                .path: "/",
            ]
        )
    )

    let expired = try #require(
        HTTPCookie(
            properties: [
                .name: "stale",
                .value: "old",
                .domain: "platform.xiaomimimo.com",
                .path: "/",
                .expires: Date(
                    timeIntervalSince1970: 1_000
                ),
            ]
        )
    )

    #expect(
        MiMoLoginDetector.cookieHeader(
            in: [foreign, session, token]
        ) == "session=abc; token=def"
    )
    #expect(
        MiMoLoginDetector.cookieHeader(
            in: [token, expired, session, foreign]
        ) == "session=abc; token=def"
    )
    #expect(
        MiMoLoginDetector.cookieHeader(in: [foreign]) == nil
    )
}

@Test
@MainActor
func mimoConnectionSavesAValidatedSession() async throws {
    let reference = Date(
        timeIntervalSince1970: 2_000_000_000
    )
    let accountID = UUID()
    let credential = try #require(
        MiMoWebCredential(cookieHeader: "session=abc")
    )
    let credentialStore = TestCredentialStore()
    let appModel = AppModel(
        stateStore: TestAppStateStore(state: .empty),
        credentialStore: credentialStore,
        adapters: [
            TestProviderAccountAdapter(
                provider: .mimo,
                result: .success(
                    UsageSnapshot(
                        accountID: accountID,
                        fetchedAt: reference,
                        windows: []
                    )
                )
            )
        ],
        now: { reference }
    )
    await appModel.start()
    let connection = MiMoConnectionModel(
        appModel: appModel,
        accountID: accountID,
        authenticate: { credential },
        removeProfile: { _ in }
    )

    await connection.start()

    #expect(connection.phase == .readyToSave)

    try await connection.save(displayName: "MiMo")

    #expect(connection.phase == .complete)
    #expect(
        appModel.accounts[0].account.provider == .mimo
    )
    #expect(
        try await credentialStore.load(
            MiMoWebCredential.self,
            for: accountID
        ) == credential
    )
}

@Test
@MainActor
func mimoConnectionReportsSignInFailure() async {
    let appModel = AppModel(
        stateStore: TestAppStateStore(state: .empty),
        credentialStore: TestCredentialStore(),
        adapters: [
            TestProviderAccountAdapter(provider: .mimo)
        ]
    )
    await appModel.start()
    let connection = MiMoConnectionModel(
        appModel: appModel,
        authenticate: {
            throw ProviderClientError.temporaryFailure
        },
        removeProfile: { _ in }
    )

    await connection.start()

    #expect(
        connection.phase
            == .failed("MiMo sign-in failed.")
    )
}

@Test
@MainActor
func mimoCancelRemovesTheUnsavedProfile() async throws {
    let accountID = UUID()
    let removal = ProfileRemovalRecorder()
    let appModel = AppModel(
        stateStore: TestAppStateStore(state: .empty),
        credentialStore: TestCredentialStore(),
        adapters: [
            TestProviderAccountAdapter(provider: .mimo)
        ]
    )
    await appModel.start()
    let connection = MiMoConnectionModel(
        appModel: appModel,
        accountID: accountID,
        authenticate: {
            try #require(
                MiMoWebCredential(cookieHeader: "session=abc")
            )
        },
        removeProfile: { profileID in
            removal.remove(profileID)
        }
    )

    await connection.start()
    await connection.cancel()

    #expect(removal.profileIDs == [accountID])
    #expect(appModel.accounts.isEmpty)

    await connection.start()
    await connection.cancel()

    #expect(
        removal.profileIDs == [accountID, accountID]
    )
}

@Test
@MainActor
func mimoRefreshUsesTheProfilesCurrentCookies() async throws {
    let account = SubscriptionAccount(
        provider: .mimo,
        displayName: "MiMo",
        displayOrder: 0
    )
    let credentialStore = TestCredentialStore()
    try await credentialStore.save(
        MiMoWebCredential(cookieHeader: "session=stale")!,
        for: account.id
    )
    let base = TestProviderAccountAdapter(
        provider: .mimo,
        result: .success(
            UsageSnapshot(
                accountID: account.id,
                fetchedAt: Date(),
                windows: []
            )
        )
    )
    let adapter = MiMoWebAccountUsageClient(
        base: base,
        credentialStore: credentialStore,
        loadCookieHeader: { accountID in
            #expect(accountID == account.id)
            return "session=fresh"
        },
        removeProfile: { _ in }
    )

    #expect(
        adapter.canRecoverAuthenticationWithoutReconnect
    )

    _ = try await adapter.fetchUsage(
        for: account,
        now: Date()
    )

    let stored = try #require(
        await credentialStore.load(
            MiMoWebCredential.self,
            for: account.id
        )
    )
    #expect(stored.cookieHeader == "session=fresh")
    #expect(
        await base.fetchedAccountIDs == [account.id]
    )
}

@MainActor
private final class ProfileRemovalRecorder {
    private(set) var profileIDs: [UUID] = []

    func remove(_ profileID: UUID) {
        profileIDs.append(profileID)
    }
}
