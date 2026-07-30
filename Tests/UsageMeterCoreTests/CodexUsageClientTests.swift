import Foundation
import Testing
@testable import UsageMeterCore

@Suite
struct CodexUsageClientTests {
    @Test
    func requestAndResponseMapWindowsByDuration() async throws {
        let responseData = try usageFixture(named: "codex-usage")
        let transport = CodexRecordingHTTPTransport(
            response: HTTPResponse(
                data: responseData,
                statusCode: 200,
                headers: [:]
            )
        )
        let client = CodexUsageClient(transport: transport)
        let accountID = UUID()
        let fetchedAt = Date(timeIntervalSince1970: 2_000_000_000)

        let snapshot = try await client.fetchUsage(
            accountID: accountID,
            credential: .codex(
                OAuthCredential(
                    accessToken: "access-token",
                    accountID: "chatgpt-account"
                )
            ),
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
                == Date(timeIntervalSince1970: 2_000_010_000)
        )
        #expect(snapshot.windows[1].kind == .weekly)
        #expect(snapshot.windows[1].duration == 604_800)
        #expect(snapshot.windows[1].consumedFraction == 0.66)
        #expect(
            snapshot.windows[1].resetAt
                == Date(timeIntervalSince1970: 2_000_020_000)
        )

        let request = try #require(await transport.lastRequest)
        #expect(request.httpMethod == "GET")
        #expect(
            request.url?.absoluteString
                == "https://chatgpt.com/backend-api/wham/usage"
        )
        #expect(
            request.value(forHTTPHeaderField: "Authorization")
                == "Bearer access-token"
        )
        #expect(
            request.value(forHTTPHeaderField: "ChatGPT-Account-Id")
                == "chatgpt-account"
        )
    }

    @Test
    func acceptsAvailableSupportedWindowWhenProviderOmitsTheOther() async throws {
        let response = Data(
            """
            {
              "rate_limit": {
                "allowed": true,
                "limit_reached": false,
                "primary_window": {
                  "used_percent": 25,
                  "limit_window_seconds": 604800,
                  "reset_after_seconds": 100,
                  "reset_at": 2000020000
                },
                "secondary_window": null
              }
            }
            """.utf8
        )
        let client = CodexUsageClient(
            transport: CodexRecordingHTTPTransport(
                response: HTTPResponse(
                    data: response,
                    statusCode: 200,
                    headers: [:]
                )
            )
        )

        let snapshot = try await client.fetchUsage(
            accountID: UUID(),
            credential: .codex(
                OAuthCredential(
                    accessToken: "access-token",
                    accountID: "account"
                )
            ),
            now: Date(timeIntervalSince1970: 2_000_000_000)
        )

        #expect(snapshot.windows.map(\.kind) == [.weekly])
    }

    @Test
    func invalidWindowValuesAreRejected() async {
        let response = Data(
            """
            {
              "rate_limit": {
                "allowed": true,
                "limit_reached": false,
                "primary_window": {
                  "used_percent": 101,
                  "limit_window_seconds": 18000,
                  "reset_after_seconds": 100,
                  "reset_at": 2000020000
                }
              }
            }
            """.utf8
        )
        let client = CodexUsageClient(
            transport: CodexRecordingHTTPTransport(
                response: HTTPResponse(
                    data: response,
                    statusCode: 200,
                    headers: [:]
                )
            )
        )

        await #expect(throws: ProviderClientError.unsupportedResponse) {
            _ = try await client.fetchUsage(
                accountID: UUID(),
                credential: .codex(
                    OAuthCredential(
                        accessToken: "access-token",
                        accountID: "account"
                    )
                ),
                now: Date()
            )
        }
    }

    @Test
    func credentialMustBeCodexAndIncludeTokenAndAccount() async {
        let transport = CodexRecordingHTTPTransport(
            response: HTTPResponse(data: Data(), statusCode: 200, headers: [:])
        )
        let client = CodexUsageClient(transport: transport)
        let invalidCredentials: [ProviderCredential] = [
            .kimi(OAuthCredential(accessToken: "wrong-provider")),
            .codex(OAuthCredential(accessToken: "", accountID: "account")),
            .codex(OAuthCredential(accessToken: "token", accountID: nil)),
            .codex(OAuthCredential(accessToken: "token", accountID: ""))
        ]

        for credential in invalidCredentials {
            await #expect(throws: ProviderClientError.credentialMismatch) {
                _ = try await client.fetchUsage(
                    accountID: UUID(),
                    credential: credential,
                    now: Date()
                )
            }
        }

        #expect(await transport.lastRequest == nil)
    }

    @Test
    func statusCodesMapToProviderFailures() async {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let cases: [(Int, [String: String], ProviderClientError)] = [
            (401, [:], .reauthenticationRequired),
            (403, [:], .reauthenticationRequired),
            (
                429,
                ["Retry-After": "600"],
                .retryAfter(now.addingTimeInterval(600))
            ),
            (500, [:], .temporaryFailure)
        ]

        for (statusCode, headers, expectedError) in cases {
            let client = CodexUsageClient(
                transport: CodexRecordingHTTPTransport(
                    response: HTTPResponse(
                        data: Data(),
                        statusCode: statusCode,
                        headers: headers
                    )
                )
            )

            await #expect(throws: expectedError) {
                _ = try await client.fetchUsage(
                    accountID: UUID(),
                    credential: .codex(
                        OAuthCredential(
                            accessToken: "token",
                            accountID: "account"
                        )
                    ),
                    now: now
                )
            }
        }
    }
}

private actor CodexRecordingHTTPTransport: HTTPTransport {
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
