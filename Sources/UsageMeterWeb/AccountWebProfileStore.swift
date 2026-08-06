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

        // Removal works with lingering store references, so waiting for
        // WebKit's asynchronous release of the bootstrap store is only a
        // grace period, never a reason to fail.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while initializedStore != nil, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        if initializedStore != nil {
            webProfileLogger.error(
                "Data store is still referenced after the release grace period"
            )
        }

        var lastError: (any Error)?
        for delay in [
            Duration.zero,
            .milliseconds(200),
            .milliseconds(500),
            .seconds(1),
        ] {
            if delay != .zero {
                try await Task.sleep(for: delay)
            }
            do {
                try await WKWebsiteDataStore.remove(
                    forIdentifier: accountID
                )
            } catch {
                lastError = error
                webProfileLogger.error(
                    "Profile removal attempt failed: \((error as NSError).domain, privacy: .public) code \((error as NSError).code, privacy: .public) \(error.localizedDescription, privacy: .public)"
                )
                continue
            }

            let identifiers =
                try await WKWebsiteDataStore.allDataStoreIdentifiers
            guard identifiers.contains(accountID) else {
                return
            }
            lastError = AccountWebProfileStoreError.profileNotDeleted
            webProfileLogger.error(
                "Profile removal reported success but the profile still exists"
            )
        }
        throw lastError
            ?? AccountWebProfileStoreError.profileNotDeleted
    }
}

private enum AccountWebProfileStoreError: Error {
    case profileNotDeleted
}
