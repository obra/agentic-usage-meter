import Foundation

public enum RefreshFailure: Error, Equatable, Sendable {
    case authenticationRequired
    case transient(providerRetryAt: Date?)
}

public enum RefreshOutcome: Equatable, Sendable {
    case refreshed(snapshot: UsageSnapshot)
    case throttled(snapshot: UsageSnapshot?, eligibleAt: Date)
    case reauthenticationRequired(snapshot: UsageSnapshot?)
    case failed(snapshot: UsageSnapshot?, eligibleAt: Date)
}

public struct AccountRefreshState: Codable, Equatable, Sendable {
    public var lastRequestStartedAt: Date?
    public var providerRetryAt: Date?
    public var failureBackoffUntil: Date?
    public var consecutiveTransientFailures: Int
    public var requiresReauthentication: Bool

    public init(
        lastRequestStartedAt: Date? = nil,
        providerRetryAt: Date? = nil,
        failureBackoffUntil: Date? = nil,
        consecutiveTransientFailures: Int = 0,
        requiresReauthentication: Bool = false
    ) {
        self.lastRequestStartedAt = lastRequestStartedAt
        self.providerRetryAt = providerRetryAt
        self.failureBackoffUntil = failureBackoffUntil
        self.consecutiveTransientFailures = max(0, consecutiveTransientFailures)
        self.requiresReauthentication = requiresReauthentication
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let consecutiveTransientFailures = try container.decode(
            Int.self,
            forKey: .consecutiveTransientFailures
        )
        guard consecutiveTransientFailures >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .consecutiveTransientFailures,
                in: container,
                debugDescription: "Transient failure count cannot be negative."
            )
        }

        self.init(
            lastRequestStartedAt: try container.decodeIfPresent(
                Date.self,
                forKey: .lastRequestStartedAt
            ),
            providerRetryAt: try container.decodeIfPresent(
                Date.self,
                forKey: .providerRetryAt
            ),
            failureBackoffUntil: try container.decodeIfPresent(
                Date.self,
                forKey: .failureBackoffUntil
            ),
            consecutiveTransientFailures: consecutiveTransientFailures,
            requiresReauthentication: try container.decode(
                Bool.self,
                forKey: .requiresReauthentication
            )
        )
    }

    public static let initial = AccountRefreshState()

    private enum CodingKeys: String, CodingKey {
        case lastRequestStartedAt
        case providerRetryAt
        case failureBackoffUntil
        case consecutiveTransientFailures
        case requiresReauthentication
    }
}

