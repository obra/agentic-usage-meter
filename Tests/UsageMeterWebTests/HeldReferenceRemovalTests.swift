import Foundation
import Testing
import WebKit
@testable import UsageMeterWeb

// Removal right after the last reference is released races WebKit's
// asynchronous network-process session teardown ("data store is in
// use"); the removal retries must absorb that window (issue #7).
@MainActor
@Test
func removalSucceedsImmediatelyAfterTheLastReferenceIsReleased() async throws {
    let accountID = UUID()
    var held: WKWebsiteDataStore? =
        WKWebsiteDataStore(forIdentifier: accountID)
    _ = await withCheckedContinuation { continuation in
        held?.httpCookieStore.getAllCookies {
            continuation.resume(returning: $0)
        }
    }

    held = nil
    try await AccountWebProfileStore.remove(accountID: accountID)

    let identifiers = try await WKWebsiteDataStore.allDataStoreIdentifiers
    #expect(!identifiers.contains(accountID))
}

// Slow machines have needed several seconds of "in use" retries
// before WebKit's session teardown allows deletion.
@MainActor
@Test
func removalRetriesSpanSeveralSecondsForSlowSessionTeardown() {
    let totalSeconds = AccountWebProfileStore.removalRetryDelays
        .reduce(Duration.zero, +)
    #expect(totalSeconds >= .seconds(7))
}
