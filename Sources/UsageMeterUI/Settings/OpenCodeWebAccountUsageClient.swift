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

    private let base: any ProviderAccountAdapter
    private let credentialStore:
        any CredentialStore
    private let loadAuthCookie: LoadAuthCookie
    private let removeProfile: RemoveProfile

    public init(
        base: any ProviderAccountAdapter,
        credentialStore: any CredentialStore,
        loadAuthCookie: LoadAuthCookie? = nil,
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
        } else {
            let source =
                OpenCodeProfileAuthCookieSource()
            self.loadAuthCookie = {
                accountID in
                await source.authCookie(
                    accountID: accountID
                )
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

        if let authCookie = await authCookie(
            from: profile
        ) {
            return authCookie
        }
        profile.warmIfNeeded()

        for delay in retryDelays {
            do {
                try await Task.sleep(for: delay)
            } catch {
                return nil
            }
            if let authCookie = await authCookie(
                from: profile
            ) {
                return authCookie
            }
        }
        return nil
    }

    private func authCookie(
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
