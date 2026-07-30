import Foundation
import WebKit

@MainActor
public final class AccountWebProfileStore {
    public let dataStore: WKWebsiteDataStore

    public var identifier: UUID? {
        dataStore.identifier
    }

    public init(accountID: UUID) {
        dataStore = WKWebsiteDataStore(forIdentifier: accountID)
    }

    public static func remove(accountID: UUID) async throws {
        weak var initializedStore: WKWebsiteDataStore?
        autoreleasepool {
            let store = WKWebsiteDataStore(forIdentifier: accountID)
            initializedStore = store
        }

        // Static removal can race WebKit's asynchronous release of the
        // bootstrap store and fail to delete its files.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while initializedStore != nil {
            guard clock.now < deadline else {
                throw AccountWebProfileStoreError.releaseTimedOut
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        try await WKWebsiteDataStore.remove(forIdentifier: accountID)
    }
}

private enum AccountWebProfileStoreError: Error {
    case releaseTimedOut
}
