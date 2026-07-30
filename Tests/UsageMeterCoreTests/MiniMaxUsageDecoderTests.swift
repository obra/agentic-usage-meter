import Foundation
import Testing

@testable import UsageMeterCore

@Suite
struct MiniMaxUsageDecoderTests {
    @Test
    func remainingCountsBecomeConsumedFractions() throws {
        let accountID = UUID()
        let fetchedAt = Date(
            timeIntervalSince1970: 1_774_587_600
        )

        let snapshot = try MiniMaxUsageDecoder().decode(
            usageFixture(named: "minimax-usage"),
            accountID: accountID,
            fetchedAt: fetchedAt
        )

        #expect(snapshot.accountID == accountID)
        #expect(snapshot.fetchedAt == fetchedAt)
        #expect(snapshot.windows.map(\.kind) == [.short, .weekly])
        #expect(snapshot.windows[0].consumedFraction == 0.5)
        #expect(snapshot.windows[1].consumedFraction == 0.6)
        #expect(snapshot.windows[0].duration == 18_000)
        #expect(snapshot.windows[1].duration == 604_800)
        #expect(
            snapshot.windows[0].resetAt
                == Date(timeIntervalSince1970: 1_774_605_600)
        )
        #expect(
            snapshot.windows[0].reportedStartAt
                == Date(timeIntervalSince1970: 1_774_587_600)
        )
    }

    @Test
    func subOnePercentConsumptionIsNotRoundedAway() throws {
        let data = Data(
            """
            {
              "model_remains": [{
                "start_time": "1774587600000",
                "end_time": "1774605600000",
                "current_interval_total_count": "1500",
                "current_interval_usage_count": "1494",
                "model_name": "MiniMax-M*"
              }],
              "base_resp": {
                "status_code": "0",
                "status_msg": "success"
              }
            }
            """.utf8
        )

        let snapshot = try MiniMaxUsageDecoder().decode(
            data,
            accountID: UUID(),
            fetchedAt: Date(
                timeIntervalSince1970: 1_774_587_600
            )
        )

        #expect(snapshot.windows.count == 1)
        #expect(snapshot.windows[0].consumedFraction == 0.004)
    }

    @Test
    func nonzeroProviderStatusIsRejected() {
        let data = Data(
            """
            {
              "model_remains": [],
              "base_resp": {
                "status_code": 1004,
                "status_msg": "invalid token"
              }
            }
            """.utf8
        )

        #expect(throws: ProviderClientError.unsupportedResponse) {
            _ = try MiniMaxUsageDecoder().decode(
                data,
                accountID: UUID(),
                fetchedAt: Date(
                    timeIntervalSince1970: 1_774_587_600
                )
            )
        }
    }
}
