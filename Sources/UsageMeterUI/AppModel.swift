import Foundation
import Observation
import UsageMeterCore

public protocol AppStatePersisting: Sendable {
    func load() async throws -> PersistedAppState
    func save(_ state: PersistedAppState) async throws
}

extension AppStateStore: AppStatePersisting {}

public enum AccountViewError: Equatable, Sendable {
    case authenticationRequired
    case subscriptionRequired
    case temporarilyUnavailable
    case unsupportedResponse
}

public enum AppModelError: Error, Equatable, Sendable {
    case accountAlreadyExists
    case accountNotFound
    case emptyDisplayName
    case invalidAccountOrder
    case providerUnavailable
    case invalidSnapshot
}

public struct MenuBarSummary: Equatable, Sendable {
    public let text: String?
    public let systemImage: String

    public init(text: String?, systemImage: String) {
        self.text = text
        self.systemImage = systemImage
    }
}

public struct AccountViewState: Equatable, Identifiable, Sendable {
    public var account: SubscriptionAccount
    public var snapshot: UsageSnapshot?
    public var error: AccountViewError?
    public var nextEligibleAt: Date?
    public var isRefreshing: Bool

    public init(
        account: SubscriptionAccount,
        snapshot: UsageSnapshot?,
        error: AccountViewError? = nil,
        nextEligibleAt: Date? = nil,
        isRefreshing: Bool = false,
    ) {
        self.account = account
        self.snapshot = snapshot
        self.error = error
        self.nextEligibleAt = nextEligibleAt
        self.isRefreshing = isRefreshing
    }

    public var id: UUID {
        account.id
    }
}

@MainActor
@Observable
public final class AppModel {
    public typealias RefreshSleep =
        @Sendable (TimeInterval) async throws -> Void

    public private(set) var accounts: [AccountViewState] = []
    public private(set) var isFloatingWidgetVisible = false
    public private(set) var floatingWidgetPlacement:
        FloatingWidgetPlacement?
    public private(set) var collapsedUsageSections:
        Set<UsageSectionID> = []
    public let isSampleData: Bool

    @ObservationIgnored
    private let stateStore: any AppStatePersisting
    @ObservationIgnored
    private let credentialStore: any CredentialStore
    @ObservationIgnored
    private let adaptersByProvider: [Provider: any ProviderAccountAdapter]
    @ObservationIgnored
    private let refreshCoordinator: RefreshCoordinator
    @ObservationIgnored
    private let refreshPolicy: RefreshPolicy
    @ObservationIgnored
    private let now: @Sendable () -> Date
    @ObservationIgnored
    private var persistedState = PersistedAppState.empty
    @ObservationIgnored
    private var refreshers: [UUID: AccountRefresher] = [:]

    public init(
        stateStore: any AppStatePersisting,
        credentialStore: any CredentialStore,
        adapters: [any ProviderAccountAdapter],
        refreshCoordinator: RefreshCoordinator = RefreshCoordinator(),
        refreshPolicy: RefreshPolicy = .release,
        isSampleData: Bool = false,
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.stateStore = stateStore
        self.credentialStore = credentialStore
        adaptersByProvider = Dictionary(
            uniqueKeysWithValues: adapters.map {
                ($0.provider, $0)
            },
        )
        self.refreshCoordinator = refreshCoordinator
        self.refreshPolicy = refreshPolicy
        self.isSampleData = isSampleData
        self.now = now
    }

    public var menuBarSummary: MenuBarSummary {
        let tightest = UsageSummary.tightestWindow(
            in: accounts.compactMap(\.snapshot),
        )
        let text = tightest.map {
            "\(Int(($0.window.remainingFraction * 100).rounded()))%"
        }
        return MenuBarSummary(
            text: text,
            systemImage: "gauge.with.needle",
        )
    }

    public func start() async {
        do {
            let loaded = try await stateStore.load()
            persistedState = loaded
            isFloatingWidgetVisible =
                loaded.isFloatingWidgetVisible
            floatingWidgetPlacement =
                loaded.floatingWidgetPlacement
            collapsedUsageSections =
                loaded.collapsedUsageSections
            accounts = loaded.accounts
                .sorted(by: accountComesBefore)
                .map {
                    AccountViewState(
                        account: $0,
                        snapshot: loaded.snapshots[$0.id],
                        error:
                        loaded.refreshStates[$0.id]?
                            .requiresReauthentication == true
                            ? .authenticationRequired
                            : nil,
                    )
                }

            let now = now
            refreshers = Dictionary(
                uniqueKeysWithValues: loaded.accounts.map { account in
                    (
                        account.id,
                        AccountRefresher(
                            minimumInterval:
                                refreshPolicy.minimumProviderInterval,
                            state:
                            loaded.refreshStates[account.id]
                                ?? .initial,
                            lastGoodSnapshot:
                            loaded.snapshots[account.id],
                            now: { now() },
                        ),
                    )
                },
            )

            for account in accounts {
                await refreshAccount(id: account.id)
            }
        } catch {
            accounts = []
        }
    }

