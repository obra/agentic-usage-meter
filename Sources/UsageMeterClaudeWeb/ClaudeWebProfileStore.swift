import Foundation
import WebKit

@MainActor
public final class ClaudeWebProfileStore {
    public let dataStore: WKWebsiteDataStore

    public var identifier: UUID? {
        dataStore.identifier
    }

    public init(profileID: UUID) {
        dataStore = WKWebsiteDataStore(forIdentifier: profileID)
    }

    public static func remove(profileID: UUID) async throws {
        weak var initializedStore: WKWebsiteDataStore?
        autoreleasepool {
            let store = WKWebsiteDataStore(forIdentifier: profileID)
            initializedStore = store
        }

        // Static removal can race WebKit's asynchronous release of the
        // bootstrap store and fail to delete its files.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while initializedStore != nil {
            guard clock.now < deadline else {
                throw ClaudeWebProfileStoreError.releaseTimedOut
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        try await WKWebsiteDataStore.remove(forIdentifier: profileID)
    }
}

private enum ClaudeWebProfileStoreError: Error {
    case releaseTimedOut
}
