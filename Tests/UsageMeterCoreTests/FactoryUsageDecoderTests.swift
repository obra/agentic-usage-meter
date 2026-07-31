import Foundation
import Testing

@testable import UsageMeterCore

@Suite
struct FactoryUsageDecoderTests {
    @Test
    func standardAndCorePoolsRemainIndependent() throws {
        let accountID = UUID()
        let fetchedAt = Date(
            timeIntervalSince1970: 1_775_088_000
        )

        let snapshot = try FactoryUsageDecoder().decode(
            usageFixture(named: "factory-limits"),
            accountID: accountID,
            fetchedAt: fetchedAt
        )

        #expect(snapshot.accountID == accountID)
        #expect(snapshot.fetchedAt == fetchedAt)
        #expect(
            snapshot.windows.map(\.id) == [
                "factory-standard-five-hour",
                "factory-standard-weekly",
                "factory-standard-monthly",
                "factory-core-five-hour",
                "factory-core-weekly",
                "factory-core-monthly",
            ]
        )
        #expect(
            snapshot.windows.map(\.kind) == [
                .short,
                .weekly,
                .monthly,
                .short,
                .weekly,
                .monthly,
            ]
        )
        #expect(
            snapshot.windows.map(\.label) == [
                "Standard",
                "Standard",
                "Standard",
                "Droid Core",
                "Droid Core",
                "Droid Core",
            ]
        )
        #expect(
            snapshot.windows.map(\.consumedFraction) == [
                0.225,
                0.48,
                0.6125,
                0.07,
                0.11,
                0.19,
            ]
        )
        #expect(
            snapshot.windows.map(\.duration) == [
                18_000,
                604_800,
                2_592_000,
                18_000,
                604_800,
                2_592_000,
            ]
        )
        #expect(
            snapshot.windows[0].resetAt
                == Date(timeIntervalSince1970: 1_785_452_400)
        )
        #expect(
            snapshot.balances == [
                UsageBalance(
                    id: "factory-extra-usage",
                    label: "Extra usage",
                    remainingAmount: 12.34,
                    unit: "USD"
                )!
            ]
        )
    }

    @Test
    func absentPoolsWindowsAndBalanceStayAbsent() throws {
        let data = Data(
            """
            {
              "usesTokenRateLimitsBilling": true,
              "limits": {
                "standard": {
                  "weekly": {
                    "usedPercent": 31,
                    "windowEnd": "2026-08-03T07:00:00Z"
                  }
                }
              }
            }
            """.utf8
        )

        let snapshot = try FactoryUsageDecoder().decode(
            data,
            accountID: UUID(),
            fetchedAt: Date(
                timeIntervalSince1970: 1_775_088_000
            )
        )

        #expect(snapshot.windows.count == 1)
        #expect(
            snapshot.windows[0].id
                == "factory-standard-weekly"
        )
        #expect(snapshot.windows[0].consumedFraction == 0.31)
        #expect(snapshot.balances.isEmpty)
    }

    @Test
    func inactiveRollingWindowsWithoutEndsRemainVisible() throws {
        let data = Data(
            """
            {
              "usesTokenRateLimitsBilling": true,
              "limits": {
                "standard": {
                  "fiveHour": { "usedPercent": 0 },
                  "weekly": { "usedPercent": 0 },
                  "monthly": { "usedPercent": 0 }
                },
                "core": {
                  "fiveHour": { "usedPercent": 0 },
                  "weekly": { "usedPercent": 0 },
                  "monthly": { "usedPercent": 0 }
                }
              },
              "extraUsageBalanceCents": 0,
              "overagePreference": "droidCore",
              "extraUsageAllowed": true
            }
            """.utf8
        )

        let snapshot = try FactoryUsageDecoder().decode(
            data,
            accountID: UUID(),
            fetchedAt: Date(
                timeIntervalSince1970: 1_775_088_000
            )
        )

        #expect(snapshot.windows.count == 6)
        #expect(snapshot.windows.allSatisfy { $0.resetAt == nil })
        #expect(
            snapshot.windows.allSatisfy {
                $0.consumedFraction == 0
            },
        )
        #expect(
            snapshot.balances.map(\.value)
                == [
                    .available(
                        amount: Decimal(string: "0")!,
                        unit: "USD",
                    )
                ],
        )
    }

    @Test
    func explicitlyDisabledExtraUsageRendersOff() throws {
        let data = Data(
            """
            {
              "usesTokenRateLimitsBilling": true,
              "limits": {
                "standard": {
                  "weekly": {
                    "usedPercent": 20,
                    "windowEnd": "2026-08-03T07:00:00Z"
                  }
                }
              },
              "extraUsageAllowed": false
            }
            """.utf8,
        )

        let snapshot = try FactoryUsageDecoder().decode(
            data,
            accountID: UUID(),
            fetchedAt: Date(timeIntervalSince1970: 1_775_088_000),
        )

        #expect(snapshot.balances.map(\.value) == [.disabled])
    }

    @Test
    func monthlyDurationUsesThirtyDayRollingWindow() throws {
        let data = Data(
            """
            {
              "usesTokenRateLimitsBilling": true,
              "limits": {
                "standard": {
                  "monthly": {
                    "usedPercent": 20,
                    "windowEnd": "2026-03-01T00:00:00Z"
                  }
                }
              }
            }
            """.utf8
        )

        let snapshot = try FactoryUsageDecoder().decode(
            data,
            accountID: UUID(),
            fetchedAt: Date(
                timeIntervalSince1970: 1_775_088_000
            )
        )

        #expect(snapshot.windows.count == 1)
        #expect(snapshot.windows[0].duration == 2_592_000)
    }

    @Test
    func legacyBillingAndMalformedWindowsAreRejected() {
        let unsupported = Data(
            """
            {
              "usesTokenRateLimitsBilling": false,
              "limits": {}
            }
            """.utf8
        )
        let malformed = Data(
            """
            {
              "usesTokenRateLimitsBilling": true,
              "limits": {
                "standard": {
                  "fiveHour": {
                    "usedPercent": 101,
                    "windowEnd": "not-a-date"
                  }
                }
              }
            }
            """.utf8
        )
        let activeWithoutEnd = Data(
            """
            {
              "usesTokenRateLimitsBilling": true,
              "limits": {
                "standard": {
                  "fiveHour": {
                    "usedPercent": 1
                  }
                }
              }
            }
            """.utf8
        )

        for data in [
            unsupported,
            malformed,
            activeWithoutEnd,
        ] {
            #expect(
                throws: ProviderClientError.unsupportedResponse
            ) {
                _ = try FactoryUsageDecoder().decode(
                    data,
                    accountID: UUID(),
                    fetchedAt: Date(
                        timeIntervalSince1970: 1_775_088_000
                    )
                )
            }
        }
    }
}
