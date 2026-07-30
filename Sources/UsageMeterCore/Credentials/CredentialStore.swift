import Foundation

public protocol CredentialStore: Sendable {
    func save(_ credential: ProviderCredential, for accountID: UUID) async throws
    func load(for accountID: UUID) async throws -> ProviderCredential?
    func delete(for accountID: UUID) async throws
}
