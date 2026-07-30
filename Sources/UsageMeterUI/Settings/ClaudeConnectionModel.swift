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
    public let snapshot: UsageSnapshot

    public init(
        organizationID: UUID,
        organizationName: String,
        organizationCount: Int,
        snapshot: UsageSnapshot,
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
        didSave = false
        if let qualify {
            phase = .loadingUsage
            do {
                try await accept(qualify())
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .failed(
                    "Claude usage validation failed.",
                )
            }
            return
        }

        startInteractiveLogin()
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
            onAuthenticated: { [weak self] _ in
                self?.loadQualifiedAccount()
            },
        )
        loginSession = session
        webView = session.start()
    }

    private func loadQualifiedAccount() {
        phase = .loadingOrganizations

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                let organizations =
                    try await usageClient.organizations(
                        profileID: profileID,
                    )
                guard let organization = organizations.first else {
                    throw ProviderClientError
                        .unsupportedResponse
                }

                phase = .loadingUsage
                let snapshot = try await usageClient.fetchUsage(
                    accountID: accountID,
                    profileID: profileID,
                    organizationID: organization.id,
                    now: Date(),
                )
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
                    "Claude usage validation failed.",
                )
            }
        }
    }

    private func accept(
        _ connection: ClaudeQualifiedConnection,
    ) throws {
        guard connection.snapshot.accountID == accountID else {
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
