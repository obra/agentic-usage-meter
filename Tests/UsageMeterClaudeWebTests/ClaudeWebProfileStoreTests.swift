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
    func preparingForRemovalEvictsTheProfileAndBlocksNewLoads() async throws {
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
        var createdLoaders = 0
        let source = WebKitClaudeCookieSource { _ in
            createdLoaders += 1
            return TestClaudeWebProfileCookieLoader(
                results: [[sessionCookie]]
            )
        }
        let url = try #require(URL(string: "https://claude.ai/api/organizations"))

        #expect(
            await source.cookies(for: url, profileID: profileID)
                == [sessionCookie]
        )
        #expect(createdLoaders == 1)

        await source.prepareForRemoval(profileID: profileID)
        #expect(await source.cookies(for: url, profileID: profileID).isEmpty)
        #expect(createdLoaders == 1)

        source.finishRemoval(profileID: profileID)
        #expect(
            await source.cookies(for: url, profileID: profileID)
                == [sessionCookie]
        )
        #expect(createdLoaders == 2)
    }

    @Test
    func preparingForRemovalWaitsForInFlightCookieLoads() async throws {
        let profileID = UUID()
        let loader = StallableClaudeWebProfileCookieLoader()
        let source = WebKitClaudeCookieSource { _ in
            loader
        }
        let url = try #require(URL(string: "https://claude.ai/api/organizations"))

        let load = Task { @MainActor in
            _ = await source.cookies(for: url, profileID: profileID)
        }
        await loader.waitUntilLoading()

        let prepare = Task { @MainActor in
            await source.prepareForRemoval(profileID: profileID)
            return loader.completedLoads
        }
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        loader.finishLoading()

        #expect(await prepare.value == 1)
        _ = await load.value
        source.finishRemoval(profileID: profileID)
    }

    @Test
    func profileCanBeRemovedWhileTheCookieSourceHadItCached() async throws {
        let profileID = UUID()
        let source = WebKitClaudeCookieSource()
        let url = try #require(URL(string: "https://claude.ai/api/organizations"))

        _ = await source.cookies(for: url, profileID: profileID)

        await source.prepareForRemoval(profileID: profileID)
        defer {
            source.finishRemoval(profileID: profileID)
        }
        try await ClaudeWebProfileStore.remove(profileID: profileID)
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
private final class StallableClaudeWebProfileCookieLoader:
    ClaudeWebProfileCookieLoading
{
    private(set) var completedLoads = 0
    private var loadContinuation: CheckedContinuation<Void, Never>?
    private var loadingContinuation: CheckedContinuation<Void, Never>?
    private var isLoading = false

    func cookies() async -> [HTTPCookie] {
        isLoading = true
        loadingContinuation?.resume()
        loadingContinuation = nil
        await withCheckedContinuation { continuation in
            loadContinuation = continuation
        }
        completedLoads += 1
        return []
    }

    func warmIfNeeded() {}

    func waitUntilLoading() async {
        guard !isLoading else {
            return
        }
        await withCheckedContinuation { continuation in
            loadingContinuation = continuation
        }
    }

    func finishLoading() {
        loadContinuation?.resume()
        loadContinuation = nil
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
