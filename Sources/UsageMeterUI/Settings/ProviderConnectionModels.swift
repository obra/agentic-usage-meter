import Foundation
import Observation
import UsageMeterCore

public enum ProviderConnectionInputError:
    Error,
    Equatable,
    Sendable
{
    case emptyDisplayName
    case authorizationNotComplete
}

public enum CodexConnectionPhase: Equatable, Sendable {
    case idle
    case authenticating
    case confirmingIdentity(email: String?, plan: String?)
    case duplicateIdentity(email: String?)
    case saving
    case complete
    case failed(String)
}

@MainActor
@Observable
public final class CodexConnectionModel {
    public typealias Authenticate =
        @MainActor @Sendable () async throws -> CodexOAuthResult

    public private(set) var phase = CodexConnectionPhase.idle

    @ObservationIgnored
    private let appModel: AppModel
    @ObservationIgnored
    private let accountID: UUID
    @ObservationIgnored
    private let reconnectingAccount: SubscriptionAccount?
    @ObservationIgnored
    private let authenticate: Authenticate
    @ObservationIgnored
    private var pendingResult: CodexOAuthResult?

    public init(
        appModel: AppModel,
        accountID: UUID = UUID(),
        reconnectingAccount: SubscriptionAccount? = nil,
        authenticate: @escaping Authenticate = {
            try await CodexOAuthFlow().authenticate()
        },
    ) {
        self.appModel = appModel
        self.accountID = reconnectingAccount?.id ?? accountID
        self.reconnectingAccount = reconnectingAccount
        self.authenticate = authenticate
    }

    public func start() async {
        phase = .authenticating
        pendingResult = nil
        do {
            let result = try await authenticate()
            if
                let providerAccountID =
                result.identity.accountID
                    ?? result.credential.accountID,
                    await appModel.hasCodexAccount(
                        providerAccountID: providerAccountID,
                        excluding: reconnectingAccount?.id,
                    )
            {
                phase = .duplicateIdentity(
                    email: result.identity.email,
                )
                return
            }
            pendingResult = result
            phase = .confirmingIdentity(
                email: result.identity.email,
                plan: result.identity.plan,
            )
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed("Codex authorization failed.")
        }
    }

    public func save(displayName: String) async throws {
        let displayName = try validatedDisplayName(displayName)
        guard let pendingResult else {
            throw ProviderConnectionInputError
                .authorizationNotComplete
        }

        phase = .saving
        do {
            let identity =
                pendingResult.identity.email
                    ?? pendingResult.identity.plan
            if let reconnectingAccount {
                try await appModel.reconnectAccount(
                    id: reconnectingAccount.id,
                    credential: ProviderCredential.codex(
                        pendingResult.credential,
                    ),
                    authenticatedIdentity: identity,
                )
            } else {
                try await appModel.connectAccount(
                    SubscriptionAccount(
                        id: accountID,
                        provider: .codex,
                        displayName: displayName,
                        authenticatedIdentity: identity,
                        displayOrder: appModel.accounts.count {
                            $0.account.provider == .codex
                        },
                    ),
                    credential: ProviderCredential.codex(
                        pendingResult.credential,
                    ),
                )
            }
            self.pendingResult = nil
            phase = .complete
        } catch {
            phase = .failed("Codex usage validation failed.")
            throw error
        }
    }

    public func cancel() {
        pendingResult = nil
        phase = .idle
    }
}

public enum KimiConnectionPhase: Equatable, Sendable {
    case idle
    case authorizing
    case waitingForApproval
    case readyToSave
    case saving
    case complete
    case failed(String)
}

@MainActor
@Observable
public final class KimiConnectionModel {
    public typealias Authenticate =
        @Sendable (
            @escaping KimiOAuthFlow.AuthorizationUpdate
        ) async throws -> OAuthCredential

    public private(set) var phase = KimiConnectionPhase.idle
    public private(set) var prompt: KimiAuthorizationPrompt?

    @ObservationIgnored
    private let appModel: AppModel
    @ObservationIgnored
    private let accountID: UUID
    @ObservationIgnored
    private let reconnectingAccount: SubscriptionAccount?
    @ObservationIgnored
    private let authenticate: Authenticate
    @ObservationIgnored
    private var pendingCredential: OAuthCredential?

    public init(
        appModel: AppModel,
        accountID: UUID = UUID(),
        reconnectingAccount: SubscriptionAccount? = nil,
        authenticate: @escaping Authenticate,
    ) {
        self.appModel = appModel
        self.accountID = reconnectingAccount?.id ?? accountID
        self.reconnectingAccount = reconnectingAccount
        self.authenticate = authenticate
    }

    public static func live(
        appModel: AppModel,
        reconnectingAccount: SubscriptionAccount? = nil,
    ) -> KimiConnectionModel {
        let accountID = reconnectingAccount?.id ?? UUID()
        let device = KimiDeviceInfo.currentMac(
            accountID: accountID,
        )
        return KimiConnectionModel(
            appModel: appModel,
            accountID: accountID,
            reconnectingAccount: reconnectingAccount,
            authenticate: { onPrompt in
                try await KimiOAuthFlow(
                    device: device,
                ).authenticate(onPrompt: onPrompt)
            },
        )
    }

