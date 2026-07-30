import Foundation

public protocol CredentialStore: Sendable {
    func saveData(_ data: Data, for accountID: UUID) async throws
    func loadData(for accountID: UUID) async throws -> Data?
    func delete(for accountID: UUID) async throws
}

public extension CredentialStore {
    func save(
        _ credential: ProviderCredential,
        for accountID: UUID
    ) async throws {
        try await saveData(JSONEncoder().encode(credential), for: accountID)
    }

    func save<Value: Encodable & Sendable>(
        _ value: Value,
        for accountID: UUID
    ) async throws {
        try await saveData(JSONEncoder().encode(value), for: accountID)
    }

    func load<Value: Decodable & Sendable>(
        _ type: Value.Type,
        for accountID: UUID
    ) async throws -> Value? {
        guard let data = try await loadData(for: accountID) else {
            return nil
        }
        return try JSONDecoder().decode(type, from: data)
    }

    func load(for accountID: UUID) async throws -> ProviderCredential? {
        try await load(ProviderCredential.self, for: accountID)
    }
}
