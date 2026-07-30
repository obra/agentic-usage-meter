import Foundation
import Testing
@testable import UsageMeterCore

@Test
func refreshCoordinatorBoundsConcurrentOperations() async {
    let coordinator = RefreshCoordinator(
        maximumConcurrentRefreshes: 2
    )
    let counter = SuspendedOperationCounter()
    let accountIDs = (0 ..< 5).map { _ in UUID() }

    let run = Task {
        await coordinator.run(accountIDs: accountIDs) { accountID in
            await counter.run(accountID: accountID)
        }
    }

    await counter.waitUntilStarted(count: 2)

    #expect(await counter.activeCount == 2)
    #expect(await counter.peakActiveCount == 2)

    await counter.releaseAllAndStopSuspending()
    await run.value

    #expect(await counter.completedCount == accountIDs.count)
    #expect(await counter.peakActiveCount == 2)
}

private actor SuspendedOperationCounter {
    private(set) var activeCount = 0
    private(set) var peakActiveCount = 0
    private(set) var completedCount = 0

    private var shouldSuspend = true
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var startWaiters:
        [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var startedCount = 0

    func run(accountID _: UUID) async {
        activeCount += 1
        peakActiveCount = max(peakActiveCount, activeCount)
        startedCount += 1
        resumeSatisfiedStartWaiters()

        if shouldSuspend {
            await withCheckedContinuation { continuation in
                releaseWaiters.append(continuation)
            }
        }

        activeCount -= 1
        completedCount += 1
    }

    func waitUntilStarted(count: Int) async {
        guard startedCount < count else {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append((count, continuation))
        }
    }

    func releaseAllAndStopSuspending() {
        shouldSuspend = false
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func resumeSatisfiedStartWaiters() {
        let satisfied = startWaiters.filter {
            startedCount >= $0.count
        }
        startWaiters.removeAll {
            startedCount >= $0.count
        }
        for waiter in satisfied {
            waiter.continuation.resume()
        }
    }
}
