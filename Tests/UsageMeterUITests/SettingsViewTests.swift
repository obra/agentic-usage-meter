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
func completingConnectionDismissesSheetAndResetsProviderModels() {
    let firstAttemptID = UUID(
        uuidString: "11111111-1111-1111-1111-111111111111",
    )!
    let secondAttemptID = UUID(
        uuidString: "22222222-2222-2222-2222-222222222222",
    )!
    var presentation = AccountManagementPresentation(
        connectionForm: AccountConnectionFormState(
            attemptID: firstAttemptID,
        ),
    )
    presentation.presentAddAccount()
    let firstViewID = presentation.connectionViewID

    presentation.connectionDidComplete(
        nextAttemptID: secondAttemptID,
    )

    #expect(presentation.sheetRoute == nil)
    #expect(presentation.connectionViewID != firstViewID)
}

@Test
func reconnectPresentationCarriesTheSelectedAccount() {
    let account = SubscriptionAccount(
        provider: .kimi,
        displayName: "Kimi",
        displayOrder: 0,
    )
    var presentation = AccountManagementPresentation()

    presentation.presentReconnect(account)

    #expect(
        presentation.sheetRoute?.reconnectingAccount?.id
            == account.id,
    )
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
