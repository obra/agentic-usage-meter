import Foundation
import Testing

@testable import UsageMeterCore

@Suite
struct OpenCodeGoUsageDecoderTests {
    @Test
    func dashboardWindowsRemainIndependent()
        throws
    {
        let accountID = UUID()
        let fetchedAt = Date(
            timeIntervalSince1970: 1_800_000_000
        )
        let html = #"""
            <script>
            self.__next_f.push([1,"{\"rollingUsage\":{\"usagePercent\":12.5,\"resetInSec\":3600},\"weeklyUsage\":{\"usagePercent\":\"25\",\"resetInSec\":\"7200\"},\"monthlyUsage\":{\"usagePercent\":50,\"resetInSec\":10800}}"])
            </script>
            """#

        let snapshot = try OpenCodeGoUsageDecoder()
            .decode(
                Data(html.utf8),
                accountID: accountID,
                fetchedAt: fetchedAt
            )

        #expect(snapshot.accountID == accountID)
        #expect(
            snapshot.windows.map(\.id)
                == [
                    "opencode-go-rolling",
                    "opencode-go-weekly",
                    "opencode-go-monthly",
                ]
        )
        #expect(
            snapshot.windows.map(\.kind)
                == [.short, .weekly, .monthly]
        )
        #expect(
            snapshot.windows.map(
                \.consumedFraction
            ) == [0.125, 0.25, 0.5]
        )
        #expect(
            snapshot.windows.map(\.resetAt)
                == [
                    fetchedAt.addingTimeInterval(
                        3_600
                    ),
                    fetchedAt.addingTimeInterval(
                        7_200
                    ),
                    fetchedAt.addingTimeInterval(
                        10_800
                    ),
                ]
        )
        #expect(
            snapshot.windows[0].duration
                == 5 * 60 * 60
        )
        #expect(
            snapshot.windows[1].duration
                == 7 * 24 * 60 * 60
        )
    }

    @Test
    func solidResourceReferencesAndPartialWindowsDecode()
        throws
    {
        let html = #"""
            <script>
            $R[24]($R[18],$R[30]={mine:!0,useBalance:!0,rollingUsage:$R[31]={status:"ok",resetInSec:18000,usagePercent:0},weeklyUsage:$R[32]={status:"ok",resetInSec:162822,usagePercent:31}});
            </script>
            """#

        let snapshot = try OpenCodeGoUsageDecoder()
            .decode(
                Data(html.utf8),
                accountID: UUID(),
                fetchedAt: Date()
            )

        #expect(snapshot.windows.count == 2)
        #expect(
            snapshot.windows.map(\.id)
                == [
                    "opencode-go-rolling",
                    "opencode-go-weekly",
                ]
        )
        #expect(
            snapshot.windows.map(
                \.consumedFraction
            ) == [0, 0.31]
        )
    }

    @Test
    func dataSlotDashboardWindowsDecode()
        throws
    {
        let fetchedAt = Date(
            timeIntervalSince1970: 1_800_000_000
        )
        let html = #"""
            <div data-slot="usage">
              <div data-slot="usage-item">
                <span data-slot="usage-label">Rolling Usage</span>
                <span data-slot="usage-value"><!--$-->7<!--/-->%</span>
                <span data-slot="reset-time"><!--$-->Resets in<!--/--> <!--$-->1 hour 56 minutes<!--/--></span>
              </div>
              <div data-slot="usage-item">
                <span data-slot="usage-label">Weekly Usage</span>
                <span data-slot="usage-value"><!--$-->10<!--/-->%</span>
                <span data-slot="reset-time"><!--$-->Resets in<!--/--> <!--$-->6 days 2 hours<!--/--></span>
              </div>
              <div data-slot="usage-item">
                <span data-slot="usage-label">Monthly Usage</span>
                <span data-slot="usage-value"><!--$-->50<!--/-->%</span>
                <span data-slot="reset-time"><!--$-->Resets in<!--/--> <!--$-->26 days 17 hours<!--/--></span>
              </div>
            </div>
            """#

        let snapshot = try OpenCodeGoUsageDecoder()
            .decode(
                Data(html.utf8),
                accountID: UUID(),
                fetchedAt: fetchedAt
            )

        #expect(
            snapshot.windows.map(\.id)
                == [
                    "opencode-go-rolling",
                    "opencode-go-weekly",
                    "opencode-go-monthly",
                ]
        )
        #expect(
            snapshot.windows.map(
                \.consumedFraction
            ) == [0.07, 0.10, 0.50]
        )
        #expect(
            snapshot.windows.map(\.resetAt)
                == [
                    fetchedAt.addingTimeInterval(
                        6_960
                    ),
                    fetchedAt.addingTimeInterval(
                        525_600
                    ),
                    fetchedAt.addingTimeInterval(
                        2_307_600
                    ),
                ]
        )
    }

    @Test
    func workspaceWithoutGoSubscriptionIsRejectedClearly() {
        let html = #"""
            <script>
            $R[1]={subscription:null,subscriptionPlan:null,monthlyUsage:null};
            </script>
            <button data-slot="subscribe-button">Subscribe to Go</button>
            """#

        #expect(
            throws:
                ProviderClientError
                .subscriptionRequired
        ) {
            _ = try OpenCodeGoUsageDecoder()
                .decode(
                    Data(html.utf8),
                    accountID: UUID(),
                    fetchedAt: Date()
                )
        }
    }

    @Test
    func pageWithoutUsageWindowsIsRejected() {
        #expect(
            throws:
                ProviderClientError
                .unsupportedResponse
        ) {
            _ = try OpenCodeGoUsageDecoder()
                .decode(
                    Data("<html></html>".utf8),
                    accountID: UUID(),
                    fetchedAt: Date()
                )
        }
    }
}
