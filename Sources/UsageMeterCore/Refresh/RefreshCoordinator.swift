import Foundation

public actor RefreshCoordinator {
    public typealias Operation =
        @Sendable (UUID) async -> Void

    private let maximumConcurrentRefreshes: Int
    private var activeRefreshes = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(maximumConcurrentRefreshes: Int = 3) {
        precondition(maximumConcurrentRefreshes > 0)
        self.maximumConcurrentRefreshes = maximumConcurrentRefreshes
    }

    public func run(
        accountIDs: [UUID],
        operation: @escaping Operation
    ) async {
        await withTaskGroup(of: Void.self) { group in
            for accountID in accountIDs {
                group.addTask {
                    await self.acquire()
                    await operation(accountID)
                    await self.release()
                }
            }
        }
    }

    private func acquire() async {
        guard activeRefreshes >= maximumConcurrentRefreshes else {
            activeRefreshes += 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        guard !waiters.isEmpty else {
            activeRefreshes -= 1
            return
        }

        let next = waiters.removeFirst()
        next.resume()
    }
}
