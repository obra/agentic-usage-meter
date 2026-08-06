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

    @Test
    func undecodableUsageFailsTheConnectionInsteadOfSavingIt() async {
        let client = makeClient(
            usageResponse: HTTPResponse(
                data: Data(
                    #"{"five_hour":null,"seven_day":null}"#.utf8,
                ),
                statusCode: 200,
                headers: [:],
            ),
        )

        await #expect(throws: ProviderClientError.unsupportedResponse) {
            _ = try await ClaudeConnectionModel.qualifyConnection(
                usageClient: client,
                accountID: UUID(),
                profileID: UUID(),
                retrier: ClaudeFreshSessionRetrier(
                    maximumAttempts: 1,
                    sleep: { _ in },
                ),
            )
        }
    }

    @Test
    func transientUsageFailureStillQualifiesWithoutASnapshot() async throws {
        let client = makeClient(
            usageResponse: HTTPResponse(
                data: Data(),
                statusCode: 500,
                headers: [:],
            ),
        )
        var sawUsageStage = false

        let connection = try await ClaudeConnectionModel.qualifyConnection(
            usageClient: client,
            accountID: UUID(),
            profileID: UUID(),
            retrier: ClaudeFreshSessionRetrier(
                maximumAttempts: 1,
                sleep: { _ in },
            ),
            onUsageStage: {
                sawUsageStage = true
            },
        )

        #expect(sawUsageStage)
        #expect(connection.snapshot == nil)
        #expect(connection.organizationID == organizationID)
        #expect(connection.organizationName == "Personal")
        #expect(connection.organizationCount == 1)
    }

    @Test
    func consoleOrganizationsAreNeverSelected() async throws {
        let usage = HTTPResponse(
            data: Data(
                #"{"five_hour":{"utilization":0,"resets_at":null},"seven_day":{"utilization":0,"resets_at":null}}"#
                    .utf8,
            ),
            statusCode: 200,
            headers: [:],
        )
        let client = makeClient(
            usageResponse: usage,
            organizationsJSON: """
            [
              {"uuid":"\(UUID().uuidString.lowercased())","name":"Console","capabilities":["api"]},
              {"uuid":"\(organizationID.uuidString.lowercased())","name":"Personal","capabilities":["chat","claude_max"]}
            ]
            """,
        )

        let connection = try await ClaudeConnectionModel.qualifyConnection(
            usageClient: client,
            accountID: UUID(),
            profileID: UUID(),
            retrier: ClaudeFreshSessionRetrier(
                maximumAttempts: 1,
                sleep: { _ in },
            ),
        )

        #expect(connection.organizationID == organizationID)
        #expect(connection.organizationName == "Personal")
        #expect(connection.organizationCount == 1)
    }

    @Test
    func accountsWithOnlyConsoleOrganizationsCannotQualify() async {
        let client = makeClient(
            usageResponse: HTTPResponse(
                data: Data(),
                statusCode: 200,
                headers: [:],
            ),
            organizationsJSON: """
            [{"uuid":"\(UUID().uuidString.lowercased())","name":"Console","capabilities":["api"]}]
            """,
        )

        await #expect(throws: ProviderClientError.unsupportedResponse) {
            _ = try await ClaudeConnectionModel.qualifyConnection(
                usageClient: client,
                accountID: UUID(),
                profileID: UUID(),
                retrier: ClaudeFreshSessionRetrier(
                    maximumAttempts: 1,
                    sleep: { _ in },
                ),
            )
        }
    }

    private func makeClient(
        usageResponse: HTTPResponse,
        organizationsJSON: String? = nil,
    ) -> ClaudeWebUsageClient {
        let organizations = HTTPResponse(
            data: Data(
                (
                    organizationsJSON
                        ?? #"[{"uuid":"\#(organizationID.uuidString.lowercased())","name":"Personal","capabilities":["chat","claude_max"]}]"#
                ).utf8,
            ),
            statusCode: 200,
            headers: [:],
        )
        return ClaudeWebUsageClient(
            transport: SequencedHTTPTransport(
                responses: [organizations, usageResponse],
            ),
            cookieSource: SessionOnlyCookieSource(),
        )
    }
}

@MainActor
private final class SessionOnlyCookieSource:
    ClaudeWebCookieSource
{
    func cookies(
        for _: URL,
        profileID _: UUID,
    ) async -> [HTTPCookie] {
        [
            HTTPCookie(
                properties: [
                    .domain: ".claude.ai",
                    .path: "/",
                    .name: "sessionKey",
                    .value: "session",
                    .secure: "TRUE",
                ],
            )!,
        ]
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
