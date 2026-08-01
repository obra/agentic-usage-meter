import Foundation
import Testing

@testable import UsageMeterCore

@Suite
struct SuperGrokUsageDecoderTests {
    @Test
    func currentBillingJSONBecomesWeeklyUsageAndPrepaidBalance()
        throws
    {
        let accountID = UUID()
        let fetchedAt = Date(
            timeIntervalSince1970: 1_785_000_000
        )
        let response = Data(
            #"""
            {
              "config": {
                "creditUsagePercent": 42.5,
                "currentPeriod": {
                  "type": "USAGE_PERIOD_TYPE_WEEKLY",
                  "start": "2026-07-30T00:00:00Z",
                  "end": "2026-08-06T00:00:00Z"
                },
                "prepaidBalance": { "val": 1234 },
                "isUnifiedBillingUser": true
              },
              "onDemandEnabled": true,
              "subscriptionTier": "SuperGrok Heavy"
            }
            """#.utf8
        )

        let snapshot = try SuperGrokUsageDecoder()
            .decode(
                response,
                accountID: accountID,
                fetchedAt: fetchedAt
            )

        #expect(snapshot.accountID == accountID)
        #expect(snapshot.fetchedAt == fetchedAt)
        let window = try #require(
            snapshot.windows.only
        )
        #expect(window.id == "supergrok-weekly")
        #expect(window.kind == .weekly)
        #expect(window.duration == 604_800)
        #expect(window.consumedFraction == 0.425)
        #expect(
            window.reportedStartAt
                == Date(
                    timeIntervalSince1970:
                        1_785_369_600
                )
        )
        #expect(
            window.resetAt
                == Date(
                    timeIntervalSince1970:
                        1_785_974_400
                )
        )
        let balance = try #require(
            snapshot.balances.only
        )
        #expect(balance.id == "supergrok-prepaid")
        #expect(balance.label == "Extra usage")
        #expect(
            balance.value
                == .available(
                    amount: Decimal(string: "12.34")!,
                    unit: "USD"
                )
        )
    }

    @Test
    func currentMonthlyPeriodBecomesMonthlyUsage() throws {
        let response = Data(
            #"""
            {
              "config": {
                "creditUsagePercent": 25,
                "currentPeriod": {
                  "type": "USAGE_PERIOD_TYPE_MONTHLY",
                  "start": "2026-07-01T00:00:00Z",
                  "end": "2026-08-01T00:00:00Z"
                }
              }
            }
            """#.utf8
        )

        let snapshot = try SuperGrokUsageDecoder()
            .decode(
                response,
                accountID: UUID(),
                fetchedAt: Date()
            )

        let window = try #require(
            snapshot.windows.only
        )
        #expect(window.id == "supergrok-monthly")
        #expect(window.kind == .monthly)
        #expect(window.duration == 2_678_400)
        #expect(window.consumedFraction == 0.25)
    }

    @Test
    func omittedCurrentUsagePercentMeansZeroUsed() throws {
        let response = Data(
            #"""
            {
              "config": {
                "currentPeriod": {
                  "type": "USAGE_PERIOD_TYPE_WEEKLY",
                  "start": "2026-07-30T00:00:00Z",
                  "end": "2026-08-06T00:00:00Z"
                }
              }
            }
            """#.utf8
        )

        let snapshot = try SuperGrokUsageDecoder()
            .decode(
                response,
                accountID: UUID(),
                fetchedAt: Date()
            )

        let window = try #require(
            snapshot.windows.only
        )
        #expect(window.kind == .weekly)
        #expect(window.consumedFraction == 0)
    }

    @Test
    func legacyMonthlyBillingBecomesMonthlyUsage() throws {
        let response = Data(
            #"""
            {
              "config": {
                "monthlyLimit": { "val": 10000 },
                "used": { "val": 3750 },
                "billingPeriodStart": "2026-07-01T00:00:00Z",
                "billingPeriodEnd": "2026-08-01T00:00:00Z"
              }
            }
            """#.utf8
        )

        let snapshot = try SuperGrokUsageDecoder()
            .decode(
                response,
                accountID: UUID(),
                fetchedAt: Date()
            )

        let window = try #require(
            snapshot.windows.only
        )
        #expect(window.id == "supergrok-monthly")
        #expect(window.kind == .monthly)
        #expect(window.duration == 2_678_400)
        #expect(window.consumedFraction == 0.375)
    }

    @Test
    func responseWithoutUsageOrResetIsRejected() {
        #expect(
            throws:
                ProviderClientError
                .unsupportedResponse
        ) {
            _ = try SuperGrokUsageDecoder()
                .decode(
                    Data(#"{"config":{}}"#.utf8),
                    accountID: UUID(),
                    fetchedAt: Date()
                )
        }
    }
}

extension Collection {
    fileprivate var only: Element? {
        count == 1 ? first : nil
    }
}
