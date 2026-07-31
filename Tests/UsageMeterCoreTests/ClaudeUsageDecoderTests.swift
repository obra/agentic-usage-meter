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
