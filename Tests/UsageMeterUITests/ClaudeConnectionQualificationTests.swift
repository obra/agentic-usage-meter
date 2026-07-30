import Foundation
import Testing
import UsageMeterCore

@testable import UsageMeterUI

@MainActor
@Suite
struct ClaudeConnectionQualificationTests {
    @Test
    func freshSessionAuthenticationIsRetriedBeforeFailing() async throws {
        var attempts = 0
        let retrier = ClaudeFreshSessionRetrier(
            maximumAttempts: 4,
            sleep: { _ in },
        )

        let value = try await retrier.run {
            attempts += 1
            if attempts < 3 {
                throw ProviderClientError
                    .reauthenticationRequired
            }
            return "qualified"
        }

        #expect(value == "qualified")
        #expect(attempts == 3)
    }

    @Test
    func responseShapeFailureNamesTheUsageStage() {
        let message = ClaudeConnectionFailureDescription
            .message(
                for: ProviderClientError
                    .unsupportedResponse,
                stage: .usage,
            )

        #expect(
            message
                == "Claude returned a usage response this app does not understand.",
        )
    }

    @Test
    func exhaustedAuthenticationRetriesExplainTheFailure() {
        let message = ClaudeConnectionFailureDescription
            .message(
                for: ProviderClientError
                    .reauthenticationRequired,
                stage: .organizations,
            )

        #expect(
            message
                == "Claude rejected the signed-in session while loading organizations, even after retrying.",
        )
    }

    @Test
    func failedValidationCanBeRetriedWithoutAnotherLogin() async {
        let reference = Date(
            timeIntervalSince1970: 2_000_000_000,
        )
        let accountID = UUID()
        let organizationID = UUID()
        let snapshot = UsageSnapshot(
            accountID: accountID,
            fetchedAt: reference,
            windows: [],
        )
        let appModel = AppModel(
            stateStore: TestAppStateStore(state: .empty),
            credentialStore: TestCredentialStore(),
            adapters: [TestClaudeProfileRemover()],
            now: { reference },
        )
        await appModel.start()
        var attempts = 0
        let connection = ClaudeConnectionModel(
            appModel: appModel,
            accountID: accountID,
            qualify: {
                attempts += 1
                if attempts == 1 {
                    throw ProviderClientError
                        .temporaryFailure
                }
                return ClaudeQualifiedConnection(
                    organizationID: organizationID,
                    organizationName: "Work",
                    organizationCount: 1,
                    snapshot: snapshot,
                )
            },
            removeProfile: { _ in },
        )

        await connection.start()
        await connection.retry()

        #expect(attempts == 2)
        #expect(
            connection.phase
                == .readyToSave(
                    organizationName: "Work",
                    organizationCount: 1,
                ),
        )
    }

    @Test
    func authenticatedProfileCanBeSavedWithoutInitialUsage() async throws {
        let accountID = UUID()
        let organizationID = UUID()
        let appModel = AppModel(
            stateStore: TestAppStateStore(state: .empty),
            credentialStore: TestCredentialStore(),
            adapters: [TestClaudeProfileRemover()]
        )
        await appModel.start()
        let connection = ClaudeConnectionModel(
            appModel: appModel,
            accountID: accountID,
            qualify: {
                ClaudeQualifiedConnection(
                    organizationID: organizationID,
                    organizationName: "Work",
                    organizationCount: 1,
                    snapshot: nil
                )
            },
            removeProfile: { _ in }
        )

        await connection.start()
        try await connection.save(displayName: "Work Claude")

        #expect(connection.phase == .complete)
        #expect(appModel.accounts.count == 1)
        #expect(appModel.accounts[0].snapshot == nil)
        #expect(appModel.accounts[0].error == .temporarilyUnavailable)
    }
}
