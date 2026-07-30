import Foundation
import Testing
@testable import UsageMeterWeb

@MainActor
@Test
func accountStoresRemainIndependentWhenOneIsRemoved() async throws {
    let firstID = UUID()
    let secondID = UUID()
    var first: AccountWebProfileStore? = .init(accountID: firstID)
    var second: AccountWebProfileStore? = .init(accountID: secondID)

    #expect(first?.identifier == firstID)
    #expect(second?.identifier == secondID)
    first = nil
    try await AccountWebProfileStore.remove(accountID: firstID)
    #expect(second?.identifier == secondID)
    second = nil
    try await AccountWebProfileStore.remove(accountID: secondID)
}
