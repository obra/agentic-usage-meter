import Foundation
import UsageMeterCore
import UsageMeterWeb
import WebKit

@MainActor
public final class OpenCodeWebAccountUsageClient:
    ProviderAccountAdapter
{
    public nonisolated let provider: Provider

    public nonisolated var canRecoverAuthenticationWithoutReconnect: Bool {
        true
    }

    public typealias RemoveProfile =
        @MainActor @Sendable (
            UUID
        ) async throws -> Void
    public typealias LoadAuthCookie =
        @MainActor @Sendable (
            UUID
        ) async -> String?
    public typealias EvictAuthCookieProfile =
        @MainActor @Sendable (UUID) async -> Void
    public typealias FinishAuthCookieProfile =
        @MainActor @Sendable (UUID) -> Void

    private let base: any ProviderAccountAdapter
    private let credentialStore:
        any CredentialStore
    private let loadAuthCookie: LoadAuthCookie
    private let evictAuthCookieProfile:
        EvictAuthCookieProfile
    private let finishAuthCookieProfile:
        FinishAuthCookieProfile
    private let removeProfile: RemoveProfile

    public init(
        base: any ProviderAccountAdapter,
        credentialStore: any CredentialStore,
        loadAuthCookie: LoadAuthCookie? = nil,
        evictAuthCookieProfile:
            EvictAuthCookieProfile? = nil,
        finishAuthCookieProfile:
            FinishAuthCookieProfile? = nil,
        removeProfile:
            @escaping RemoveProfile = {
                try await AccountWebProfileStore
                    .remove(accountID: $0)
            }
    ) {
        provider = base.provider
        precondition(
            provider == .openCodeGo
                || provider == .openCodeZen
        )
        self.base = base
        self.credentialStore = credentialStore
        if let loadAuthCookie {
            self.loadAuthCookie =
                loadAuthCookie
            self.evictAuthCookieProfile =
                evictAuthCookieProfile ?? { _ in }
            self.finishAuthCookieProfile =
                finishAuthCookieProfile ?? { _ in }
        } else {
            let source =
                OpenCodeProfileAuthCookieSource()
            self.loadAuthCookie = {
                accountID in
                await source.authCookie(
                    accountID: accountID
                )
            }
            self.evictAuthCookieProfile = {
                await source.prepareForRemoval(
                    accountID: $0
                )
            }
            self.finishAuthCookieProfile = {
                source.finishRemoval(accountID: $0)
            }
        }
        self.removeProfile = removeProfile
    }

    public func fetchUsage(
        for account: SubscriptionAccount,
        now: Date
    ) async throws -> UsageSnapshot {
        if
            let profileAuthCookie =
                await loadAuthCookie(account.id),
            let storedCredential =
                try await credentialStore.load(
                    OpenCodeDashboardCredential.self,
                    for: account.id
                ),
            storedCredential.authCookie
                != profileAuthCookie
        {
            try await credentialStore.save(
                OpenCodeDashboardCredential(
                    workspaceID:
                        storedCredential.workspaceID,
                    authCookie: profileAuthCookie
                ),
                for: account.id
            )
        }
        return try await base.fetchUsage(
            for: account,
            now: now
        )
    }

    public func removeAuthentication(
        for account: SubscriptionAccount
    ) async throws {
        try await base.removeAuthentication(
            for: account
        )
        await evictAuthCookieProfile(account.id)
        defer {
            finishAuthCookieProfile(account.id)
        }
        try await removeProfile(account.id)
    }
}

@MainActor
protocol OpenCodeProfileCookieLoading:
    AnyObject
{
    func cookies() async -> [HTTPCookie]
    func warmIfNeeded()
}

@MainActor
final class OpenCodeProfileAuthCookieSource {
    typealias ProfileFactory =
        @MainActor (UUID) ->
        any OpenCodeProfileCookieLoading

    private let retryDelays: [Duration]
    private let profileFactory: ProfileFactory
    private var profiles:
        [
            UUID:
                any OpenCodeProfileCookieLoading
        ] = [:]
    private var activeLoads:
        [UUID: [UUID: Task<String?, Never>]] = [:]
    private var removalLeaseCounts: [UUID: Int] = [:]

    convenience init() {
        self.init(
            retryDelays: [
                .milliseconds(250),
                .milliseconds(500),
                .seconds(1),
            ],
            profileFactory: {
                WebKitOpenCodeProfileCookieLoader(
                    accountID: $0
                )
            }
        )
    }