    public func refreshAllAccounts() async {
        let accountIDs = accounts.map(\.id)
        await refreshCoordinator.run(accountIDs: accountIDs) {
            [weak self] accountID in
            await self?.refreshAccount(id: accountID)
        }
    }

    public func refreshAfterWake() async {
        await refreshAllAccounts()
    }

    public func runAutomaticRefresh(
        sleep: @escaping RefreshSleep = { interval in
            try await Task.sleep(
                for: .milliseconds(
                    Int64((interval * 1_000).rounded()),
                ),
            )
        },
    ) async {
        let interval = refreshPolicy.automaticInterval
        while !Task.isCancelled {
            do {
                try await sleep(interval)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            await refreshAllAccounts()
        }
    }

    public func setFloatingWidgetVisible(
        _ isVisible: Bool,
    ) async throws {
        let previous = isFloatingWidgetVisible
        isFloatingWidgetVisible = isVisible
        persistedState.isFloatingWidgetVisible = isVisible
        do {
            try await stateStore.save(persistedState)
        } catch {
            isFloatingWidgetVisible = previous
            persistedState.isFloatingWidgetVisible = previous
            throw error
        }
    }

    public func setFloatingWidgetPlacement(
        _ placement: FloatingWidgetPlacement,
    ) async throws {
        let previous = floatingWidgetPlacement
        floatingWidgetPlacement = placement
        persistedState.floatingWidgetPlacement = placement
        do {
            try await stateStore.save(persistedState)
        } catch {
            floatingWidgetPlacement = previous
            persistedState.floatingWidgetPlacement = previous
            throw error
        }
    }

    public func toggleUsageSection(
        _ section: UsageSectionID,
    ) async throws {
        let previous = collapsedUsageSections
        if collapsedUsageSections.contains(section) {
            collapsedUsageSections.remove(section)
        } else {
            collapsedUsageSections.insert(section)
        }
        persistedState.collapsedUsageSections =
            collapsedUsageSections
        do {
            try await stateStore.save(persistedState)
        } catch {
            collapsedUsageSections = previous
            persistedState.collapsedUsageSections = previous
            throw error
        }
    }

    public func refreshAccount(id: UUID) async {
        guard
            let account = accounts.first(where: { $0.id == id })?.account,
            let refresher = refreshers[id]
        else {
            return
        }

        updateAccount(id: id) {
            $0.isRefreshing = true
        }

        do {
            let now = now
            guard let adapter = adaptersByProvider[account.provider] else {
                updateAccount(id: id) {
                    $0.isRefreshing = false
                    $0.error = .temporarilyUnavailable
                }
                return
            }
            let outcome = try await refresher.refresh(
                retryingAuthentication:
                    adapter.canRecoverAuthenticationWithoutReconnect
            ) {
                do {
                    let snapshot = try await adapter.fetchUsage(
                        for: account,
                        now: now()
                    )
                    guard snapshot.accountID == account.id else {
                        throw ProviderClientError.unsupportedResponse
                    }
                    return snapshot
                } catch let error as ProviderClientError {
                    throw refreshFailure(for: error)
                }
            }
            apply(outcome, to: id)
        } catch let error as ProviderClientError {
            updateAccount(id: id) {
                switch error {
                case .subscriptionRequired:
                    $0.error = .subscriptionRequired
                case .unsupportedResponse:
                    $0.error = .unsupportedResponse
                default:
                    $0.error = .temporarilyUnavailable
                }
            }
        } catch {
            updateAccount(id: id) {
                $0.error = .temporarilyUnavailable
            }
        }

        updateAccount(id: id) {
            $0.isRefreshing = false
        }
        persistedState.refreshStates[id] =
            await refresher.refreshState()
        if let snapshot = accounts.first(where: { $0.id == id })?.snapshot {
            persistedState.snapshots[id] = snapshot
        }
        try? await stateStore.save(persistedState)
    }

    public func removeAccount(id: UUID) async throws {
        guard
            let account = accounts.first(
                where: { $0.id == id },
            )?.account
        else {
            return
        }

        guard let adapter = adaptersByProvider[account.provider] else {
            throw AppModelError.providerUnavailable
        }
        try await adapter.removeAuthentication(for: account)

        var nextState = persistedState
        nextState.accounts.removeAll { $0.id == id }
        nextState.snapshots[id] = nil
        nextState.refreshStates[id] = nil
        try await stateStore.save(nextState)

        persistedState = nextState
        accounts.removeAll { $0.id == id }
        refreshers[id] = nil
    }

    public func connectClaudeAccount(
        _ account: SubscriptionAccount,
        snapshot: UsageSnapshot? = nil
    ) async throws {
        guard !accounts.contains(where: { $0.id == account.id }) else {
            throw AppModelError.accountAlreadyExists
        }
        guard
            account.provider == .claude,
            account.claudeProfileID != nil,
            account.claudeOrganizationID != nil,
            snapshot?.accountID == account.id || snapshot == nil,
            adaptersByProvider[.claude] != nil
        else {
            throw AppModelError.invalidSnapshot
        }

        let refreshState =
            snapshot.map {
                AccountRefreshState(
                    lastRequestStartedAt: $0.fetchedAt
                )
            } ?? .initial
        var nextState = persistedState
        nextState.accounts.append(account)
        nextState.snapshots[account.id] = snapshot
        nextState.refreshStates[account.id] = refreshState
        try await stateStore.save(nextState)

        let now = now
        persistedState = nextState
        refreshers[account.id] = AccountRefresher(
            minimumInterval: refreshPolicy.minimumProviderInterval,
            state: refreshState,
            lastGoodSnapshot: snapshot,
            now: { now() }
        )
        accounts.append(
            AccountViewState(
                account: account,
                snapshot: snapshot,
                error: snapshot == nil ? .temporarilyUnavailable : nil
            )
        )
        accounts.sort(by: viewStateComesBefore)
    }

    public func reconnectClaudeAccount(
        id: UUID,
        replacement: SubscriptionAccount,
        snapshot: UsageSnapshot? = nil
    ) async throws {
        guard
            let existing = accounts.first(
                where: { $0.id == id },
            )?.account,
            existing.provider == .claude
        else {
            throw AppModelError.accountNotFound
        }
        guard
            replacement.id == id,
            replacement.provider == .claude,
            let replacementProfileID =
            replacement.claudeProfileID,
            replacement.claudeOrganizationID != nil,
            snapshot?.accountID == id || snapshot == nil,
            let existingProfileID =
            existing.claudeProfileID,
            let adapter = adaptersByProvider[.claude]
        else {
            throw AppModelError.invalidSnapshot
        }

        let refreshState =
            snapshot.map {
                AccountRefreshState(
                    lastRequestStartedAt: $0.fetchedAt
                )
            } ?? .initial
        var nextState = persistedState
        guard
            let stateIndex = nextState.accounts.firstIndex(
                where: { $0.id == id },
            )
        else {
            throw AppModelError.accountNotFound
        }
        nextState.accounts[stateIndex] = replacement
        nextState.snapshots[id] = snapshot
        nextState.refreshStates[id] = refreshState
        try await stateStore.save(nextState)

        if existingProfileID != replacementProfileID {
            try? await adapter.removeAuthentication(for: existing)
        }

        let now = now
        persistedState = nextState
        refreshers[id] = AccountRefresher(
            minimumInterval: refreshPolicy.minimumProviderInterval,
            state: refreshState,
            lastGoodSnapshot: snapshot,
            now: { now() },
        )
        updateAccount(id: id) {
            $0.account = replacement
            $0.snapshot = snapshot
            $0.error =
                snapshot == nil ? .temporarilyUnavailable : nil
            $0.nextEligibleAt = nil
        }
        accounts.sort(by: viewStateComesBefore)
    }

    public func connectAccount<Credential: Codable & Sendable>(
        _ account: SubscriptionAccount,
        credential: Credential
    ) async throws {
        guard !accounts.contains(where: { $0.id == account.id }) else {
            throw AppModelError.accountAlreadyExists
        }
        guard adaptersByProvider[account.provider] != nil else {
            throw AppModelError.providerUnavailable
        }

        try await credentialStore.save(credential, for: account.id)
        var nextState = persistedState
        nextState.accounts.append(account)
        nextState.refreshStates[account.id] = .initial
        do {
            try await stateStore.save(nextState)
        } catch {
            try? await credentialStore.delete(for: account.id)
            throw error
        }

        let now = now
        persistedState = nextState
        refreshers[account.id] = AccountRefresher(
            minimumInterval: refreshPolicy.minimumProviderInterval,
            now: { now() }
        )
        accounts.append(
            AccountViewState(
                account: account,
                snapshot: nil
            )
        )
        accounts.sort(by: viewStateComesBefore)
        await refreshAccount(id: account.id)
    }

    public func hasCodexAccount(
        providerAccountID: String,
        excluding excludedAccountID: UUID? = nil,
    ) async -> Bool {
        for account in accounts
            where account.account.provider == .codex
            && account.id != excludedAccountID
        {
            guard
                let credential = try? await credentialStore.load(
                    for: account.id,
                ),
                case let .codex(oauth) = credential
            else {
                continue
            }
            if oauth.accountID == providerAccountID {
                return true
            }
        }
        return false
    }

    public func hasGitHubCopilotAccount(
        userID: String,
        excluding excludedAccountID: UUID? = nil
    ) async -> Bool {
        for account in accounts
            where
                account.account.provider
                    == .githubCopilot
                && account.id != excludedAccountID
        {
            guard
                let credential =
                    try? await credentialStore.load(
                        GitHubCopilotCredential.self,
                        for: account.id
                    )
            else {
                continue
            }
            if credential.userID == userID {
                return true
            }
        }
        return false
    }

    public func hasSuperGrokAccount(
        identityKey: String,
        excluding excludedAccountID: UUID? = nil
    ) async -> Bool {
        for account in accounts
            where
                account.account.provider == .superGrok
                && account.id != excludedAccountID
        {
            guard
                let credential =
                    try? await credentialStore.load(
                        SuperGrokCredential.self,
                        for: account.id
                    )
            else {
                continue
            }
            if credential.identityKey == identityKey {
                return true
            }
        }
        return false
    }

    public func hasOpenCodeAccount(
        provider: Provider,
        workspaceID: String,
        excluding excludedAccountID: UUID? = nil
    ) async -> Bool {
        guard
            provider == .openCodeGo
                || provider == .openCodeZen
        else {
            return false
        }
        for account in accounts
            where
                account.account.provider == provider
                && account.id != excludedAccountID
        {
            guard
                let credential =
                    try? await credentialStore.load(
                        OpenCodeDashboardCredential.self,
                        for: account.id
                    )
            else {
                continue
            }
            if credential.identityKey == workspaceID {
                return true
            }
        }
        return false
    }

    public func renameAccount(
        id: UUID,
        displayName: String,
    ) async throws {
        let displayName = displayName.trimmingCharacters(
            in: .whitespacesAndNewlines,
        )
        guard !displayName.isEmpty else {
            throw AppModelError.emptyDisplayName
        }
        guard
            let viewIndex = accounts.firstIndex(where: { $0.id == id }),
            let stateIndex = persistedState.accounts.firstIndex(
                where: { $0.id == id },
            )
        else {
            throw AppModelError.accountNotFound
        }

        let previousView = accounts[viewIndex]
        let previousAccount = persistedState.accounts[stateIndex]
        accounts[viewIndex].account.displayName = displayName
        persistedState.accounts[stateIndex].displayName = displayName
        do {
            try await stateStore.save(persistedState)
        } catch {
            accounts[viewIndex] = previousView
            persistedState.accounts[stateIndex] = previousAccount
            throw error
        }
    }

    public func reorderAccounts(
        provider: Provider,
        orderedIDs: [UUID],
    ) async throws {
        let providerIDs = persistedState.accounts
            .filter { $0.provider == provider }
            .map(\.id)
        guard
            orderedIDs.count == providerIDs.count,
            Set(orderedIDs).count == orderedIDs.count,
            Set(orderedIDs) == Set(providerIDs)
        else {
            throw AppModelError.invalidAccountOrder
        }

        let previousAccounts = accounts
        let previousStateAccounts = persistedState.accounts
        let positions = Dictionary(
            uniqueKeysWithValues: orderedIDs.enumerated().map {
                ($0.element, $0.offset)
            },
        )
        for index in persistedState.accounts.indices
            where persistedState.accounts[index].provider == provider
        {
            persistedState.accounts[index].displayOrder =
                positions[persistedState.accounts[index].id]!
        }
        for index in accounts.indices
            where accounts[index].account.provider == provider
        {
            accounts[index].account.displayOrder =
                positions[accounts[index].id]!
        }
        accounts.sort(by: viewStateComesBefore)

        do {
            try await stateStore.save(persistedState)
        } catch {
            accounts = previousAccounts
            persistedState.accounts = previousStateAccounts
            throw error
        }
    }

    public func reconnectAccount<Credential: Codable & Sendable>(
        id: UUID,
        credential: Credential,
        authenticatedIdentity: String? = nil
    ) async throws {
        guard
            let account = accounts.first(
                where: { $0.id == id },
            )?.account
        else {
            throw AppModelError.accountNotFound
        }
        guard adaptersByProvider[account.provider] != nil else {
            throw AppModelError.providerUnavailable
        }

        let previousCredentialData = try await credentialStore.loadData(
            for: id
        )
        try await credentialStore.save(credential, for: id)

        let previousState = persistedState
        persistedState.refreshStates[id] = .initial
        if
            let authenticatedIdentity,
            let index = persistedState.accounts.firstIndex(
                where: { $0.id == id },
            )
        {
            persistedState.accounts[index]
                .authenticatedIdentity = authenticatedIdentity
        }
        do {
            try await stateStore.save(persistedState)
        } catch {
            persistedState = previousState
            if let previousCredentialData {
                try? await credentialStore.saveData(
                    previousCredentialData,
                    for: id
                )
            } else {
                try? await credentialStore.delete(for: id)
            }
            throw error
        }

        let refresher: AccountRefresher
        if let existingRefresher = refreshers[id] {
            refresher = existingRefresher
        } else {
            let now = now
            refresher = AccountRefresher(
                minimumInterval: refreshPolicy.minimumProviderInterval,
                now: { now() },
            )
            refreshers[id] = refresher
        }
        await refresher.credentialsDidChange()
        updateAccount(id: id) {
            $0.error = nil
            $0.nextEligibleAt = nil
            if let authenticatedIdentity {
                $0.account.authenticatedIdentity =
                    authenticatedIdentity
            }
        }
        await refreshAccount(id: id)
    }

    private func apply(
        _ outcome: RefreshOutcome,
        to accountID: UUID,
    ) {
        updateAccount(id: accountID) { account in
            switch outcome {
            case let .refreshed(snapshot):
                account.snapshot = snapshot
                account.error = nil
                account.nextEligibleAt = nil
            case let .throttled(snapshot, eligibleAt):
                account.snapshot = snapshot ?? account.snapshot
                account.nextEligibleAt = eligibleAt
            case let .reauthenticationRequired(snapshot):
                account.snapshot = snapshot ?? account.snapshot
                account.error = .authenticationRequired
                account.nextEligibleAt = nil
            case let .failed(snapshot, eligibleAt):
                account.snapshot = snapshot ?? account.snapshot
                account.error = .temporarilyUnavailable
                account.nextEligibleAt = eligibleAt
            }
        }
    }

    private func updateAccount(
        id: UUID,
        _ update: (inout AccountViewState) -> Void,
    ) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else {
            return
        }
        update(&accounts[index])
    }

    private func accountComesBefore(
        _ lhs: SubscriptionAccount,
        _ rhs: SubscriptionAccount,
    ) -> Bool {
        let lhsProvider = ProviderCatalog.live.sortIndex(
            for: lhs.provider,
        )
        let rhsProvider = ProviderCatalog.live.sortIndex(
            for: rhs.provider,
        )
        if lhsProvider != rhsProvider {
            return lhsProvider < rhsProvider
        }
        if lhs.displayOrder != rhs.displayOrder {
            return lhs.displayOrder < rhs.displayOrder
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func viewStateComesBefore(
        _ lhs: AccountViewState,
        _ rhs: AccountViewState,
    ) -> Bool {
        accountComesBefore(lhs.account, rhs.account)
    }
}

private func refreshFailure(
    for error: ProviderClientError,
) -> any Error {
    switch error {
    case .credentialMismatch, .reauthenticationRequired:
        RefreshFailure.authenticationRequired
    case let .retryAfter(date):
        RefreshFailure.transient(providerRetryAt: date)
    case .temporaryFailure:
        RefreshFailure.transient(providerRetryAt: nil)
    case .subscriptionRequired,
        .unsupportedResponse:
        error
    }
}
