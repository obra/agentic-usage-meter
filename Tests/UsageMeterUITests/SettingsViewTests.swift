import Foundation
import Testing

@testable import UsageMeterUI

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
