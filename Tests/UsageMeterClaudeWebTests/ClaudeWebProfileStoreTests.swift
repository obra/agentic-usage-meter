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

    @Test
    func coldProfileStartsOneBrowserLoadAndReusesItsStore() async throws {
        let profileID = UUID()
        let sessionCookie = try #require(
            HTTPCookie(
                properties: [
                    .domain: ".claude.ai",
                    .path: "/",
                    .name: "sessionKey",
                    .value: "persisted-session",
                    .secure: "TRUE"
                ]
            )
        )
        let loader = TestClaudeWebProfileCookieLoader(
            results: [[], [sessionCookie]]
        )
        var requestedProfileIDs: [UUID] = []
        let source = WebKitClaudeCookieSource { requestedProfileID in
            requestedProfileIDs.append(requestedProfileID)
            return loader
        }
        let url = try #require(URL(string: "https://claude.ai/api/organizations"))

        #expect(await source.cookies(for: url, profileID: profileID).isEmpty)
        #expect(
            await source.cookies(for: url, profileID: profileID)
                == [sessionCookie]
        )
        #expect(requestedProfileIDs == [profileID])
        #expect(loader.warmCount == 1)
    }
}

@MainActor
private final class TestClaudeWebProfileCookieLoader:
    ClaudeWebProfileCookieLoading
{
    private let results: [[HTTPCookie]]
    private var requestCount = 0
    private(set) var warmCount = 0

    init(results: [[HTTPCookie]]) {
        self.results = results
    }

    func cookies() async -> [HTTPCookie] {
        defer {
            requestCount += 1
        }
        return results[min(requestCount, results.count - 1)]
    }

    func warmIfNeeded() {
        warmCount += 1
    }
}
