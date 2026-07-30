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
    public private(set) var accounts: [AccountViewState] = []
    public private(set) var isFloatingWidgetVisible = false
    public private(set) var floatingWidgetPlacement:
        FloatingWidgetPlacement?

    @ObservationIgnored
    private let stateStore: any AppStatePersisting
    @ObservationIgnored
    private let credentialStore: any CredentialStore
    @ObservationIgnored
    private let clientsByProvider: [Provider: any UsageProviderClient]
    @ObservationIgnored
    private let now: @Sendable () -> Date
    @ObservationIgnored
    private var persistedState = PersistedAppState.empty
    @ObservationIgnored
    private var refreshers: [UUID: AccountRefresher] = [:]

    public init(
        stateStore: any AppStatePersisting,
        credentialStore: any CredentialStore,
        clients: [any UsageProviderClient],
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.stateStore = stateStore
        self.credentialStore = credentialStore
        clientsByProvider = Dictionary(
            uniqueKeysWithValues: clients.map {
                ($0.provider, $0)
            },
        )
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

    public func refreshAccount(id: UUID) async {
        guard
            let account = accounts.first(where: { $0.id == id })?.account,
            let client = clientsByProvider[account.provider],
            let refresher = refreshers[id]
        else {
            return
        }

        updateAccount(id: id) {
            $0.isRefreshing = true
        }

        do {
            let credentialStore = credentialStore
            let now = now
            let outcome = try await refresher.refresh {
                guard
                    let credential = try await credentialStore.load(
                        for: id,
                    )
                else {
                    throw RefreshFailure.authenticationRequired
                }
                do {
                    return try await client.fetchUsage(
                        accountID: id,
                        credential: credential,
                        now: now(),
                    )
                } catch let error as ProviderClientError {
                    throw refreshFailure(for: error)
                }
            }
            apply(outcome, to: id)
        } catch let error as ProviderClientError {
            updateAccount(id: id) {
                $0.error =
                    error == .unsupportedResponse
                        ? .unsupportedResponse
                        : .temporarilyUnavailable
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
        guard accounts.contains(where: { $0.id == id }) else {
            return
        }

        try await credentialStore.delete(for: id)

        var nextState = persistedState
        nextState.accounts.removeAll { $0.id == id }
        nextState.snapshots[id] = nil
        nextState.refreshStates[id] = nil
        try await stateStore.save(nextState)

        persistedState = nextState
        accounts.removeAll { $0.id == id }
        refreshers[id] = nil
    }

    public func connectAccount(
        _ account: SubscriptionAccount,
        credential: ProviderCredential,
    ) async throws {
        guard !accounts.contains(where: { $0.id == account.id }) else {
            throw AppModelError.accountAlreadyExists
        }
        guard let client = clientsByProvider[account.provider] else {
            throw AppModelError.providerUnavailable
        }

        let now = now
        let refresher = AccountRefresher(now: { now() })
        let outcome = try await refresher.refresh {
            try await client.fetchUsage(
                accountID: account.id,
                credential: credential,
                now: now(),
            )
        }
        guard
            case let .refreshed(snapshot) = outcome,
            snapshot.accountID == account.id
        else {
            throw AppModelError.invalidSnapshot
        }

        try await credentialStore.save(
            credential,
            for: account.id,
        )

        var nextState = persistedState
        nextState.accounts.append(account)
        nextState.snapshots[account.id] = snapshot
        nextState.refreshStates[account.id] =
            await refresher.refreshState()
        do {
            try await stateStore.save(nextState)
        } catch {
            try? await credentialStore.delete(for: account.id)
            throw error
        }

        persistedState = nextState
        refreshers[account.id] = refresher
        accounts.append(
            AccountViewState(
                account: account,
                snapshot: snapshot,
            ),
        )
        accounts.sort(by: viewStateComesBefore)
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

    public func reconnectAccount(
        id: UUID,
        credential: ProviderCredential,
    ) async throws {
        guard
            let account = accounts.first(
                where: { $0.id == id },
            )?.account
        else {
            throw AppModelError.accountNotFound
        }
        guard let client = clientsByProvider[account.provider] else {
            throw AppModelError.providerUnavailable
        }

        let now = now
        let refresher = AccountRefresher(now: { now() })
        let outcome = try await refresher.refresh {
            try await client.fetchUsage(
                accountID: id,
                credential: credential,
                now: now(),
            )
        }
        guard
            case let .refreshed(snapshot) = outcome,
            snapshot.accountID == id
        else {
            throw AppModelError.invalidSnapshot
        }

        let previousCredential = try await credentialStore.load(
            for: id,
        )
        try await credentialStore.save(credential, for: id)

        let previousState = persistedState
        persistedState.snapshots[id] = snapshot
        persistedState.refreshStates[id] =
            await refresher.refreshState()
        do {
            try await stateStore.save(persistedState)
        } catch {
            persistedState = previousState
            if let previousCredential {
                try? await credentialStore.save(
                    previousCredential,
                    for: id,
                )
            } else {
                try? await credentialStore.delete(for: id)
            }
            throw error
        }

        refreshers[id] = refresher
        updateAccount(id: id) {
            $0.snapshot = snapshot
            $0.error = nil
            $0.nextEligibleAt = nil
        }
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
        let providers = Dictionary(
            uniqueKeysWithValues: Provider.allCases.enumerated().map {
                ($0.element, $0.offset)
            },
        )
        let lhsProvider = providers[lhs.provider] ?? .max
        let rhsProvider = providers[rhs.provider] ?? .max
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
    case .unsupportedResponse:
        error
    }
}