public actor AccountRefresher {
    public typealias Fetch = @Sendable () async throws -> UsageSnapshot

    private struct InFlightRequest {
        let id: UUID
        let task: Task<UsageSnapshot, any Error>
        var waiterCount: Int
    }

    private struct CompletedRequest {
        let id: UUID
        let result: Result<RefreshOutcome, any Error>
    }

    private let minimumInterval: TimeInterval
    private let now: @Sendable () async -> Date
    private var state: AccountRefreshState
    private var lastGoodSnapshot: UsageSnapshot?
    private var inFlightRequest: InFlightRequest?
    private var completedRequest: CompletedRequest?

    public init(
        minimumInterval: TimeInterval =
            RefreshPolicy.release.minimumProviderInterval,
        state: AccountRefreshState = .initial,
        lastGoodSnapshot: UsageSnapshot? = nil,
        now: @escaping @Sendable () async -> Date = { Date() }
    ) {
        precondition(minimumInterval.isFinite && minimumInterval > 0)
        self.minimumInterval = minimumInterval
        self.state = state
        self.lastGoodSnapshot = lastGoodSnapshot
        self.now = now
    }

    public func refresh(
        retryingAuthentication: Bool = false,
        using fetch: @escaping Fetch
    ) async throws -> RefreshOutcome {
        if var inFlightRequest {
            inFlightRequest.waiterCount += 1
            self.inFlightRequest = inFlightRequest
            return try await wait(for: inFlightRequest)
        }

        if state.requiresReauthentication && !retryingAuthentication {
            return .reauthenticationRequired(snapshot: lastGoodSnapshot)
        }

        let requestedAt = await now()
        let eligibleAt = nextEligibleDate()
        guard requestedAt >= eligibleAt else {
            return .throttled(
                snapshot: lastGoodSnapshot,
                eligibleAt: eligibleAt
            )
        }

        state.lastRequestStartedAt = requestedAt
        let request = InFlightRequest(
            id: UUID(),
            task: Task {
                try await fetch()
            },
            waiterCount: 1
        )
        inFlightRequest = request
        return try await wait(for: request)
    }

    public func refreshState() -> AccountRefreshState {
        state
    }

    var activeDemandCount: Int {
        inFlightRequest?.waiterCount ?? 0
    }

    public func credentialsDidChange() {
        state.lastRequestStartedAt = nil
        state.providerRetryAt = nil
        state.failureBackoffUntil = nil
        state.consecutiveTransientFailures = 0
        state.requiresReauthentication = false
    }

    private func wait(for request: InFlightRequest) async throws -> RefreshOutcome {
        let providerResult: Result<UsageSnapshot, any Error>
        do {
            providerResult = .success(try await request.task.value)
        } catch {
            providerResult = .failure(error)
        }

        do {
            let outcome = try await finish(
                requestID: request.id,
                providerResult: providerResult
            )
            releaseWaiter(for: request.id)
            return outcome
        } catch {
            releaseWaiter(for: request.id)
            throw error
        }
    }

    private func finish(
        requestID: UUID,
        providerResult: Result<UsageSnapshot, any Error>
    ) async throws -> RefreshOutcome {
        if let completedRequest, completedRequest.id == requestID {
            return try completedRequest.result.get()
        }

        let result: Result<RefreshOutcome, any Error>
        switch providerResult {
        case let .success(snapshot):
            lastGoodSnapshot = snapshot
            state.providerRetryAt = nil
            state.failureBackoffUntil = nil
            state.consecutiveTransientFailures = 0
            state.requiresReauthentication = false
            result = .success(.refreshed(snapshot: snapshot))

        case let .failure(failure as RefreshFailure):
            result = .success(await outcome(for: failure))

        case let .failure(error as ProviderClientError):
            switch error {
            case .subscriptionRequired,
                .unsupportedResponse:
                state.requiresReauthentication = false
            default:
                break
            }
            result = .failure(error)

        case let .failure(error):
            result = .failure(error)
        }

        completedRequest = CompletedRequest(id: requestID, result: result)
        return try result.get()
    }

    private func releaseWaiter(for requestID: UUID) {
        guard var inFlightRequest, inFlightRequest.id == requestID else {
            return
        }

        inFlightRequest.waiterCount -= 1
        if inFlightRequest.waiterCount == 0 {
            self.inFlightRequest = nil
            if completedRequest?.id == requestID {
                completedRequest = nil
            }
        } else {
            self.inFlightRequest = inFlightRequest
        }
    }

    private func outcome(for failure: RefreshFailure) async -> RefreshOutcome {
        switch failure {
        case .authenticationRequired:
            state.providerRetryAt = nil
            state.failureBackoffUntil = nil
            state.consecutiveTransientFailures = 0
            state.requiresReauthentication = true
            return .reauthenticationRequired(snapshot: lastGoodSnapshot)

        case let .transient(providerRetryAt):
            state.consecutiveTransientFailures += 1
            state.providerRetryAt = providerRetryAt

            let exponent = min(state.consecutiveTransientFailures - 1, 3)
            let backoff = min(600 * pow(2, Double(exponent)), 3_600)
            state.failureBackoffUntil = await now().addingTimeInterval(backoff)

            return .failed(
                snapshot: lastGoodSnapshot,
                eligibleAt: nextEligibleDate()
            )
        }
    }

    private func nextEligibleDate() -> Date {
        [
            state.lastRequestStartedAt?.addingTimeInterval(minimumInterval),
            state.providerRetryAt,
            state.failureBackoffUntil
        ]
        .compactMap(\.self)
        .max() ?? .distantPast
    }
}
