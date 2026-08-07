import Foundation
import Testing
import UsageMeterClaudeWeb
import UsageMeterCore

@testable import UsageMeterUI

@MainActor
@Suite
struct ClaudeConnectionUsagePolicyTests {
    private let organizationID = UUID(
        uuidString: "10000000-0000-0000-0000-000000000001",
    )!
    private let teamOrganizationID = UUID(
        uuidString: "10000000-0000-0000-0000-000000000002",
    )!

    private static let zeroUsage =
        #"{"five_hour":{"utilization":0,"resets_at":null},"seven_day":{"utilization":0,"resets_at":null}}"#

    @Test
    func undecodableUsageFailsTheConnectionInsteadOfSavingIt() async throws {
        let model = try await makeModel(
            organizationsJSON: singleOrganizationJSON,
            usageBodies: [#"{"five_hour":null,"seven_day":null}"#],
        )

        await model.qualifyLogin(
            authenticatedCookies: [Self.sessionCookie],
        )

        #expect(
            model.phase
                == .failed(
                    "Claude returned a usage response this app does not understand.",
                ),
        )
    }

    @Test
    func transientUsageFailureStillQualifiesWithoutASnapshot() async throws {
        let model = try await makeModel(
            organizationsJSON: singleOrganizationJSON,
            usageResponses: [
                HTTPResponse(
                    data: Data(),
                    statusCode: 500,
                    headers: [:],
                ),
            ],
        )

        await model.qualifyLogin(
            authenticatedCookies: [Self.sessionCookie],
        )

        #expect(
            model.phase
                == .readyToSave(
                    organizationName: "Personal",
                    organizationCount: 1,
                ),
        )
    }

    @Test
    func consoleOrganizationsAreNeverSelected() async throws {
        let model = try await makeModel(
            organizationsJSON: """
            [
              {"uuid":"\(UUID().uuidString.lowercased())","name":"Console","capabilities":["api"]},
              {"uuid":"\(organizationID.uuidString.lowercased())","name":"Personal","capabilities":["chat","claude_max"]}
            ]
            """,
            usageBodies: [Self.zeroUsage],
        )

        await model.qualifyLogin(
            authenticatedCookies: [Self.sessionCookie],
        )

        #expect(
            model.phase
                == .readyToSave(
                    organizationName: "Personal",
                    organizationCount: 1,
                ),
        )
    }

    @Test
    func accountsWithOnlyConsoleOrganizationsCannotQualify() async throws {
        let model = try await makeModel(
            organizationsJSON: """
            [{"uuid":"\(UUID().uuidString.lowercased())","name":"Console","capabilities":["api"]}]
            """,
            usageBodies: [],
        )

        await model.qualifyLogin(
            authenticatedCookies: [Self.sessionCookie],
        )

        #expect(
            model.phase
                == .failed(
                    "Claude returned an organizations response this app does not understand.",
                ),
        )
    }

    @Test
    func multipleChatOrganizationsOfferAChoice() async throws {
        let connectedAccount = SubscriptionAccount(
            provider: .claude,
            displayName: "Existing Personal",
            displayOrder: 0,
            claudeProfileID: UUID(),
            claudeOrganizationID: organizationID,
        )
        let model = try await makeModel(
            organizationsJSON: multiOrganizationJSON,
            usageBodies: [],
            existingAccounts: [connectedAccount],
        )

        await model.qualifyLogin(
            authenticatedCookies: [Self.sessionCookie],
        )

        guard
            case let .choosingOrganizations(choices) = model.phase
        else {
            Issue.record("Expected a choosing phase, got \(model.phase)")
            return
        }
        #expect(choices.map(\.organization.name) == ["Personal", "Acme Team"])
        #expect(
            choices.map(\.connectedAccountName)
                == ["Existing Personal", nil],
        )
        #expect(choices.map(\.isSelected) == [false, true])
    }

    @Test
    func selectionCreatesOneAccountPerOrganizationSharingTheProfile() async throws {
        let (model, appModel) = try await makeModelReturningAppModel(
            organizationsJSON: multiOrganizationJSON,
            usageBodies: [Self.zeroUsage, Self.zeroUsage],
        )

        await model.qualifyLogin(
            authenticatedCookies: [Self.sessionCookie],
        )
        await model.confirmOrganizationSelection()

        guard
            case let .readyToSaveOrganizations(connections) = model.phase
        else {
            Issue.record("Expected save-ready phase, got \(model.phase)")
            return
        }
        #expect(
            connections.map(\.organizationName)
                == ["Personal", "Acme Team"],
        )
        #expect(connections.allSatisfy { $0.snapshot != nil })

        await model.saveSelectedOrganizations()

        #expect(model.phase == .complete)
        #expect(
            appModel.accounts.map(\.account.displayName)
                == ["Personal", "Acme Team"],
        )
        let profileIDs = Set(
            appModel.accounts.compactMap(\.account.claudeProfileID),
        )
        #expect(profileIDs.count == 1)
        #expect(
            appModel.accounts.map(\.account.claudeOrganizationID)
                == [organizationID, teamOrganizationID],
        )
    }

    @Test
    func decliningAnOrganizationOnlyConnectsTheSelectedOnes() async throws {
        let (model, appModel) = try await makeModelReturningAppModel(
            organizationsJSON: multiOrganizationJSON,
            usageBodies: [Self.zeroUsage],
        )

        await model.qualifyLogin(
            authenticatedCookies: [Self.sessionCookie],
        )
        model.toggleOrganization(id: organizationID)
        await model.confirmOrganizationSelection()
        await model.saveSelectedOrganizations()

        #expect(model.phase == .complete)
        #expect(
            appModel.accounts.map(\.account.claudeOrganizationID)
                == [teamOrganizationID],
        )
    }

    @Test
    func reconnectQualifiesAgainstTheStoredOrganization() async throws {
        let reconnecting = SubscriptionAccount(
            provider: .claude,
            displayName: "Team",
            displayOrder: 0,
            claudeProfileID: UUID(),
            claudeOrganizationID: teamOrganizationID,
        )
        let model = try await makeModel(
            organizationsJSON: multiOrganizationJSON,
            usageBodies: [Self.zeroUsage],
            existingAccounts: [reconnecting],
            reconnectingAccount: reconnecting,
        )

        await model.qualifyLogin(
            authenticatedCookies: [Self.sessionCookie],
        )

        #expect(
            model.phase
                == .readyToSave(
                    organizationName: "Acme Team",
                    organizationCount: 2,
                ),
        )
    }

    @Test
    func reconnectFailsWhenTheLoginLacksTheStoredOrganization() async throws {
        let reconnecting = SubscriptionAccount(
            provider: .claude,
            displayName: "Team",
            displayOrder: 0,
            claudeProfileID: UUID(),
            claudeOrganizationID: UUID(),
        )
        let model = try await makeModel(
            organizationsJSON: singleOrganizationJSON,
            usageBodies: [],
            existingAccounts: [reconnecting],
            reconnectingAccount: reconnecting,
        )

        await model.qualifyLogin(
            authenticatedCookies: [Self.sessionCookie],
        )

        #expect(
            model.phase
                == .failed(
                    "This Claude login does not belong to the organization Team was connected to.",
                ),
        )
    }


    @Test
    func reconnectMismatchRecoversWithAFreshSignIn() async throws {
        let reconnecting = SubscriptionAccount(
            provider: .claude,
            displayName: "Team",
            displayOrder: 0,
            claudeProfileID: UUID(),
            claudeOrganizationID: UUID(),
        )
        var removedProfileIDs: [UUID] = []
        let (model, _) = try await makeModelReturningAppModel(
            organizationsJSON: singleOrganizationJSON,
            usageBodies: [],
            existingAccounts: [reconnecting],
            reconnectingAccount: reconnecting,
            removeProfile: { removedProfileIDs.append($0) },
        )

        await model.qualifyLogin(
            authenticatedCookies: [Self.sessionCookie],
        )
        guard case .failed = model.phase else {
            Issue.record("Expected failure, got \(model.phase)")
            return
        }
        #expect(removedProfileIDs.count == 1)

        await model.retry()

        #expect(model.phase == .signingIn)
    }

    @Test
    func reconnectMismatchAbandonsTheProvisionalProfileEvenWhenCleanupFails() async throws {
        let reconnecting = SubscriptionAccount(
            provider: .claude,
            displayName: "Team",
            displayOrder: 0,
            claudeProfileID: UUID(),
            claudeOrganizationID: UUID(),
        )
        let (model, _) = try await makeModelReturningAppModel(
            organizationsJSON: singleOrganizationJSON,
            usageBodies: [],
            existingAccounts: [reconnecting],
            reconnectingAccount: reconnecting,
            removeProfile: { _ in
                throw ProviderClientError.temporaryFailure
            },
        )
        let provisionalProfileID = model.profileID

        await model.qualifyLogin(
            authenticatedCookies: [Self.sessionCookie],
        )

        guard case .failed = model.phase else {
            Issue.record("Expected failure, got \(model.phase)")
            return
        }
        #expect(model.profileID != provisionalProfileID)
    }

    private var singleOrganizationJSON: String {
        #"[{"uuid":"\#(organizationID.uuidString.lowercased())","name":"Personal","capabilities":["chat","claude_max"]}]"#
    }

    private var multiOrganizationJSON: String {
        """
        [
          {"uuid":"\(organizationID.uuidString.lowercased())","name":"Personal","capabilities":["chat","claude_max"]},
          {"uuid":"\(teamOrganizationID.uuidString.lowercased())","name":"Acme Team","capabilities":["chat","claude_team"]}
        ]
        """
    }

    private func makeModel(
        organizationsJSON: String,
        usageBodies: [String] = [],
        usageResponses: [HTTPResponse] = [],
        existingAccounts: [SubscriptionAccount] = [],
        reconnectingAccount: SubscriptionAccount? = nil,
    ) async throws -> ClaudeConnectionModel {
        try await makeModelReturningAppModel(
            organizationsJSON: organizationsJSON,
            usageBodies: usageBodies,
            usageResponses: usageResponses,
            existingAccounts: existingAccounts,
            reconnectingAccount: reconnectingAccount,
        ).model
    }

    private func makeModelReturningAppModel(
        organizationsJSON: String,
        usageBodies: [String] = [],
        usageResponses: [HTTPResponse] = [],
        existingAccounts: [SubscriptionAccount] = [],
        reconnectingAccount: SubscriptionAccount? = nil,
        removeProfile: @escaping @MainActor @Sendable (UUID) async throws
            -> Void = { _ in },
    ) async throws -> (
        model: ClaudeConnectionModel,
        appModel: AppModel
    ) {
        let appModel = AppModel(
            stateStore: TestAppStateStore(
                state: PersistedAppState(
                    accounts: existingAccounts,
                    snapshots: [:],
                ),
            ),
            credentialStore: TestCredentialStore(),
            adapters: [TestClaudeProfileRemover()],
            now: { Date(timeIntervalSince1970: 2_000_000_000) },
        )
        await appModel.start()

        var responses = [
            HTTPResponse(
                data: Data(organizationsJSON.utf8),
                statusCode: 200,
                headers: [:],
            ),
        ]
        responses += usageBodies.map {
            HTTPResponse(
                data: Data($0.utf8),
                statusCode: 200,
                headers: [:],
            )
        }
        responses += usageResponses

        let model = ClaudeConnectionModel(
            appModel: appModel,
            reconnectingAccount: reconnectingAccount,
            removeProfile: removeProfile,
            usageClient: ClaudeWebUsageClient(
                transport: SequencedHTTPTransport(
                    responses: responses,
                ),
                cookieSource: NoCookiesSource(),
            ),
        )
        return (model, appModel)
    }

    private static let sessionCookie = HTTPCookie(
        properties: [
            .domain: ".claude.ai",
            .path: "/",
            .name: "sessionKey",
            .value: "session",
            .secure: "TRUE",
        ],
    )!
}

@MainActor
private final class NoCookiesSource:
    ClaudeWebCookieSource
{
    func cookies(
        for _: URL,
        profileID _: UUID,
    ) async -> [HTTPCookie] {
        []
    }
}

private actor SequencedHTTPTransport: HTTPTransport {
    private var responses: [HTTPResponse]

    init(responses: [HTTPResponse]) {
        self.responses = responses
    }

    func send(_: URLRequest) async throws -> HTTPResponse {
        guard !responses.isEmpty else {
            throw HTTPTransportError.nonHTTPResponse
        }
        return responses.removeFirst()
    }
}
