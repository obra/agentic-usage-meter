import Foundation
import UsageMeterWeb
import WebKit

@MainActor
public final class ClaudeWebProfileStore {
    private let profileStore: AccountWebProfileStore

    public var dataStore: WKWebsiteDataStore {
        profileStore.dataStore
    }

    public var identifier: UUID? {
        profileStore.identifier
    }

    public init(profileID: UUID) {
        profileStore = AccountWebProfileStore(
            accountID: profileID
        )
    }

    public static func remove(profileID: UUID) async throws {
        try await AccountWebProfileStore.remove(
            accountID: profileID
        )
    }
}
