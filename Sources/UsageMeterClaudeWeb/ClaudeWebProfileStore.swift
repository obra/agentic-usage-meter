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
        // Initialize WebKit's identified-store machinery in command-line
        // processes, then release the store before asking WebKit to remove it.
        autoreleasepool {
            _ = WKWebsiteDataStore(forIdentifier: profileID)
        }
        try await WKWebsiteDataStore.remove(forIdentifier: profileID)
    }
}
