import Foundation
import Testing
@testable import UsageMeterCore

@Test
func secondRequestInsideTenMinutesUsesCachedSnapshot() async throws {
    let reference = Date(timeIntervalSince1970: 2_000_000_000)
    let clock = TestDateSource(now: reference)
    let snapshot = makeSnapshot(fetchedAt: reference)
    let fetcher = SequencedUsageFetcher(outcomes: [.success(snapshot)])
    let refresher = AccountRefresher(
        minimumInterval: 600,
        now: { await clock.current() }
    )

    #expect(
        try await refresher.refresh { try await fetcher.fetch() }
            == .refreshed(snapshot: snapshot)
    )
    await clock.advance(by: 599)

    #expect(
        try await refresher.refresh { try await fetcher.fetch() }
            == .throttled(
                snapshot: snapshot,
                eligibleAt: reference.addingTimeInterval(600)
            )
    )
    #expect(await fetcher.callCount == 1)
}

@Test
func requestAtTenMinutesFetchesAgain() async throws {
    let reference = Date(timeIntervalSince1970: 2_000_000_000)
    let clock = TestDateSource(now: reference)
    let firstSnapshot = makeSnapshot(fetchedAt: reference)
    let secondSnapshot = makeSnapshot(fetchedAt: reference.addingTimeInterval(600))
    let fetcher = SequencedUsageFetcher(
        outcomes: [.success(firstSnapshot), .success(secondSnapshot)]
    )
    let refresher = AccountRefresher(now: { await clock.current() })

    _ = try await refresher.refresh { try await fetcher.fetch() }
    await clock.advance(by: 600)

    #expect(
        try await refresher.refresh { try await fetcher.fetch() }
            == .refreshed(snapshot: secondSnapshot)
    )
    #expect(await fetcher.callCount == 2)
}

@Test(.timeLimit(.minutes(1)))
func concurrentDemandSharesOneInFlightRequest() async throws {
    let reference = Date(timeIntervalSince1970: 2_000_000_000)
    let snapshot = makeSnapshot(fetchedAt: reference)
    let fetcher = SuspendingUsageFetcher()
    let refresher = AccountRefresher(now: { reference })

    let first = Task {
        try await refresher.refresh { try await fetcher.fetch() }
    }
    await fetcher.waitUntilCalled()
    let second = Task {
        try await refresher.refresh { try await fetcher.fetch() }
    }
    while await refresher.activeDemandCount < 2 {
        try await Task.sleep(for: .milliseconds(10))
    }
    await fetcher.resume(with: snapshot)

    let results = try await [first.value, second.value]

    #expect(results == [.refreshed(snapshot: snapshot), .refreshed(snapshot: snapshot)])
    #expect(await fetcher.callCount == 1)
}

@Test
func transientFailuresBackOffTenTwentyFortyThenSixtyMinutes() async throws {
    let reference = Date(timeIntervalSince1970: 2_000_000_000)
    let clock = TestDateSource(now: reference)
    let fetcher = SequencedUsageFetcher(
        outcomes: Array(
            repeating: .failure(.transient(providerRetryAt: nil)),
            count: 4
        )
    )
    let refresher = AccountRefresher(now: { await clock.current() })
    let expectedDelays: [TimeInterval] = [600, 1_200, 2_400, 3_600]

    for delay in expectedDelays {
        let failedAt = await clock.current()
        #expect(
            try await refresher.refresh { try await fetcher.fetch() }
                == .failed(
                    snapshot: nil,
                    eligibleAt: failedAt.addingTimeInterval(delay)
                )
        )
        await clock.advance(by: delay)
    }

    #expect(await fetcher.callCount == 4)
    #expect(await refresher.refreshState().consecutiveTransientFailures == 4)
}

@Test
func providerRetryDateCanExtendTransientBackoff() async throws {
    let reference = Date(timeIntervalSince1970: 2_000_000_000)
    let providerRetryAt = reference.addingTimeInterval(1_800)
    let fetcher = SequencedUsageFetcher(
        outcomes: [.failure(.transient(providerRetryAt: providerRetryAt))]
    )
    let refresher = AccountRefresher(now: { reference })

    #expect(
        try await refresher.refresh { try await fetcher.fetch() }
            == .failed(snapshot: nil, eligibleAt: providerRetryAt)
    )
}

@Test
func transientFailureRetainsTheLastGoodSnapshot() async throws {
    let reference = Date(timeIntervalSince1970: 2_000_000_000)
    let clock = TestDateSource(now: reference)
    let snapshot = makeSnapshot(fetchedAt: reference)
    let fetcher = SequencedUsageFetcher(
        outcomes: [
            .success(snapshot),
            .failure(.transient(providerRetryAt: nil))
        ]
    )
    let refresher = AccountRefresher(now: { await clock.current() })

    _ = try await refresher.refresh { try await fetcher.fetch() }
    await clock.advance(by: 600)

    #expect(
        try await refresher.refresh { try await fetcher.fetch() }
            == .failed(
                snapshot: snapshot,
                eligibleAt: reference.addingTimeInterval(1_200)
            )
    )
}

@Test
func authenticationFailureStopsRequestsUntilCredentialsChange() async throws {
    let reference = Date(timeIntervalSince1970: 2_000_000_000)
    let snapshot = makeSnapshot(fetchedAt: reference)
    let fetcher = SequencedUsageFetcher(
        outcomes: [
            .failure(.authenticationRequired),
            .success(snapshot)
        ]
    )
    let refresher = AccountRefresher(now: { reference })

    #expect(
        try await refresher.refresh { try await fetcher.fetch() }
            == .reauthenticationRequired(snapshot: nil)
    )
    #expect(
        try await refresher.refresh { try await fetcher.fetch() }
            == .reauthenticationRequired(snapshot: nil)
    )
    #expect(await fetcher.callCount == 1)

    await refresher.credentialsDidChange()

    #expect(
        try await refresher.refresh { try await fetcher.fetch() }
            == .refreshed(snapshot: snapshot)
    )
    #expect(await fetcher.callCount == 2)
}

@Test
func refreshStateDecodingRejectsNegativeFailureCounts() {
    let invalidState = Data(
        """
        {
          "lastRequestStartedAt": null,
          "providerRetryAt": null,
          "failureBackoffUntil": null,
          "consecutiveTransientFailures": -1,
          "requiresReauthentication": false
        }
        """.utf8
    )

    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(AccountRefreshState.self, from: invalidState)
    }
}

private actor TestDateSource {
    private var now: Date

    init(now: Date) {
        self.now = now
    }

    func current() -> Date {
        now
    }

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}

private actor SequencedUsageFetcher {
    private let outcomes: [Result<UsageSnapshot, RefreshFailure>]
    private(set) var callCount = 0

    init(outcomes: [Result<UsageSnapshot, RefreshFailure>]) {
        self.outcomes = outcomes
    }

    func fetch() throws -> UsageSnapshot {
        let outcome = outcomes[min(callCount, outcomes.count - 1)]
        callCount += 1
        return try outcome.get()
    }
}

private actor SuspendingUsageFetcher {
    private var continuation: CheckedContinuation<UsageSnapshot, any Error>?
    private(set) var callCount = 0

    func fetch() async throws -> UsageSnapshot {
        callCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilCalled() async {
        while callCount == 0 {
            await Task.yield()
        }
    }

    func resume(with snapshot: UsageSnapshot) {
        continuation?.resume(returning: snapshot)
        continuation = nil
    }
}

private func makeSnapshot(fetchedAt: Date) -> UsageSnapshot {
    UsageSnapshot(accountID: UUID(), fetchedAt: fetchedAt, windows: [])
}
