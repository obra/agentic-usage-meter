import Foundation
import Observation
import UsageMeterClaudeWeb
import UsageMeterCore
import WebKit

public struct ClaudeQualifiedConnection:
    Equatable,
    Sendable
{
    public let organizationID: UUID
    public let organizationName: String
    public let organizationCount: Int
    public let snapshot: UsageSnapshot?

    public init(
        organizationID: UUID,
        organizationName: String,
        organizationCount: Int,
        snapshot: UsageSnapshot?,
    ) {
        self.organizationID = organizationID
        self.organizationName = organizationName
        self.organizationCount = organizationCount
        self.snapshot = snapshot
    }
}

public enum ClaudeConnectionPhase: Equatable, Sendable {
    case idle
    case signingIn
    case loadingOrganizations
    case loadingUsage
    case readyToSave(
        organizationName: String,
        organizationCount: Int,
    )
    case saving
    case complete
    case failed(String)
}

enum ClaudeConnectionStage {
    case organizations
    case usage
}

struct ClaudeConnectionFailureDescription {
    static func message(
        for error: any Error,
        stage: ClaudeConnectionStage,
    ) -> String {
        guard let error = error as? ProviderClientError else {
            return fallbackMessage(for: stage)
        }

        switch error {
        case .credentialMismatch:
            return "Claude returned credentials that do not match this connection."
        case .subscriptionRequired:
            return "The selected Claude subscription is not active."
        case .unsupportedResponse:
            switch stage {
            case .organizations:
                return "Claude returned an organizations response this app does not understand."
            case .usage:
                return "Claude returned a usage response this app does not understand."
            }
        case .reauthenticationRequired:
            return "Claude rejected the signed-in session while loading \(stage.requestName), even after retrying."
        case .retryAfter:
            return "Claude rate limited the \(stage.requestName) request. Try again later."
        case .temporaryFailure:
            return "Claude encountered a temporary network or provider failure while loading \(stage.requestName)."
        }
    }

    private static func fallbackMessage(
        for stage: ClaudeConnectionStage,
    ) -> String {
        "Claude connection failed while loading \(stage.requestName)."
    }
}

extension ClaudeConnectionStage {
    fileprivate var requestName: String {
        switch self {
        case .organizations:
            "organizations"
        case .usage:
            "usage"
        }
    }
}

@MainActor
struct ClaudeFreshSessionRetrier {
    typealias Sleep = @MainActor (Int) async throws -> Void

    let maximumAttempts: Int
    private let sleep: Sleep

    init(
        maximumAttempts: Int = 4,
        sleep: @escaping Sleep = { attempt in
            try await Task.sleep(
                for: .milliseconds(1_500 * attempt),
            )
        },
    ) {
        self.maximumAttempts = maximumAttempts
        self.sleep = sleep
    }

    func run<T>(
        _ operation: @MainActor () async throws -> T,
    ) async throws -> T {
        var attempt = 1
        while true {
            do {
                return try await operation()
            } catch let error as ProviderClientError {
                guard
                    error == .reauthenticationRequired,
                    attempt < maximumAttempts
                else {
                    throw error
                }
                try await sleep(attempt)
                attempt += 1
            }
        }
    }
}

@MainActor
@Observable
public final class ClaudeConnectionModel {
    public typealias Qualify =
        @MainActor @Sendable () async throws
            -> ClaudeQualifiedConnection
    public typealias RemoveProfile =
        @MainActor @Sendable (UUID) async throws -> Void

    public private(set) var phase = ClaudeConnectionPhase.idle
    public private(set) var hasRenderedLoginPage = false
    public private(set) var webView: WKWebView?

    @ObservationIgnored
    private let appModel: AppModel
    @ObservationIgnored
    private let accountID: UUID
    @ObservationIgnored
    private let profileID: UUID
    @ObservationIgnored
    private let reconnectingAccount: SubscriptionAccount?
    @ObservationIgnored
    private let qualify: Qualify?
    @ObservationIgnored
    private let removeProfile: RemoveProfile
    @ObservationIgnored
    private let usageClient: ClaudeWebUsageClient
    @ObservationIgnored
    private var loginSession: ClaudeLoginSession?
    @ObservationIgnored
    private var pendingConnection: ClaudeQualifiedConnection?
    @ObservationIgnored
    private var authenticatedCookies: [HTTPCookie]?
    @ObservationIgnored
    private var didSave = false
    @ObservationIgnored
    private var didRemoveProfile = false

    public init(
        appModel: AppModel,
        accountID: UUID = UUID(),
        profileID: UUID = UUID(),
        reconnectingAccount: SubscriptionAccount? = nil,
        qualify: Qualify? = nil,
        removeProfile: @escaping RemoveProfile = {
            try await ClaudeWebProfileStore.remove(
                profileID: $0,
            )
        },
        usageClient: ClaudeWebUsageClient =
            ClaudeWebUsageClient(),
    ) {
        self.appModel = appModel
        self.accountID = reconnectingAccount?.id ?? accountID
        self.profileID = profileID
        self.reconnectingAccount = reconnectingAccount
        self.qualify = qualify
        self.removeProfile = removeProfile
        self.usageClient = usageClient
    }

