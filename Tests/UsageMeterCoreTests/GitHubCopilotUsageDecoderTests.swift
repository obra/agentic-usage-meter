import Foundation
import Testing

@testable import UsageMeterCore

@Suite
struct GitHubCopilotUsageDecoderTests {
    @Test
    func limitedPoolsRemainIndependentAndUnlimitedPoolsAreOmitted()
        throws
    {
        let accountID = UUID()
        let fetchedAt = Date(
            timeIntervalSince1970: 1_775_000_000
        )

        let result = try GitHubCopilotUsageDecoder()
            .decode(
                usageFixture(
                    named: "github-copilot-usage"
                ),
                accountID: accountID,
                fetchedAt: fetchedAt
            )

        #expect(result.plan == "individual_pro")
        #expect(result.userID == "42")
        #expect(result.snapshot.accountID == accountID)
        #expect(result.snapshot.fetchedAt == fetchedAt)
        #expect(
            result.snapshot.windows.map(\.id)
                == [
                    "github-copilot-completions",
                    "github-copilot-premium-interactions",
                ]
        )
        #expect(
            result.snapshot.windows.map(\.kind)
                == [.monthly, .monthly]
        )
        #expect(
            result.snapshot.windows.map(
                \.consumedFraction
            ) == [0.25, 0.6]
        )
        #expect(
            result.snapshot.windows.map(\.label)
                == [
                    "Completions",
                    "Premium interactions",
                ]
        )
        #expect(
            result.snapshot.windows.map(\.resetAt)
                == [
                    Date(
                        timeIntervalSince1970:
                            1_785_542_400
                    ),
                    Date(
                        timeIntervalSince1970:
                            1_785_542_400
                    ),
                ]
        )
        #expect(
            result.snapshot.windows.map(\.duration)
                == [2_678_400, 2_678_400]
        )
    }
}
