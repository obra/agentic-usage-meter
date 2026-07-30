import Foundation
import Testing
import UsageMeterCore

@testable import UsageMeterUI

@Test
func reconnectRouteLocksTheExistingProvider() {
    let account = SubscriptionAccount(
        provider: .codex,
        displayName: "Work",
        displayOrder: 0,
    )
    let route = AccountSheetRoute.reconnect(account)

    #expect(route.provider == .codex)
    #expect(route.isProviderLocked)
    #expect(route.reconnectingAccount?.id == account.id)
}

@Test
func addRouteStartsWithClaudeAndAllowsProviderChanges() {
    let route = AccountSheetRoute.add

    #expect(route.provider == .claude)
    #expect(!route.isProviderLocked)
    #expect(route.reconnectingAccount == nil)
}

@Test
func accountNameEditRejectsBlankDraftWithoutDiscardingIt() {
    let edit = AccountNameEdit(
        originalName: "Work",
        draftName: "   ",
    )

    #expect(edit.saveDecision == .invalid)
    #expect(edit.draftName == "   ")
}

@Test
func accountNameEditCanCancelBackToTheOriginalName() {
    var edit = AccountNameEdit(
        originalName: "Work",
        draftName: "Personal",
    )

    edit.cancel()

    #expect(edit.draftName == "Work")
}

@Test
func completingAccountConnectionStartsFreshProviderModels() {
    let firstAttemptID = UUID(
        uuidString: "11111111-1111-1111-1111-111111111111",
    )!
    let secondAttemptID = UUID(
        uuidString: "22222222-2222-2222-2222-222222222222",
    )!
    var form = AccountConnectionFormState(
        attemptID: firstAttemptID,
    )
    let firstViewID = form.viewID(
        reconnectingAccountID: nil,
    )

    form.accountDidConnect(nextAttemptID: secondAttemptID)

    #expect(
        form.viewID(reconnectingAccountID: nil)
            != firstViewID,
    )
}
