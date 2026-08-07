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

public struct ClaudeOrganizationChoice:
    Equatable,
    Identifiable,
    Sendable
{
    public let organization: ClaudeOrganization
    public let connectedAccountName: String?
    public var isSelected: Bool

    public var id: UUID {
        organization.id
    }
}

public struct ClaudeOrganizationConnection:
    Equatable,
    Identifiable,
    Sendable
{
    public let accountID: UUID
    public let organizationID: UUID
    public let organizationName: String
    public let snapshot: UsageSnapshot?

    public var id: UUID {
        accountID
    }
}

public enum ClaudeConnectionPhase: Equatable, Sendable {
    case idle
    case signingIn
    case loadingOrganizations
    case choosingOrganizations([ClaudeOrganizationChoice])
    case loadingUsage
    case readyToSave(
        organizationName: String,
        organizationCount: Int,
    )
    case readyToSaveOrganizations([ClaudeOrganizationConnection])
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
    private(set) var profileID: UUID
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
    private var pendingChoices: [ClaudeOrganizationChoice] = []
    @ObservationIgnored
    private var pendingSelection: [ClaudeOrganizationConnection] = []
    @ObservationIgnored
    private var authenticatedCookies: [HTTPCookie]?
    @ObservationIgnored
    private var qualifiedOrganizationIDs: Set<UUID> = []
    @ObservationIgnored
    private var didSave = false
    @ObservationIgnored
    private var isSaving = false
    @ObservationIgnored
    private var pendingCancellation = false
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
        pendingChoices = []
        pendingSelection = []
        authenticatedCookies = nil
        qualifiedOrganizationIDs = []
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
            await qualifyLogin(
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
        isSaving = true
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
                    qualifiedOrganizationIDs:
                    qualifiedOrganizationIDs,
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
            await finishSaveAttempt()
            throw error
        }
        await finishSaveAttempt()
    }

    public func cancel() async {
        guard !didSave, !didRemoveProfile else {
            return
        }
        // A save that is still writing may yet succeed; deleting the
        // profile out from under it would break the saved accounts.
        // The cancellation runs after the save, if the save fails.
        if isSaving {
            pendingCancellation = true
            return
        }

        await performCancellation()
    }

    private func performCancellation() async {
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

    private func finishSaveAttempt() async {
        isSaving = false
        if pendingCancellation {
            pendingCancellation = false
            if !didSave {
                await performCancellation()
            }
        }
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
                Task { @MainActor [weak self] in
                    await self?.qualifyLogin(
                        authenticatedCookies: cookies,
                    )
                }
            },
        )
        loginSession = session
        webView = session.start()
    }

    func qualifyLogin(
        authenticatedCookies: [HTTPCookie],
    ) async {
        self.authenticatedCookies = authenticatedCookies
        phase = .loadingOrganizations
        let usageClient = usageClient.authenticated(
            with: authenticatedCookies,
        )
        let retrier = ClaudeFreshSessionRetrier()

        let organizations: [ClaudeOrganization]
        do {
            organizations =
                ClaudeOrganizationSelection.qualified(
                    from: try await retrier.run {
                        try await usageClient.organizations(
                            profileID: profileID,
                        )
                    },
                )
        } catch {
            phase = .failed(
                ClaudeConnectionFailureDescription
                    .message(
                        for: error,
                        stage: .organizations,
                    ),
            )
            return
        }
        qualifiedOrganizationIDs = Set(organizations.map(\.id))

        if let reconnectingAccount {
            guard
                let organization = organizations.first(
                    where: {
                        $0.id
                            == reconnectingAccount
                            .claudeOrganizationID
                    },
                )
            else {
                closeLogin()
                // The captured login is deterministically wrong for
                // this account; retrying must start a fresh sign-in
                // from a clean profile instead of revalidating it.
                // Abandoning the provisional profile for a fresh one
                // keeps that true even when its cleanup fails.
                self.authenticatedCookies = nil
                qualifiedOrganizationIDs = []
                try? await removeProfile(profileID)
                profileID = UUID()
                phase = .failed(
                    "This Claude login does not belong to the organization \(reconnectingAccount.displayName) was connected to.",
                )
                return
            }
            await qualifySingle(
                organization: organization,
                organizationCount: organizations.count,
                usageClient: usageClient,
                retrier: retrier,
            )
            return
        }

        guard let organization = organizations.first else {
            phase = .failed(
                ClaudeConnectionFailureDescription
                    .message(
                        for: ProviderClientError
                            .unsupportedResponse,
                        stage: .organizations,
                    ),
            )
            return
        }
        if organizations.count == 1 {
            await qualifySingle(
                organization: organization,
                organizationCount: 1,
                usageClient: usageClient,
                retrier: retrier,
            )
            return
        }

        closeLogin()
        pendingChoices = Self.organizationChoices(
            from: organizations,
            existingAccounts: appModel.accounts.map(\.account),
        )
        phase = .choosingOrganizations(pendingChoices)
    }

    public func toggleOrganization(id: UUID) {
        guard
            case .choosingOrganizations = phase,
            let index = pendingChoices.firstIndex(
                where: { $0.id == id },
            )
        else {
            return
        }
        pendingChoices[index].isSelected.toggle()
        phase = .choosingOrganizations(pendingChoices)
    }

    public func confirmOrganizationSelection() async {
        guard case .choosingOrganizations = phase else {
            return
        }
        let selected = pendingChoices.filter(\.isSelected)
        guard
            !selected.isEmpty,
            let authenticatedCookies
        else {
            return
        }

        phase = .loadingUsage
        let usageClient = usageClient.authenticated(
            with: authenticatedCookies,
        )
        let retrier = ClaudeFreshSessionRetrier()
        var connections: [ClaudeOrganizationConnection] = []
        for choice in selected {
            let accountID = UUID()
            let snapshot: UsageSnapshot?
            do {
                snapshot = try await Self.loadSnapshot(
                    usageClient: usageClient,
                    accountID: accountID,
                    profileID: profileID,
                    organizationID: choice.organization.id,
                    retrier: retrier,
                )
            } catch {
                phase = .failed(
                    ClaudeConnectionFailureDescription
                        .message(
                            for: error,
                            stage: .usage,
                        ),
                )
                return
            }
            connections.append(
                ClaudeOrganizationConnection(
                    accountID: accountID,
                    organizationID: choice.organization.id,
                    organizationName: choice.organization.name,
                    snapshot: snapshot,
                ),
            )
        }
        pendingSelection = connections
        phase = .readyToSaveOrganizations(connections)
    }

    public func saveSelectedOrganizations() async {
        guard
            case .readyToSaveOrganizations = phase,
            !pendingSelection.isEmpty
        else {
            return
        }

        phase = .saving
        isSaving = true
        let firstDisplayOrder = appModel.accounts.count {
            $0.account.provider == .claude
        }
        let connections = pendingSelection.enumerated().map {
            offset,
                connection in
            (
                account: SubscriptionAccount(
                    id: connection.accountID,
                    provider: .claude,
                    displayName: connection.organizationName,
                    authenticatedIdentity:
                    connection.organizationName,
                    displayOrder: firstDisplayOrder + offset,
                    claudeProfileID: profileID,
                    claudeOrganizationID:
                    connection.organizationID,
                ),
                snapshot: connection.snapshot
            )
        }
        do {
            try await appModel.connectClaudeAccounts(connections)
        } catch {
            phase = .failed(
                "Claude accounts could not be saved.",
            )
            await finishSaveAttempt()
            return
        }
        didSave = true
        pendingSelection = []
        phase = .complete
        await finishSaveAttempt()
    }

    private func qualifySingle(
        organization: ClaudeOrganization,
        organizationCount: Int,
        usageClient: ClaudeWebUsageClient,
        retrier: ClaudeFreshSessionRetrier,
    ) async {
        phase = .loadingUsage
        let snapshot: UsageSnapshot?
        do {
            snapshot = try await Self.loadSnapshot(
                usageClient: usageClient,
                accountID: accountID,
                profileID: profileID,
                organizationID: organization.id,
                retrier: retrier,
            )
        } catch {
            phase = .failed(
                ClaudeConnectionFailureDescription
                    .message(
                        for: error,
                        stage: .usage,
                    ),
            )
            return
        }
        closeLogin()
        do {
            try accept(
                ClaudeQualifiedConnection(
                    organizationID: organization.id,
                    organizationName: organization.name,
                    organizationCount: organizationCount,
                    snapshot: snapshot,
                ),
            )
        } catch {
            phase = .failed(
                ClaudeConnectionFailureDescription
                    .message(
                        for: error,
                        stage: .usage,
                    ),
            )
        }
    }

    private func closeLogin() {
        loginSession?.close()
        loginSession = nil
        webView = nil
    }

    static func organizationChoices(
        from organizations: [ClaudeOrganization],
        existingAccounts: [SubscriptionAccount],
    ) -> [ClaudeOrganizationChoice] {
        organizations.map { organization in
            // A different login can hold its own seat in the same
            // organization, so already-metered organizations remain
            // selectable; they just start unchecked.
            let connectedAccountName = existingAccounts.first {
                $0.provider == .claude
                    && $0.claudeOrganizationID == organization.id
            }?.displayName
            return ClaudeOrganizationChoice(
                organization: organization,
                connectedAccountName: connectedAccountName,
                isSelected: connectedAccountName == nil,
            )
        }
    }

    // A usage payload the decoder rejects will not improve on refresh,
    // so it fails qualification instead of saving an account that can
    // never show data. Transient failures still qualify without a
    // snapshot.
    static func loadSnapshot(
        usageClient: ClaudeWebUsageClient,
        accountID: UUID,
        profileID: UUID,
        organizationID: UUID,
        retrier: ClaudeFreshSessionRetrier,
    ) async throws -> UsageSnapshot? {
        do {
            return try await retrier.run {
                try await usageClient.fetchUsage(
                    accountID: accountID,
                    profileID: profileID,
                    organizationID: organizationID,
                    now: Date(),
                )
            }
        } catch ProviderClientError.unsupportedResponse {
            throw ProviderClientError.unsupportedResponse
        } catch {
            return nil
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
