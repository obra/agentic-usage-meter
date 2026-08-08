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
        #expect(snapshot.windows.count == 3)
        #expect(snapshot.windows[0].kind == .short)
        #expect(snapshot.windows[0].duration == 18_000)
        #expect(snapshot.windows[0].consumedFraction == 0.81)
        #expect(snapshot.windows[1].kind == .weekly)
        #expect(snapshot.windows[1].duration == 604_800)
        #expect(snapshot.windows[1].consumedFraction == 0.66)
        #expect(snapshot.windows[2].id == "claude-weekly-scoped-fable")
        #expect(snapshot.windows[2].kind == .weekly)
        #expect(snapshot.windows[2].duration == 604_800)
        #expect(snapshot.windows[2].consumedFraction == 0.42)
        #expect(snapshot.windows[2].label == "Fable")
    }

    @Test
    func scopedLimitEntriesAreFilteredWithoutRejectingTheResponse() throws {
        let data = Data(
            """
            {
              "five_hour": {
                "utilization": 10,
                "resets_at": "2026-08-01T00:00:00Z"
              },
              "seven_day": {
                "utilization": 20,
                "resets_at": "2026-08-03T00:00:00Z"
              },
              "limits": [
                {
                  "kind": "weekly_all",
                  "group": "weekly",
                  "percent": 20,
                  "resets_at": "2026-08-03T00:00:00Z",
                  "scope": null,
                  "is_active": false
                },
                {
                  "kind": "session_scoped",
                  "group": "session",
                  "percent": 15,
                  "resets_at": "2026-08-01T00:00:00Z",
                  "scope": {
                    "model": {"id": null, "display_name": "Fable"},
                    "surface": null
                  },
                  "is_active": true
                },
                {
                  "kind": "weekly_scoped",
                  "group": "weekly",
                  "percent": "not-a-number",
                  "resets_at": "2026-08-03T00:00:00Z",
                  "scope": {
                    "model": {"id": null, "display_name": "Fable"},
                    "surface": null
                  },
                  "is_active": true
                },
                {
                  "kind": "weekly_scoped",
                  "group": "weekly",
                  "percent": 40,
                  "resets_at": null,
                  "scope": {
                    "model": {"id": null, "display_name": "Fable"},
                    "surface": null
                  },
                  "is_active": true
                },
                {
                  "kind": "weekly_scoped",
                  "group": "weekly",
                  "percent": 35,
                  "resets_at": "2026-08-03T00:00:00Z",
                  "scope": {
                    "model": {"id": null, "display_name": "Fable"},
                    "surface": null
                  },
                  "is_active": false
                },
                {
                  "kind": "weekly_scoped",
                  "group": "weekly",
                  "percent": 50,
                  "resets_at": "2026-08-03T00:00:00Z",
                  "scope": {
                    "model": {"id": null, "display_name": "Fable"},
                    "surface": null
                  },
                  "is_active": true
                }
              ]
            }
            """.utf8,
        )

        let snapshot = try ClaudeUsageDecoder().decode(
            data,
            accountID: UUID(),
            fetchedAt: Date(timeIntervalSince1970: 2_000_000_000),
        )

        // The unscoped entry duplicates the legacy weekly window, the
        // scoped session-group entry is unqualified surface, and the
        // malformed percent and the nonzero resetless entry are
        // dropped. The two valid Fable entries collide on id and
        // resolve to the higher-consumed one, so a duplicate can only
        // tighten the reported limit; the loser's inactive flag is
        // irrelevant because the provider reports real percents on
        // inactive scoped entries too.
        #expect(snapshot.windows.count == 3)
        #expect(snapshot.windows[2].id == "claude-weekly-scoped-fable")
        #expect(snapshot.windows[2].consumedFraction == 0.5)
        #expect(snapshot.windows[2].label == "Fable")
    }

    @Test
    func driftedLimitsContainerDoesNotRejectTheLegacyWindows() throws {
        for limits in ["{}", "3", "\"drifted\"", "null"] {
            let data = Data(
                """
                {
                  "five_hour": {
                    "utilization": 10,
                    "resets_at": "2026-08-01T00:00:00Z"
                  },
                  "seven_day": {
                    "utilization": 20,
                    "resets_at": "2026-08-03T00:00:00Z"
                  },
                  "limits": \(limits)
                }
                """.utf8,
            )

            let snapshot = try ClaudeUsageDecoder().decode(
                data,
                accountID: UUID(),
                fetchedAt: Date(timeIntervalSince1970: 2_000_000_000),
            )

            #expect(
                snapshot.windows.map(\.id) == ["five-hour", "seven-day"]
            )
        }
    }

    @Test
    func responseWithoutLimitsKeepsTheLegacyWindowPair() throws {
        let data = Data(
            """
            {
              "five_hour": {
                "utilization": 10,
                "resets_at": "2026-08-01T00:00:00Z"
              },
              "seven_day": {
                "utilization": 20,
                "resets_at": "2026-08-03T00:00:00Z"
              }
            }
            """.utf8,
        )

        let snapshot = try ClaudeUsageDecoder().decode(
            data,
            accountID: UUID(),
            fetchedAt: Date(timeIntervalSince1970: 2_000_000_000),
        )

        #expect(snapshot.windows.map(\.id) == ["five-hour", "seven-day"])
    }

    @Test
    func inactiveWindowAndDisabledCreditsArePreserved() throws {
        let data = Data(
            """
            {
              "five_hour": {
                "utilization": 0,
                "resets_at": null
              },
              "seven_day": {
                "utilization": 12,
                "resets_at": "2026-08-03T21:40:00Z"
              },
              "extra_usage": {
                "is_enabled": false,
                "user_disabled": true,
                "currency": "USD",
                "decimal_places": 2
              },
              "spend": {
                "enabled": false,
                "balance": null
              }
            }
            """.utf8,
        )

        let snapshot = try ClaudeUsageDecoder().decode(
            data,
            accountID: UUID(),
            fetchedAt: Date(timeIntervalSince1970: 2_000_000_000),
        )

        #expect(snapshot.windows[0].resetAt == nil)
        #expect(snapshot.windows[0].consumedFraction == 0)
        #expect(snapshot.balances.map(\.label) == ["Usage credits"])
        #expect(snapshot.balances.map(\.value) == [.disabled])
    }

    @Test
    func authoritativeSpendBalanceBecomesAvailableCredits() throws {
        let data = Data(
            """
            {
              "five_hour": {
                "utilization": 10,
                "resets_at": "2026-08-01T00:00:00Z"
              },
              "seven_day": {
                "utilization": 20,
                "resets_at": "2026-08-03T00:00:00Z"
              },
              "extra_usage": {
                "is_enabled": true,
                "user_disabled": false,
                "currency": "USD",
                "decimal_places": 2
              },
              "spend": {
                "enabled": true,
                "balance": {
                  "amount_minor": 3842,
                  "currency": "USD",
                  "exponent": 2
                }
              }
            }
            """.utf8,
        )

        let snapshot = try ClaudeUsageDecoder().decode(
            data,
            accountID: UUID(),
            fetchedAt: Date(timeIntervalSince1970: 2_000_000_000),
        )

        #expect(
            snapshot.balances.map(\.value)
                == [
                    .available(
                        amount: Decimal(string: "38.42")!,
                        unit: "USD",
                    )
                ],
        )
    }

    @Test
    func fractionalSecondResetTimestampsDecode() throws {
        let data = Data(
            """
            {
              "five_hour": {
                "utilization": 10,
                "resets_at": "2026-08-03T12:10:00.646247+00:00"
              },
              "seven_day": {
                "utilization": 20,
                "resets_at": "2026-08-05T00:00:00.711237+00:00"
              }
            }
            """.utf8,
        )

        let snapshot = try ClaudeUsageDecoder().decode(
            data,
            accountID: UUID(),
            fetchedAt: Date(timeIntervalSince1970: 2_000_000_000),
        )

        let shortReset = try #require(snapshot.windows[0].resetAt)
        let weeklyReset = try #require(snapshot.windows[1].resetAt)
        #expect(
            abs(shortReset.timeIntervalSince1970 - 1_785_759_000.646247) < 1,
        )
        #expect(
            abs(weeklyReset.timeIntervalSince1970 - 1_785_888_000.711237) < 1,
        )
    }

    @Test
    func nonzeroResetlessWindowAndMalformedBalanceAreRejected() {
        let responses = [
            """
            {
              "five_hour": {"utilization": 1, "resets_at": null},
              "seven_day": {"utilization": 0, "resets_at": null}
            }
            """,
            """
            {
              "five_hour": {"utilization": 0, "resets_at": null},
              "seven_day": {"utilization": 0, "resets_at": null},
              "extra_usage": {"is_enabled": true, "user_disabled": false},
              "spend": {
                "enabled": true,
                "balance": {
                  "amount_minor": 100,
                  "currency": "USD",
                  "exponent": -1
                }
              }
            }
            """,
        ]

        for response in responses {
            #expect(throws: ProviderClientError.unsupportedResponse) {
                _ = try ClaudeUsageDecoder().decode(
                    Data(response.utf8),
                    accountID: UUID(),
                    fetchedAt: Date(),
                )
            }
        }
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
