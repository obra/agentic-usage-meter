import Foundation
import UsageMeterWeb
import WebKit

@MainActor
protocol ProfileCookieLoading:
    AnyObject
{
    func cookies() async -> [HTTPCookie]
    func warmIfNeeded()
}

@MainActor
final class ProfileAuthCookieSource {
    typealias Extract =
        @MainActor ([HTTPCookie]) -> String?
    typealias ProfileFactory =
        @MainActor (UUID) ->
        any ProfileCookieLoading

    private let retryDelays: [Duration]
    private let extract: Extract
    private let profileFactory: ProfileFactory
    private var profiles:
        [
            UUID:
                any ProfileCookieLoading
        ] = [:]
    private var activeLoads:
        [UUID: [UUID: Task<String?, Never>]] = [:]
    private var removalLeaseCounts: [UUID: Int] = [:]

    init(
        retryDelays: [Duration],
        extract: @escaping Extract,
        profileFactory:
            @escaping ProfileFactory
    ) {
        self.retryDelays = retryDelays
        self.extract = extract
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
            assertionFailure("Profile removal lease underflow")
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
            ProfileCookieLoading
        if let existing = profiles[accountID] {
            profile = existing
        } else {
            let created =
                profileFactory(accountID)
            profiles[accountID] = created
            profile = created
        }

        let retryDelays = self.retryDelays
        let extract = self.extract
        return Task { @MainActor in
            await Self.loadAuthCookie(
                from: profile,
                retryDelays: retryDelays,
                extract: extract
            )
        }
    }

    private static func loadAuthCookie(
        from profile: any ProfileCookieLoading,
        retryDelays: [Duration],
        extract: Extract
    ) async -> String? {
        guard !Task.isCancelled else {
            return nil
        }
        if let authCookie = extract(await profile.cookies()) {
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
            if let authCookie = extract(await profile.cookies()) {
                return authCookie
            }
        }
        return nil
    }
}

@MainActor
final class WebKitProfileCookieLoader:
    ProfileCookieLoading
{
    private let warmupURL: URL
    private let hasAuthentication:
        @MainActor ([HTTPCookie]) -> Bool
    private let profileStore:
        AccountWebProfileStore
    private var warmupWebView: WKWebView?
    private var didStartWarmup = false

    init(
        accountID: UUID,
        warmupURL: URL,
        hasAuthentication:
            @escaping @MainActor ([HTTPCookie]) -> Bool
    ) {
        self.warmupURL = warmupURL
        self.hasAuthentication = hasAuthentication
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
        if hasAuthentication(cookies) {
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
                url: warmupURL
            )
        )
    }
}
