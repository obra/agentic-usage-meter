import Foundation
import Testing
@testable import UsageMeterClaudeWeb

@MainActor
@Suite
struct ClaudeWebProfileStoreTests {
    @Test
    func identifiedStoresRemainIndependentAndCanBeRemoved() async throws {
        let firstID = UUID()
        let secondID = UUID()
        var firstStore: ClaudeWebProfileStore? = ClaudeWebProfileStore(
            profileID: firstID
        )
        var secondStore: ClaudeWebProfileStore? = ClaudeWebProfileStore(
            profileID: secondID
        )

        #expect(firstStore?.identifier == firstID)
        #expect(secondStore?.identifier == secondID)
        #expect(firstStore?.identifier != secondStore?.identifier)

        firstStore = nil
        secondStore = nil
        try await ClaudeWebProfileStore.remove(profileID: firstID)
        try await ClaudeWebProfileStore.remove(profileID: secondID)
    }
}