    init(
        retryDelays: [Duration],
        profileFactory:
            @escaping ProfileFactory
    ) {
        self.retryDelays = retryDelays
        self.profileFactory = profileFactory
    }

    func authCookie(
        accountID: UUID
    ) async -> String? {
        guard removalLeaseCounts[accountID] == nil else {
            return nil
        }

        let loadID = UUID()
        let load = startCookieLoad(accountID: accountID)
        activeLoads[accountID, default: [:]][loadID] = load
        let cookie = await withTaskCancellationHandler {
            await load.value
        } onCancel: {
            load.cancel()
        }
        activeLoads[accountID]?[loadID] = nil
        if activeLoads[accountID]?.isEmpty == true {
            activeLoads[accountID] = nil
        }
        if
            load.isCancelled,
            activeLoads[accountID] == nil
        {
            profiles[accountID] = nil
        }
        return cookie
    }

    func prepareForRemoval(accountID: UUID) async {
        removalLeaseCounts[accountID, default: 0] += 1
        profiles[accountID] = nil

        let loads = activeLoads[accountID].map {
            Array($0.values)
        } ?? []
        for load in loads {
            load.cancel()
        }
        for load in loads {
            _ = await load.value
        }
        activeLoads[accountID] = nil
    }

    func finishRemoval(accountID: UUID) {
        guard let leaseCount = removalLeaseCounts[accountID] else {
            assertionFailure("OpenCode removal lease underflow")
            return
        }
        if leaseCount == 1 {
            removalLeaseCounts[accountID] = nil
        } else {
            removalLeaseCounts[accountID] = leaseCount - 1
        }
    }

    func isPreparingRemoval(accountID: UUID) -> Bool {
        removalLeaseCounts[accountID] != nil
    }

    private func startCookieLoad(
        accountID: UUID
    ) -> Task<String?, Never> {
        let profile: any
            OpenCodeProfileCookieLoading
        if let existing = profiles[accountID] {
            profile = existing
        } else {
            let created =
                profileFactory(accountID)
            profiles[accountID] = created
            profile = created
        }

        let retryDelays = self.retryDelays
        return Task { @MainActor in
            await Self.loadAuthCookie(
                from: profile,
                retryDelays: retryDelays
            )
        }
    }

    private static func loadAuthCookie(
        from profile: any OpenCodeProfileCookieLoading,
        retryDelays: [Duration]
    ) async -> String? {
        guard !Task.isCancelled else {
            return nil
        }
        if let authCookie = await authCookie(from: profile) {
            return authCookie
        }
        guard !Task.isCancelled else {
            return nil
        }
        profile.warmIfNeeded()

        for delay in retryDelays {
            do {
                try await Task.sleep(for: delay)
            } catch {
                return nil
            }
            guard !Task.isCancelled else {
                return nil
            }
            if let authCookie = await authCookie(from: profile) {
                return authCookie
            }
        }
        return nil
    }

    private static func authCookie(
        from profile:
            any OpenCodeProfileCookieLoading
    ) async -> String? {
        OpenCodeLoginDetector.authCookie(
            in: await profile.cookies()
        )
    }
}

@MainActor
private final class WebKitOpenCodeProfileCookieLoader:
    OpenCodeProfileCookieLoading
{
    private static let warmupURL =
        URL(
            string:
                "https://opencode.ai/robots.txt"
        )!

    private let profileStore:
        AccountWebProfileStore
    private var warmupWebView: WKWebView?
    private var didStartWarmup = false

    init(accountID: UUID) {
        profileStore = AccountWebProfileStore(
            accountID: accountID
        )
    }

    func cookies() async -> [HTTPCookie] {
        let cookies = await withCheckedContinuation {
            continuation in
            profileStore.dataStore.httpCookieStore
                .getAllCookies { cookies in
                    continuation.resume(
                        returning: cookies
                    )
                }
        }
        if OpenCodeLoginDetector.authCookie(
            in: cookies
        ) != nil {
            warmupWebView?.stopLoading()
            warmupWebView = nil
        }
        return cookies
    }

    func warmIfNeeded() {
        guard !didStartWarmup else {
            return
        }
        didStartWarmup = true

        let configuration =
            WKWebViewConfiguration()
        configuration.websiteDataStore =
            profileStore.dataStore
        let webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )
        warmupWebView = webView
        webView.load(
            URLRequest(
                url: Self.warmupURL
            )
        )
    }
}
