import Foundation
import Testing
import UsageMeterCore

@testable import UsageMeterUI

@Test
func settingsHeaderMarksOnlySampleData() {
    #expect(
        SettingsHeaderPresentation(
            isSampleData: true,
        ).sampleDataLabel == "SAMPLE DATA",
    )
    #expect(
        SettingsHeaderPresentation(
            isSampleData: false,
        ).sampleDataLabel == nil,
    )
}

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
func providerRequestIsAvailableOnlyWhenAddingAnAccount() {
    let account = SubscriptionAccount(
        provider: .codex,
        displayName: "Work",
        displayOrder: 0,
    )

    #expect(
        AccountSheetRoute.add.providerRequestURL
            == URL(
                string:
                    "https://github.com/obra/agentic-usage-meter/issues/new",
            ),
    )
    #expect(
        AccountSheetRoute.reconnect(account).providerRequestURL == nil,
    )
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
func addAccountStartsOnTheProviderChoiceStep() {
    var wizard = AccountConnectionWizard(route: .add)

    #expect(wizard.step == .chooseProvider)
    #expect(!wizard.canGoBack)

    wizard.choose(.kimi)

    #expect(wizard.step == .connect(.kimi))
    #expect(wizard.canGoBack)
}

@Test
func goingBackReturnsToTheProviderChoiceStep() {
    var wizard = AccountConnectionWizard(route: .add)

    wizard.choose(.claude)
    wizard.goBack()

    #expect(wizard.step == .chooseProvider)
}

@Test
func reconnectSkipsProviderChoiceAndStaysLocked() {
    let account = SubscriptionAccount(
        provider: .codex,
        displayName: "Work",
        displayOrder: 0,
    )
    var wizard = AccountConnectionWizard(
        route: .reconnect(account),
    )

    #expect(wizard.step == .connect(.codex))
    #expect(!wizard.canGoBack)

    wizard.choose(.claude)
    wizard.goBack()

    #expect(wizard.step == .connect(.codex))
}

@Test
func providerChoicesMapSubscriptionsToTheirOwnLabels() {
    #expect(
        ProviderPresentation(.claude).title
            == "Claude",
    )
    #expect(
        ProviderPresentation(.codex).title
            == "Codex",
    )
    #expect(
        ProviderPresentation(.kimi).title
            == "Kimi",
    )
}

@Test
func claudeEmbeddedBrowserGuidanceRequiresEmailSignIn() {
    let guidance =
        ClaudeConnectionGuidance.embeddedBrowser

    #expect(!guidance.allowsGoogleSignIn)
    #expect(
        guidance.recommendedSignInMethod == .email,
    )
}

@Test
func movingAccountsUsesTheCompleteProviderLocalOrder() {
    let first = UUID()
    let second = UUID()
    let third = UUID()

    #expect(
        AccountOrder.moving(
            [first, second, third],
            fromOffsets: IndexSet(integer: 0),
            toOffset: 3,
        ) == [second, third, first],
    )
}

@Test
func movingAnEmptySelectionKeepsTheExistingOrder() {
    let ids = [UUID(), UUID()]

    #expect(
        AccountOrder.moving(
            ids,
            fromOffsets: IndexSet(),
            toOffset: 1,
        ) == ids,
    )
}

@Test
func boundaryMoveKeepsTheProviderOrderUnchanged() {
    let first = UUID()
    let second = UUID()

    #expect(
        AccountOrder.moving(
            [first, second],
            accountID: first,
            by: -1,
        ) == [first, second],
    )
}

@Test
func moveCommandMovesOneAccountWithinItsProvider() {
    let first = UUID()
    let second = UUID()

    #expect(
        AccountOrder.moving(
            [first, second],
            accountID: second,
            by: -1,
        ) == [second, first],
    )
}

@Test
func onlyAuthenticationFailuresShowProminentReconnect() {
    #expect(
        AccountRowPresentation.showsReconnectAction(
            for: .authenticationRequired,
        ),
    )
    #expect(
        !AccountRowPresentation.showsReconnectAction(
            for: .temporarilyUnavailable,
        ),
    )
    #expect(
        !AccountRowPresentation.showsReconnectAction(
            for: nil,
        ),
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

@Test
func apiKeyFormTrimsNameButPreservesSecretBytes() {
    let form = APIKeyConnectionForm(
        displayName: "  MiniMax Work  ",
        apiKey: " key-with-spaces "
    )

    #expect(form.validatedDisplayName == "MiniMax Work")
    #expect(form.apiKey == " key-with-spaces ")
    #expect(form.canConnect)
}

@Test
func apiKeyFormRequiresANameAndNonblankSecret() {
    #expect(
        !APIKeyConnectionForm(
            displayName: " ",
            apiKey: "key"
        ).canConnect
    )
    #expect(
        !APIKeyConnectionForm(
            displayName: "MiniMax",
            apiKey: "\n\t"
        ).canConnect
    )
}

@Test
func apiKeyConnectionCopyMatchesTheSelectedProvider() {
    let miniMax = APIKeyConnectionPresentation(
        provider: .minimax
    )
    let factory = APIKeyConnectionPresentation(
        provider: .factory
    )

    #expect(miniMax.sectionTitle == "MiniMax Token Plan")
    #expect(miniMax.secretLabel == "MiniMax API key")
    #expect(factory.sectionTitle == "Factory API key")
    #expect(factory.secretLabel == "Factory API key")
    #expect(
        factory.guidance.contains(
            "app.factory.ai/settings/api-keys"
        )
    )
    #expect(
        factory.failureMessage
            == "Factory account could not be connected."
    )
}
