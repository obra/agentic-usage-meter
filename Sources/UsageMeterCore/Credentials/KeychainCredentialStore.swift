import Foundation
import Security

public enum KeychainCredentialStoreError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case invalidStoredData
}

public actor KeychainCredentialStore: CredentialStore {
    public static let defaultService = "com.fsck.agentic-usage-meter.credentials"

    private let service: String

    public init(service: String = KeychainCredentialStore.defaultService) {
        self.service = service
    }

    public func saveData(
        _ data: Data,
        for accountID: UUID
    ) throws {
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

    public func loadData(for accountID: UUID) throws -> Data? {
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

        return data
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
