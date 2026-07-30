import Foundation

public protocol ProviderAccountAdapter: Sendable {
    var provider: Provider { get }
    var canRecoverAuthenticationWithoutReconnect: Bool { get }

    func fetchUsage(
        for account: SubscriptionAccount,
        now: Date
    ) async throws -> UsageSnapshot

    func removeAuthentication(
        for account: SubscriptionAccount
    ) async throws
}

public extension ProviderAccountAdapter {
    var canRecoverAuthenticationWithoutReconnect: Bool {
        false
    }
}
