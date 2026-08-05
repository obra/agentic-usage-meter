import AppKit
import Foundation
import UsageMeterCore
import UsageMeterWeb
import WebKit

enum MiMoLoginDetector {
    static func cookieHeader(
        in cookies: [HTTPCookie]
    ) -> String? {
        let selected = cookies.filter { cookie in
            !cookie.value.isEmpty
                && isMiMoDomain(cookie.domain)
        }
        guard !selected.isEmpty else {
            return nil
        }
        return selected
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
    }

    static func isMiMoDomain(
        _ domain: String
    ) -> Bool {
        let domain = domain.lowercased()
            .trimmingCharacters(
                in: CharacterSet(
                    charactersIn: "."
                )
            )
        return domain == "xiaomimimo.com"
            || domain.hasSuffix(".xiaomimimo.com")
    }
}

@MainActor
final class MiMoLoginSession: NSObject {
    typealias Validate =
        @MainActor (String) async -> Bool

    private static let loginURL = URL(
        string:
            "https://platform.xiaomimimo.com/console/balance"
    )!

    private let accountID: UUID
    private let validate: Validate
    private let onPageReady: @MainActor () -> Void
    private let onAuthenticated:
        @MainActor (
            MiMoWebCredential
        ) -> Void

    private var profileStore: AccountWebProfileStore?
    private var cookieStore: WKHTTPCookieStore?
    private var webView: WKWebView?
    private var isFinished = false
    private var isValidating = false
    private var hasPendingCandidate = false
    private var lastRejectedHeader: String?

    init(
        accountID: UUID,
        validate: Validate? = nil,
        onPageReady:
            @escaping @MainActor () -> Void =
            {},
        onAuthenticated:
            @escaping @MainActor (
                MiMoWebCredential
            ) -> Void
    ) {
        self.accountID = accountID
        self.validate =
            validate ?? Self.probeTokenPlanUsage
        self.onPageReady = onPageReady
        self.onAuthenticated = onAuthenticated
    }

    func start() -> WKWebView {
        if let webView {
            return webView
        }

        let profileStore =
            AccountWebProfileStore(
                accountID: accountID
            )
        let configuration =
            WKWebViewConfiguration()
        configuration.websiteDataStore =
            profileStore.dataStore

        let webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )
        webView.navigationDelegate = self
        self.profileStore = profileStore
        self.webView = webView

        let cookieStore =
            profileStore.dataStore
            .httpCookieStore
        self.cookieStore = cookieStore
        cookieStore.add(self)
        webView.load(
            URLRequest(url: Self.loginURL)
        )
        return webView
    }

    func close() {
        isFinished = true
        cookieStore?.remove(self)
        cookieStore = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
        profileStore = nil
    }

    private func searchForAuthentication(
        in cookieStore: WKHTTPCookieStore
    ) {
        cookieStore.getAllCookies {
            [weak self] cookies in
            guard
                let self,
                !self.isFinished
            else {
                return
            }
            guard
                let header =
                    MiMoLoginDetector.cookieHeader(
                        in: cookies
                    ),
                header != self.lastRejectedHeader
            else {
                return
            }
            self.validateCandidate(header)
        }
    }

    private func validateCandidate(
        _ header: String
    ) {
        guard !isValidating else {
            hasPendingCandidate = true
            return
        }
        isValidating = true
        Task { @MainActor in
            let isAuthenticated =
                await validate(header)
            isValidating = false
            guard !isFinished else {
                return
            }
            if
                isAuthenticated,
                let credential = MiMoWebCredential(
                    cookieHeader: header
                )
            {
                complete(with: credential)
                return
            }
            lastRejectedHeader = header
            if hasPendingCandidate {
                hasPendingCandidate = false
                if let cookieStore {
                    searchForAuthentication(
                        in: cookieStore
                    )
                }
            }
        }
    }

    private func complete(
        with credential: MiMoWebCredential
    ) {
        guard !isFinished else {
            return
        }
        isFinished = true
        cookieStore?.remove(self)
        cookieStore = nil
        onAuthenticated(credential)
    }

    private static func probeTokenPlanUsage(
        cookieHeader: String
    ) async -> Bool {
        guard
            let credential = MiMoWebCredential(
                cookieHeader: cookieHeader
            )
        else {
            return false
        }
        let accountID = UUID()
        let adapter = MiMoUsageAdapter(
            credentialStore:
                EphemeralMiMoCredentialStore(
                    credential: credential,
                    accountID: accountID
                )
        )
        do {
            _ = try await adapter.fetchUsage(
                for: SubscriptionAccount(
                    id: accountID,
                    provider: .mimo,
                    displayName: "MiMo",
                    displayOrder: 0
                ),
                now: Date()
            )
            return true
        } catch {
            return false
        }
    }
}

extension MiMoLoginSession:
    WKNavigationDelegate,
    WKHTTPCookieStoreObserver
{
    func cookiesDidChange(
        in cookieStore: WKHTTPCookieStore
    ) {
        searchForAuthentication(
            in: cookieStore
        )
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        onPageReady()
        searchForAuthentication(
            in: webView.configuration
                .websiteDataStore
                .httpCookieStore
        )
    }
}

private actor EphemeralMiMoCredentialStore:
    CredentialStore
{
    private var data: Data?
    private let accountID: UUID

    init(
        credential: MiMoWebCredential,
        accountID: UUID
    ) {
        data = try? JSONEncoder().encode(credential)
        self.accountID = accountID
    }

    func saveData(
        _ data: Data,
        for accountID: UUID
    ) {
        guard accountID == self.accountID else {
            return
        }
        self.data = data
    }

    func loadData(for accountID: UUID) -> Data? {
        accountID == self.accountID ? data : nil
    }

    func delete(for accountID: UUID) {
        guard accountID == self.accountID else {
            return
        }
        data = nil
    }
}
