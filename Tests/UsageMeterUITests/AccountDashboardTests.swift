import Foundation
import Testing
import UsageMeterCore

@testable import UsageMeterUI

@Test
func embeddedDashboardUsesTheAccountAsItsProfileID() throws {
    let account = SubscriptionAccount(
        id: UUID(
            uuidString: "22222222-2222-2222-2222-222222222222"
        )!,
        provider: .minimax,
        displayName: "MiniMax",
        displayOrder: 0
    )
    let definition = try #require(
        ProviderCatalog.live.definition(for: .minimax)
    )

    let route = AccountDashboardRoute(
        account: account,
        strategy: definition.dashboardStrategy
    )

    #expect(route.accountID == account.id)
    #expect(route.webProfileID == account.id)
}

@Test
func claudeDashboardReusesTheAuthenticatedWebProfile() throws {
    let accountID = UUID()
    let profileID = UUID()
    let account = SubscriptionAccount(
        id: accountID,
        provider: .claude,
        displayName: "Claude",
        displayOrder: 0,
        claudeProfileID: profileID,
        claudeOrganizationID: UUID()
    )
    let definition = try #require(
        ProviderCatalog.live.definition(for: .claude)
    )

    let route = AccountDashboardRoute(
        account: account,
        strategy: definition.dashboardStrategy
    )

    #expect(route.accountID == accountID)
    #expect(route.webProfileID == profileID)
}

@Test
func accountRowBackgroundOpensDashboardWithoutStealingControls() {
    #expect(
        AccountRowAction.resolved(
            clickedName: false,
            explicitControl: nil
        ) == .openDashboard
    )
    #expect(
        AccountRowAction.resolved(
            clickedName: true,
            explicitControl: nil
        ) == .rename
    )
    #expect(
        AccountRowAction.resolved(
            clickedName: false,
            explicitControl: .refresh
        ) == .refresh
    )
    #expect(
        AccountRowAction.resolved(
            clickedName: true,
            explicitControl: .reconnect
        ) == .reconnect
    )
}
