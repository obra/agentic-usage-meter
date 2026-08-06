import Foundation
import OSLog
import WebKit

private let webProfileLogger = Logger(
    subsystem:
        "com.fsck.agentic-usage-meter",
    category: "WebProfile"
)

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
                webProfileLogger.error(
                    "Profile removal timed out waiting for the data store to be released"
                )
                throw AccountWebProfileStoreError.releaseTimedOut
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        do {
            try await WKWebsiteDataStore.remove(forIdentifier: accountID)
        } catch {
            webProfileLogger.error(
                "Profile removal failed: \((error as NSError).domain, privacy: .public) code \((error as NSError).code, privacy: .public) \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }
}

private enum AccountWebProfileStoreError: Error {
    case releaseTimedOut
}
