import Foundation
import Testing
@testable import UsageMeterCore

@Suite
struct ClaudeUsageClientTests {
    @Test
    func requestAndResponseMapToNormalizedUsageWindows() async throws {
        let responseData = try fixture(named: "claude-usage")
        let transport = RecordingHTTPTransport(
            response: HTTPResponse(
                data: responseData,
                statusCode: 200,
                headers: [:]
            )
        )
        let client = ClaudeUsageClient(transport: transport)
        let accountID = UUID()
        let fetchedAt = Date(timeIntervalSince1970: 2_000_000_000)

        let snapshot = try await client.fetchUsage(
            accountID: accountID,
            credential: .claude(token: "setup-token"),
            now: fetchedAt
        )

        #expect(snapshot.accountID == accountID)
        #expect(snapshot.fetchedAt == fetchedAt)
        #expect(snapshot.windows.count == 2)
        #expect(snapshot.windows[0].kind == .short)
        #expect(snapshot.windows[0].duration == 18_000)
        #expect(snapshot.windows[0].consumedFraction == 0.81)
        #expect(
            snapshot.windows[0].resetAt
                == Date(timeIntervalSince1970: 1_785_356_580)
        )
        #expect(snapshot.windows[1].kind == .weekly)
        #expect(snapshot.windows[1].duration == 604_800)
        #expect(snapshot.windows[1].consumedFraction == 0.66)
        #expect(
            snapshot.windows[1].resetAt
                == Date(timeIntervalSince1970: 1_785_793_200)
        )

        let request = try #require(await transport.lastRequest)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer setup-token")
        #expect(
            request.value(forHTTPHeaderField: "anthropic-beta")
                == "oauth-2025-04-20"
        )
    }

    @Test
    func missingRequiredWindowIsRejected() async throws {
        let transport = RecordingHTTPTransport(
            response: HTTPResponse(
                data: Data(
                    #"{"five_hour":{"utilization":20,"resets_at":"2026-07-29T20:23:00Z"}}"#.utf8
                ),
                statusCode: 200,
                headers: [:]
            )
        )
        let client = ClaudeUsageClient(transport: transport)

        await #expect(throws: ProviderClientError.unsupportedResponse) {
            _ = try await client.fetchUsage(
                accountID: UUID(),
                credential: .claude(token: "setup-token"),
                now: Date(timeIntervalSince1970: 2_000_000_000)
            )
        }
    }

    @Test
    func utilizationOutsidePercentRangeIsRejected() async throws {
        let transport = RecordingHTTPTransport(
            response: HTTPResponse(
                data: Data(
                    """
                    {
                      "five_hour": {
                        "utilization": 101,
                        "resets_at": "2026-07-29T20:23:00Z"
                      },
                      "seven_day": {
                        "utilization": 20,
                        "resets_at": "2026-08-03T21:40:00Z"
                      }
                    }
                    """.utf8
                ),
                statusCode: 200,
                headers: [:]
            )
        )
        let client = ClaudeUsageClient(transport: transport)

        await #expect(throws: ProviderClientError.unsupportedResponse) {
            _ = try await client.fetchUsage(
                accountID: UUID(),
                credential: .claude(token: "setup-token"),
                now: Date(timeIntervalSince1970: 2_000_000_000)
            )
        }
    }

    @Test
    func statusCodesMapToProviderFailures() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let cases: [(Int, [String: String], ProviderClientError)] = [
            (401, [:], .reauthenticationRequired),
            (403, [:], .reauthenticationRequired),
            (429, ["Retry-After": "900"], .retryAfter(now.addingTimeInterval(900))),
            (500, [:], .temporaryFailure)
        ]

        for (statusCode, headers, expectedError) in cases {
            let transport = RecordingHTTPTransport(
                response: HTTPResponse(
                    data: Data(),
                    statusCode: statusCode,
                    headers: headers
                )
            )
            let client = ClaudeUsageClient(transport: transport)

            await #expect(throws: expectedError) {
                _ = try await client.fetchUsage(
                    accountID: UUID(),
                    credential: .claude(token: "setup-token"),
                    now: now
                )
            }
        }
    }

    @Test
    func nonClaudeCredentialIsRejectedWithoutNetworkTraffic() async {
        let transport = RecordingHTTPTransport(
            response: HTTPResponse(data: Data(), statusCode: 200, headers: [:])
        )
        let client = ClaudeUsageClient(transport: transport)

        await #expect(throws: ProviderClientError.credentialMismatch) {
            _ = try await client.fetchUsage(
                accountID: UUID(),
                credential: .kimi(OAuthCredential(accessToken: "wrong-provider")),
                now: Date(timeIntervalSince1970: 2_000_000_000)
            )
        }
        #expect(await transport.lastRequest == nil)
    }
}

private actor RecordingHTTPTransport: HTTPTransport {
    private let response: HTTPResponse
    private(set) var lastRequest: URLRequest?

    init(response: HTTPResponse) {
        self.response = response
    }

    func send(_ request: URLRequest) -> HTTPResponse {
        lastRequest = request
        return response
    }
}

private func fixture(named name: String) throws -> Data {
    let url = try #require(
        Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures"
        )
    )
    return try Data(contentsOf: url)
}
