import Foundation
import Security

public enum KeychainCredentialStoreError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case invalidStoredData
}

public actor KeychainCredentialStore: CredentialStore {
    public static let defaultService = "com.jesse.agentic-usage-meter.credentials"

    private let service: String

    public init(service: String = KeychainCredentialStore.defaultService) {
        self.service = service
    }

    public func save(
        _ credential: ProviderCredential,
        for accountID: UUID
    ) throws {
        let data = try JSONEncoder().encode(credential)
        let query = lookupQuery(for: accountID)
        let status = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )

        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData] = data
            newItem[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainCredentialStoreError.unexpectedStatus(addStatus)
            }
            return
        }

        guard status == errSecSuccess else {
            throw KeychainCredentialStoreError.unexpectedStatus(status)
        }
    }

    public func load(for accountID: UUID) throws -> ProviderCredential? {
        var query = lookupQuery(for: accountID)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainCredentialStoreError.unexpectedStatus(status)
        }
        guard let data = result as? Data else {
            throw KeychainCredentialStoreError.invalidStoredData
        }

        return try JSONDecoder().decode(ProviderCredential.self, from: data)
    }

    public func delete(for accountID: UUID) throws {
        let status = SecItemDelete(lookupQuery(for: accountID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainCredentialStoreError.unexpectedStatus(status)
        }
    }

    private func lookupQuery(for accountID: UUID) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: accountID.uuidString,
            kSecAttrSynchronizable: kCFBooleanFalse as Any
        ]
    }
}
