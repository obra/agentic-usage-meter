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
        try await WKWebsiteDataStore.remove(forIdentifier: profileID)
    }
}
