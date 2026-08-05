import Foundation
import Testing

@testable import UsageMeterCore

@Suite
struct ZaiUsageDecoderTests {
    @Test
    func tokenLimitEntriesBecomeShortAndWeeklyWindows() throws {
        let data = try usageFixture(named: "zai-quota-limit")
        let accountID = UUID()
        let fetchedAt = Date(timeIntervalSince1970: 2_000_000_000)

        let snapshot = try ZaiUsageDecoder().decode(
            data,
            accountID: accountID,
            fetchedAt: fetchedAt
        )

        #expect(snapshot.accountID == accountID)
        #expect(snapshot.fetchedAt == fetchedAt)
        #expect(snapshot.windows.count == 2)
        #expect(snapshot.windows[0].id == "zai-short")
        #expect(snapshot.windows[0].kind == .short)
        #expect(snapshot.windows[0].duration == 18_000)
        #expect(snapshot.windows[0].consumedFraction == 0.375)
        #expect(
            snapshot.windows[0].resetAt
                == Date(timeIntervalSince1970: 1_785_912_345.678)
        )
        #expect(snapshot.windows[1].id == "zai-weekly")
        #expect(snapshot.windows[1].kind == .weekly)
        #expect(snapshot.windows[1].duration == 604_800)
        #expect(snapshot.windows[1].consumedFraction == 0.12)
        #expect(
            snapshot.windows[1].resetAt
                == Date(timeIntervalSince1970: 1_785_998_765.432)
        )
    }

    @Test
    func zeroUsageWindowWithoutResetIsPreservedAsInactive() throws {
        let data = Data(
            """
            {
              "code": 200,
              "msg": "Operation successful",
              "data": {
                "limits": [
                  {
                    "type": "TOKENS_LIMIT",
                    "unit": 3,
                    "number": 5,
                    "percentage": 0
                  },
                  {
                    "type": "TOKENS_LIMIT",
                    "unit": 6,
                    "number": 1,
                    "percentage": 0,
                    "nextResetTime": 1785912345678
                  }
                ],
                "level": "max"
              },
              "success": true
            }
            """.utf8
        )

        let snapshot = try ZaiUsageDecoder().decode(
            data,
            accountID: UUID(),
            fetchedAt: Date(timeIntervalSince1970: 2_000_000_000)
        )

        #expect(snapshot.windows.count == 2)
        #expect(snapshot.windows[0].resetAt == nil)
        #expect(snapshot.windows[0].consumedFraction == 0)
        #expect(
            snapshot.windows[1].resetAt
                == Date(timeIntervalSince1970: 1_785_912_345.678)
        )
    }

    @Test
    func nonzeroWindowWithoutResetIsRejected() {
        let data = Data(
            """
            {
              "code": 200,
              "data": {
                "limits": [
                  {
                    "type": "TOKENS_LIMIT",
                    "unit": 3,
                    "number": 5,
                    "percentage": 42
                  }
                ]
              },
              "success": true
            }
            """.utf8
        )

        #expect(throws: ProviderClientError.unsupportedResponse) {
            _ = try ZaiUsageDecoder().decode(
                data,
                accountID: UUID(),
                fetchedAt: Date()
            )
        }
    }

    @Test
    func bodyLevelAuthenticationFailurePromptsReconnect() {
        #expect(
            throws: ProviderClientError.reauthenticationRequired
        ) {
            _ = try ZaiUsageDecoder().decode(
                Data(
                    """
                    {"code": 401, "msg": "Unauthorized", "success": false}
                    """.utf8
                ),
                accountID: UUID(),
                fetchedAt: Date()
            )
        }
    }

    @Test
    func errorEnvelopeAndMissingTokenLimitsAreRejected() {
        let responses = [
            """
            {"code": 500, "msg": "failed", "success": false}
            """,
            """
            {
              "code": 200,
              "success": false,
              "data": {
                "limits": [
                  {
                    "type": "TOKENS_LIMIT",
                    "unit": 3,
                    "number": 5,
                    "percentage": 10,
                    "nextResetTime": 1785912345678
                  }
                ]
              }
            }
            """,
            """
            {"code": 200, "data": {"limits": []}, "success": true}
            """,
            """
            {
              "code": 200,
              "data": {
                "limits": [
                  {
                    "type": "TIME_LIMIT",
                    "unit": 5,
                    "number": 1,
                    "usage": 4000,
                    "currentValue": 0,
                    "remaining": 4000,
                    "percentage": 0
                  }
                ]
              },
              "success": true
            }
            """,
            "not json",
        ]

        for response in responses {
            #expect(throws: ProviderClientError.unsupportedResponse) {
                _ = try ZaiUsageDecoder().decode(
                    Data(response.utf8),
                    accountID: UUID(),
                    fetchedAt: Date()
                )
            }
        }
    }
}
