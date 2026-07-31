import Foundation
import Observation
import UsageMeterCore
import UsageMeterWeb
import WebKit

public enum OpenCodeConnectionPhase:
    Equatable,
    Sendable
{
    case idle
    case signingIn
    case readyToSave(workspaceID: String)
    case duplicateIdentity(workspaceID: String)
    case saving
    case complete
    case failed(String)
}

@MainActor
@Observable
public final class OpenCodeConnectionModel {
    public typealias Authenticate =
        @MainActor @Sendable () async throws
        -> OpenCodeDashboardCredential
    public typealias RemoveProfile =
        @MainActor @Sendable (
            UUID
        ) async throws -> Void

    public private(set) var phase =
        OpenCodeConnectionPhase.idle
    public private(set) var webView: WKWebView?
    public private(set) var hasRenderedLoginPage =
        false

    @ObservationIgnored
    private let provider: Provider
    @ObservationIgnored
    private let appModel: AppModel
    @ObservationIgnored
    private let accountID: UUID
    @ObservationIgnored
    private let reconnectingAccount: SubscriptionAccount?
    @ObservationIgnored
    private let authenticate: Authenticate?
    @ObservationIgnored
    private let removeProfile: RemoveProfile
    @ObservationIgnored
    private var loginSession: OpenCodeLoginSession?
    @ObservationIgnored
    private var pendingCredential: OpenCodeDashboardCredential?
    @ObservationIgnored
    private var didSave = false
    @ObservationIgnored
    private var didRemoveProfile = false

    public init(
        provider: Provider,
        appModel: AppModel,
        accountID: UUID = UUID(),
        reconnectingAccount:
            SubscriptionAccount? = nil,
        authenticate: Authenticate? = nil,
        removeProfile:
            @escaping RemoveProfile = {
                try await AccountWebProfileStore
                    .remove(accountID: $0)
            }
    ) {
        precondition(
            provider == .openCodeGo
                || provider == .openCodeZen
        )
        self.provider = provider
        self.appModel = appModel
        self.accountID =
            reconnectingAccount?.id
            ?? accountID
        self.reconnectingAccount =
            reconnectingAccount
        self.authenticate = authenticate
        self.removeProfile = removeProfile
    }

    public func start() async {
        loginSession?.close()
        loginSession = nil
        webView = nil
        pendingCredential = nil
        didSave = false
        hasRenderedLoginPage = false
        if let authenticate {
            phase = .signingIn
            do {
                await accept(
                    try await authenticate()
                )
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .failed(
                    "OpenCode sign-in failed."
                )
            }
            return
        }
        startInteractiveLogin()
    }

    public func save(
        displayName: String
    ) async throws {
        let displayName =
            try validatedOpenCodeDisplayName(
                displayName
            )
        guard let pendingCredential else {
            throw ProviderConnectionInputError
                .authorizationNotComplete
        }
        guard
            let workspaceID =
                pendingCredential.identityKey
        else {
            throw ProviderConnectionInputError
                .authorizationNotComplete
        }

        phase = .saving
        do {
            if let reconnectingAccount {
                try await appModel.reconnectAccount(
                    id: reconnectingAccount.id,
                    credential:
                        pendingCredential,
                    authenticatedIdentity:
                        workspaceID
                )
            } else {
                try await appModel.connectAccount(
                    SubscriptionAccount(
                        id: accountID,
                        provider: provider,
                        displayName: displayName,
                        authenticatedIdentity:
                            workspaceID,
                        displayOrder:
                            appModel.accounts.count {
                                $0.account.provider
                                    == provider
                            }
                    ),
                    credential:
                        pendingCredential
                )
            }
            didSave = true
            self.pendingCredential = nil
            phase = .complete
        } catch {
            phase = .failed(
                "OpenCode usage validation failed."
            )
            throw error
        }
    }

    public func cancel() async {
        guard
            !didSave,
            !didRemoveProfile
        else {
            return
        }
        pendingCredential = nil
        loginSession?.close()
        loginSession = nil
        webView = nil
        if reconnectingAccount == nil {
            try? await removeProfile(
                accountID
            )
            didRemoveProfile = true
        }
        phase = .idle
    }

    private func startInteractiveLogin() {
        guard loginSession == nil else {
            return
        }
        phase = .signingIn
        let session = OpenCodeLoginSession(
            accountID: accountID,
            onPageReady: {
                [weak self] in
                self?.hasRenderedLoginPage =
                    true
            },
            onAuthenticated: {
                [weak self] credential in
                guard let self else {
                    return
                }
                Task { @MainActor in
                    await self.accept(
                        credential
                    )
                }
            }
        )
        loginSession = session
        webView = session.start()
    }

    private func accept(
        _ credential:
            OpenCodeDashboardCredential
    ) async {
        guard
            let workspaceID =
                credential.identityKey,
            !credential.authCookie.isEmpty
        else {
            closeLoginSession()
            phase = .failed(
                "OpenCode sign-in did not return a workspace."
            )
            return
        }
        closeLoginSession()
        if await appModel.hasOpenCodeAccount(
            provider: provider,
            workspaceID: workspaceID,
            excluding:
                reconnectingAccount?.id
        ) {
            phase = .duplicateIdentity(
                workspaceID: workspaceID
            )
            return
        }
        pendingCredential = credential
        phase = .readyToSave(
            workspaceID: workspaceID
        )
    }

    private func closeLoginSession() {
        loginSession?.close()
        loginSession = nil
        webView = nil
    }
}

private func validatedOpenCodeDisplayName(
    _ value: String
) throws -> String {
    let displayName =
        value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    guard !displayName.isEmpty else {
        throw ProviderConnectionInputError
            .emptyDisplayName
    }
    return displayName
}
