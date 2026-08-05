import Foundation
import Observation
import UsageMeterCore
import UsageMeterWeb
import WebKit

public enum MiMoConnectionPhase:
    Equatable,
    Sendable
{
    case idle
    case signingIn
    case readyToSave
    case saving
    case complete
    case failed(String)
}

@MainActor
@Observable
public final class MiMoConnectionModel {
    public typealias Authenticate =
        @MainActor @Sendable () async throws
        -> MiMoWebCredential
    public typealias RemoveProfile =
        @MainActor @Sendable (
            UUID
        ) async throws -> Void

    public private(set) var phase =
        MiMoConnectionPhase.idle
    public private(set) var webView: WKWebView?
    public private(set) var hasRenderedLoginPage =
        false

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
    private var loginSession: MiMoLoginSession?
    @ObservationIgnored
    private var pendingCredential: MiMoWebCredential?
    @ObservationIgnored
    private var didSave = false
    @ObservationIgnored
    private var didRemoveProfile = false

    public init(
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
                accept(try await authenticate())
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .failed(
                    "MiMo sign-in failed."
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
            try validatedMiMoDisplayName(
                displayName
            )
        guard let pendingCredential else {
            throw ProviderConnectionInputError
                .authorizationNotComplete
        }

        phase = .saving
        do {
            if let reconnectingAccount {
                try await appModel.reconnectAccount(
                    id: reconnectingAccount.id,
                    credential:
                        pendingCredential
                )
            } else {
                try await appModel.connectAccount(
                    SubscriptionAccount(
                        id: accountID,
                        provider: .mimo,
                        displayName: displayName,
                        displayOrder:
                            appModel.accounts.count {
                                $0.account.provider
                                    == .mimo
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
                "MiMo usage validation failed."
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
        let session = MiMoLoginSession(
            accountID: accountID,
            onPageReady: {
                [weak self] in
                self?.hasRenderedLoginPage =
                    true
            },
            onAuthenticated: {
                [weak self] credential in
                self?.accept(credential)
            }
        )
        loginSession = session
        webView = session.start()
    }

    private func accept(
        _ credential: MiMoWebCredential
    ) {
        closeLoginSession()
        pendingCredential = credential
        phase = .readyToSave
    }

    private func closeLoginSession() {
        loginSession?.close()
        loginSession = nil
        webView = nil
    }
}

private func validatedMiMoDisplayName(
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
