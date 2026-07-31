import Foundation
import Testing

@testable import UsageMeterCore

@Suite
struct OpenCodeZenUsageDecoderTests {
    @Test
    func balanceAndConfiguredMonthlyLimitAreNormalized()
        throws
    {
        let accountID = UUID()
        let fetchedAt = Date(
            timeIntervalSince1970: 1_775_003_600
        )
        let html = #"""
            <script>
            self.__next_f.push([1,"{\"customerID\":\"cus_123\",\"balance\":1500000000,\"monthlyLimit\":20,\"monthlyUsage\":500000000,\"timeMonthlyUsageUpdated\":\"2026-04-01T12:00:00.000Z\"}"])
            </script>
            """#

        let snapshot = try OpenCodeZenUsageDecoder()
            .decode(
                Data(html.utf8),
                accountID: accountID,
                fetchedAt: fetchedAt
            )

        let balance = try #require(
            snapshot.balances.first
        )
        #expect(balance.id == "opencode-zen-balance")
        #expect(balance.label == "Zen balance")
        #expect(balance.remainingAmount == 15)
        #expect(balance.unit == "USD")

        let monthly = try #require(
            snapshot.windows.first
        )
        #expect(monthly.id == "opencode-zen-monthly")
        #expect(monthly.kind == .monthly)
        #expect(monthly.consumedFraction == 0.25)
        #expect(
            monthly.resetAt
                == Date(
                    timeIntervalSince1970:
                        1_777_593_600
                )
        )
    }

    @Test
    func missingMonthlyLimitKeepsOnlyTheProviderBalance()
        throws
    {
        let html = #"""
            <script>
            self.__next_f.push([1,"{\"balance\":725000000,\"monthlyLimit\":null,\"monthlyUsage\":null}"])
            </script>
            """#

        let snapshot = try OpenCodeZenUsageDecoder()
            .decode(
                Data(html.utf8),
                accountID: UUID(),
                fetchedAt: Date()
            )

        #expect(snapshot.windows.isEmpty)
        #expect(
            snapshot.balances.first?
                .remainingAmount == 7.25
        )
    }

    @Test
    func missingBalanceIsRejected() {
        #expect(
            throws:
                ProviderClientError
                .unsupportedResponse
        ) {
            _ = try OpenCodeZenUsageDecoder()
                .decode(
                    Data(
                        """
                        {"monthlyLimit": 20}
                        """.utf8
                    ),
                    accountID: UUID(),
                    fetchedAt: Date()
                )
        }
    }
}
