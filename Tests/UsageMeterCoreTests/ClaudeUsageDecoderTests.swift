import Foundation
import Testing
@testable import UsageMeterCore

@Suite
struct ClaudeUsageDecoderTests {
    @Test
    func requiredWindowsDecodeWithoutProviderTransport() throws {
        let data = try fixture(named: "claude-usage")
        let accountID = UUID()
        let fetchedAt = Date(timeIntervalSince1970: 2_000_000_000)

        let snapshot = try ClaudeUsageDecoder().decode(
            data,
            accountID: accountID,
            fetchedAt: fetchedAt
        )

        #expect(snapshot.accountID == accountID)
        #expect(snapshot.fetchedAt == fetchedAt)
        #expect(snapshot.windows.count == 2)
        #expect(snapshot.windows[0].kind == .short)
        #expect(snapshot.windows[0].duration == 18_000)
        #expect(snapshot.windows[0].consumedFraction == 0.81)
        #expect(snapshot.windows[1].kind == .weekly)
        #expect(snapshot.windows[1].duration == 604_800)
        #expect(snapshot.windows[1].consumedFraction == 0.66)
    }
}

private func fixture(named name: String) throws -> Data {
    let url = try #require(
        Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures"
        )
    )
    return try Data(contentsOf: url)
}