    public func start() async {
        pendingConnection = nil
        authenticatedCookies = nil
        didSave = false
        if let qualify {
            phase = .loadingUsage
            do {
                try await accept(qualify())
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .failed(
                    ClaudeConnectionFailureDescription
                        .message(
                            for: error,
                            stage: .usage,
                        ),
                )
            }
            return
        }

        startInteractiveLogin()
    }

    public func retry() async {
        if let authenticatedCookies {
            loadQualifiedAccount(
                authenticatedCookies:
                authenticatedCookies,
            )
        } else {
            await start()
        }
    }

    public func save(displayName: String) async throws {
        let displayName = try validatedClaudeDisplayName(
            displayName,
        )
        guard let pendingConnection else {
            throw ProviderConnectionInputError
                .authorizationNotComplete
        }

        phase = .saving
        do {
            let replacement = SubscriptionAccount(
                id: accountID,
                provider: .claude,
                displayName: displayName,
                authenticatedIdentity:
                pendingConnection.organizationName,
                displayOrder:
                reconnectingAccount?.displayOrder
                    ?? appModel.accounts.count {
                        $0.account.provider == .claude
                    },
                claudeProfileID: profileID,
                claudeOrganizationID:
                pendingConnection.organizationID,
            )
            if let reconnectingAccount {
                try await appModel.reconnectClaudeAccount(
                    id: reconnectingAccount.id,
                    replacement: replacement,
                    snapshot: pendingConnection.snapshot,
                )
            } else {
                try await appModel.connectClaudeAccount(
                    replacement,
                    snapshot: pendingConnection.snapshot,
                )
            }
            didSave = true
            self.pendingConnection = nil
            phase = .complete
        } catch {
            phase = .failed(
                "Claude account could not be saved.",
            )
            throw error
        }
    }

    public func cancel() async {
        guard !didSave, !didRemoveProfile else {
            return
        }

        pendingConnection = nil
        authenticatedCookies = nil
        if let loginSession {
            try? await loginSession.cancel()
            self.loginSession = nil
        } else {
            try? await removeProfile(profileID)
        }
        didRemoveProfile = true
        webView = nil
        phase = .idle
    }

    private func startInteractiveLogin() {
        guard loginSession == nil else {
            return
        }
        phase = .signingIn
        hasRenderedLoginPage = false

        let session = ClaudeLoginSession(
            profileID: profileID,
            onPageReady: { [weak self] in
                self?.hasRenderedLoginPage = true
            },
            onAuthenticated: {
                [weak self] _,
                    cookies in
                self?.authenticatedCookies = cookies
                self?.loadQualifiedAccount(
                    authenticatedCookies: cookies,
                )
            },
        )
        loginSession = session
        webView = session.start()
    }

    private func loadQualifiedAccount(
        authenticatedCookies: [HTTPCookie],
    ) {
        phase = .loadingOrganizations
        let usageClient = usageClient.authenticated(
            with: authenticatedCookies,
        )
        let retrier = ClaudeFreshSessionRetrier()

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            var stage = ClaudeConnectionStage.organizations
            do {
                let organizations =
                    try await retrier.run {
                        try await usageClient.organizations(
                            profileID: profileID,
                        )
                    }
                guard let organization = organizations.first else {
                    throw ProviderClientError
                        .unsupportedResponse
                }

                stage = .usage
                phase = .loadingUsage
                let snapshot: UsageSnapshot?
                do {
                    snapshot = try await retrier.run {
                        try await usageClient.fetchUsage(
                            accountID: accountID,
                            profileID: profileID,
                            organizationID: organization.id,
                            now: Date(),
                        )
                    }
                } catch {
                    snapshot = nil
                }
                loginSession?.close()
                loginSession = nil
                webView = nil
                try accept(
                    ClaudeQualifiedConnection(
                        organizationID: organization.id,
                        organizationName: organization.name,
                        organizationCount: organizations.count,
                        snapshot: snapshot,
                    ),
                )
            } catch {
                phase = .failed(
                    ClaudeConnectionFailureDescription
                        .message(
                            for: error,
                            stage: stage,
                        ),
                )
            }
        }
    }

    private func accept(
        _ connection: ClaudeQualifiedConnection,
    ) throws {
        guard
            connection.snapshot?.accountID == accountID
                || connection.snapshot == nil
        else {
            throw AppModelError.invalidSnapshot
        }
        pendingConnection = connection
        phase = .readyToSave(
            organizationName: connection.organizationName,
            organizationCount: connection.organizationCount,
        )
    }
}

private func validatedClaudeDisplayName(
    _ value: String,
) throws -> String {
    let displayName = value.trimmingCharacters(
        in: .whitespacesAndNewlines,
    )
    guard !displayName.isEmpty else {
        throw ProviderConnectionInputError.emptyDisplayName
    }
    return displayName
}
