import Foundation

public protocol UsageProviderClient: Sendable {
    var provider: Provider { get }

    func fetchUsage(
        accountID: UUID,
        credential: ProviderCredential,
        now: Date
    ) async throws -> UsageSnapshot
}

public enum ProviderClientError: Error, Equatable, Sendable {
    case credentialMismatch
    case subscriptionRequired
    case unsupportedResponse
    case reauthenticationRequired
    case retryAfter(Date?)
    case temporaryFailure
}