    public func start() async {
        phase = .authorizing
        prompt = nil
        pendingCredential = nil
        do {
            let credential = try await authenticate {
                [weak self] prompt in
                await MainActor.run {
                    self?.prompt = prompt
                    self?.phase = .waitingForApproval
                }
            }
            pendingCredential = credential
            phase = .readyToSave
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed("Kimi authorization failed.")
        }
    }

    public func save(displayName: String) async throws {
        let displayName = try validatedDisplayName(displayName)
        guard let pendingCredential else {
            throw ProviderConnectionInputError
                .authorizationNotComplete
        }

        phase = .saving
        do {
            if let reconnectingAccount {
                try await appModel.reconnectAccount(
                    id: reconnectingAccount.id,
                    credential: ProviderCredential.kimi(pendingCredential),
                )
            } else {
                try await appModel.connectAccount(
                    SubscriptionAccount(
                        id: accountID,
                        provider: .kimi,
                        displayName: displayName,
                        displayOrder: appModel.accounts.count {
                            $0.account.provider == .kimi
                        },
                    ),
                    credential: ProviderCredential.kimi(pendingCredential),
                )
            }
            self.pendingCredential = nil
            phase = .complete
        } catch {
            phase = .failed("Kimi usage validation failed.")
            throw error
        }
    }

    public func cancel() {
        pendingCredential = nil
        prompt = nil
        phase = .idle
    }
}

public enum GitHubCopilotConnectionPhase:
    Equatable,
    Sendable
{
    case idle
    case authorizing
    case waitingForApproval
    case readyToSave(login: String)
    case duplicateIdentity(login: String)
    case saving
    case complete
    case failed(String)
}

@MainActor
@Observable
public final class GitHubCopilotConnectionModel {
    public typealias Authenticate =
        @Sendable (
            @escaping GitHubCopilotOAuthFlow
                .AuthorizationUpdate
        ) async throws -> GitHubCopilotOAuthResult

    public private(set) var phase =
        GitHubCopilotConnectionPhase.idle
    public private(set) var prompt:
        GitHubCopilotAuthorizationPrompt?

    @ObservationIgnored
    private let appModel: AppModel
    @ObservationIgnored
    private let accountID: UUID
    @ObservationIgnored
    private let reconnectingAccount:
        SubscriptionAccount?
    @ObservationIgnored
    private let authenticate: Authenticate
    @ObservationIgnored
    private var pendingResult:
        GitHubCopilotOAuthResult?

    public init(
        appModel: AppModel,
        accountID: UUID = UUID(),
        reconnectingAccount:
            SubscriptionAccount? = nil,
        authenticate:
            @escaping Authenticate = {
                onPrompt in
                try await GitHubCopilotOAuthFlow()
                    .authenticate(
                        onPrompt: onPrompt
                    )
            }
    ) {
        self.appModel = appModel
        self.accountID =
            reconnectingAccount?.id ?? accountID
        self.reconnectingAccount =
            reconnectingAccount
        self.authenticate = authenticate
    }

    public func start() async {
        phase = .authorizing
        prompt = nil
        pendingResult = nil
        do {
            let result = try await authenticate {
                [weak self] prompt in
                await MainActor.run {
                    self?.prompt = prompt
                    self?.phase =
                        .waitingForApproval
                }
            }
            if
                await appModel
                    .hasGitHubCopilotAccount(
                        userID:
                            result.credential.userID,
                        excluding:
                            reconnectingAccount?.id
                    )
            {
                phase = .duplicateIdentity(
                    login:
                        result.credential.login
                )
                return
            }
            pendingResult = result
            phase = .readyToSave(
                login:
                    result.credential.login
            )
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed(
                "GitHub authorization failed."
            )
        }
    }

    public func save(
        displayName: String
    ) async throws {
        let displayName =
            try validatedDisplayName(
                displayName
            )
        guard let pendingResult else {
            throw ProviderConnectionInputError
                .authorizationNotComplete
        }

        phase = .saving
        do {
            let credential =
                pendingResult.credential
            if let reconnectingAccount {
                try await appModel.reconnectAccount(
                    id: reconnectingAccount.id,
                    credential: credential,
                    authenticatedIdentity:
                        credential.login
                )
            } else {
                try await appModel.connectAccount(
                    SubscriptionAccount(
                        id: accountID,
                        provider:
                            .githubCopilot,
                        displayName: displayName,
                        authenticatedIdentity:
                            credential.login,
                        displayOrder:
                            appModel.accounts.count {
                                $0.account.provider
                                    == .githubCopilot
                            }
                    ),
                    credential: credential
                )
            }
            self.pendingResult = nil
            phase = .complete
        } catch {
            phase = .failed(
                "GitHub Copilot usage validation failed."
            )
            throw error
        }
    }

    public func cancel() {
        pendingResult = nil
        prompt = nil
        phase = .idle
    }
}

private func validatedDisplayName(
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
