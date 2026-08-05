import Foundation
import Testing

@testable import UsageMeterCore

@Suite
struct MiMoUsageDecoderTests {
    @Test
    func monthlyTokenBundleBecomesRemainingBalance() throws {
        let data = try usageFixture(
            named: "mimo-token-plan-usage"
        )
        let accountID = UUID()
        let fetchedAt = Date(timeIntervalSince1970: 2_000_000_000)

        let snapshot = try MiMoUsageDecoder().decode(
            data,
            accountID: accountID,
            fetchedAt: fetchedAt
        )

        #expect(snapshot.accountID == accountID)
        #expect(snapshot.fetchedAt == fetchedAt)
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.balances.count == 1)
        #expect(snapshot.balances[0].id == "mimo-monthly-tokens")
        #expect(snapshot.balances[0].label == "Monthly tokens")
        #expect(
            snapshot.balances[0].value
                == .available(
                    amount: Decimal(73_417_690_721),
                    unit: "tokens"
                )
        )
    }

    @Test
    func usageBeyondTheLimitClampsToZeroRemaining() throws {
        let data = Data(
            """
            {
              "code": 0,
              "message": "",
              "data": {
                "monthUsage": {
                  "percent": 1,
                  "items": [
                    {
                      "name": "month_total_token",
                      "used": 82000000001,
                      "limit": 82000000000,
                      "percent": 1
                    }
                  ]
                }
              }
            }
            """.utf8
        )

        let snapshot = try MiMoUsageDecoder().decode(
            data,
            accountID: UUID(),
            fetchedAt: Date(timeIntervalSince1970: 2_000_000_000)
        )

        #expect(
            snapshot.balances.map(\.value)
                == [.available(amount: 0, unit: "tokens")]
        )
    }

    @Test
    func errorCodesAndMalformedResponsesAreRejected() {
        let responses = [
            """
            {"code": 401, "message": "unauthorized"}
            """,
            """
            {"code": 0, "message": "", "data": {}}
            """,
            """
            {
              "code": 0,
              "message": "",
              "data": {
                "monthUsage": {
                  "percent": 0,
                  "items": [
                    {
                      "name": "month_total_token",
                      "used": 0,
                      "limit": 0,
                      "percent": 0
                    }
                  ]
                }
              }
            }
            """,
            "<html>login</html>",
        ]

        for response in responses {
            #expect(throws: ProviderClientError.unsupportedResponse) {
                _ = try MiMoUsageDecoder().decode(
                    Data(response.utf8),
                    accountID: UUID(),
                    fetchedAt: Date()
                )
            }
        }
    }
}
