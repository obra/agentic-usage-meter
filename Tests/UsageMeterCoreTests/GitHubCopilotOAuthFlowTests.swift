import Foundation
import Testing

@testable import UsageMeterCore

@Suite
struct GitHubCopilotOAuthFlowTests {
    @Test
    func deviceLoginReturnsTheApprovedGitHubIdentity()
        async throws
    {
        let transport = CopilotOAuthRecordingTransport(
            responses: [
                jsonResponse(
                    [
                        "device_code": "device-code",
                        "user_code": "ABCD-EFGH",
                        "verification_uri":
                            "https://github.com/login/device",
                        "expires_in": 600,
                        "interval": 5,
                    ],
                    status: 200
                ),
                jsonResponse(
                    ["error": "authorization_pending"],
                    status: 200
                ),
                jsonResponse(
                    [
                        "access_token": "github-token",
                        "token_type": "bearer",
                        "scope": "",
                    ],
                    status: 200
                ),
                jsonResponse(
                    [
                        "login": "octocat",
                        "id": 42,
                    ],
                    status: 200
                ),
            ]
        )
        let browser = CopilotOAuthRecordingBrowser(
            result: true
        )
        let sleeper = CopilotOAuthSleepRecorder()
        let promptRecorder =
            CopilotOAuthPromptRecorder()
        let now = Date(
            timeIntervalSince1970: 2_000_000_000
        )
        let flow = GitHubCopilotOAuthFlow(
            transport: transport,
            browser: browser,
            now: { now },
            sleep: { seconds in
                await sleeper.record(seconds)
            }
        )

        let result = try await flow.authenticate {
            prompt in
            await promptRecorder.record(prompt)
        }

        #expect(
            result.credential
                == GitHubCopilotCredential(
                    accessToken: "github-token",
                    userID: "42",
                    login: "octocat"
                )
        )
        #expect(
            await browser.lastURL?.absoluteString
                == "https://github.com/login/device"
        )
        #expect(await sleeper.seconds == [5])
        #expect(await transport.requests.count == 4)
        #expect(
            await promptRecorder.prompt
                == GitHubCopilotAuthorizationPrompt(
                    verificationURL: URL(
                        string:
                            "https://github.com/login/device"
                    )!,
                    userCode: "ABCD-EFGH",
                    expiresAt:
                        now.addingTimeInterval(600)
                )
        )
        let identityRequest = try #require(
            await transport.requests.last
        )
        #expect(
            identityRequest.url?.absoluteString
                == "https://api.github.com/user"
        )
        #expect(
            identityRequest.value(
                forHTTPHeaderField: "Authorization"
            ) == "Bearer github-token"
        )
    }

    private func jsonResponse(
        _ object: [String: Any],
        status: Int
    ) -> HTTPResponse {
        HTTPResponse(
            data: try! JSONSerialization.data(
                withJSONObject: object
            ),
            statusCode: status,
            headers: [:]
        )
    }
}

private actor CopilotOAuthRecordingTransport:
    HTTPTransport
{
    private var responses: [HTTPResponse]
    private(set) var requests: [URLRequest] = []

    init(responses: [HTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) throws
        -> HTTPResponse
    {
        requests.append(request)
        guard !responses.isEmpty else {
            throw CopilotOAuthTestError.noResponse
        }
        return responses.removeFirst()
    }
}

private actor CopilotOAuthRecordingBrowser:
    BrowserOpening
{
    private let result: Bool
    private(set) var lastURL: URL?

    init(result: Bool) {
        self.result = result
    }

    func open(_ url: URL) -> Bool {
        lastURL = url
        return result
    }
}

private actor CopilotOAuthSleepRecorder {
    private(set) var seconds: [TimeInterval] = []

    func record(_ seconds: TimeInterval) {
        self.seconds.append(seconds)
    }
}

private actor CopilotOAuthPromptRecorder {
    private(set) var prompt: GitHubCopilotAuthorizationPrompt?

    func record(
        _ prompt: GitHubCopilotAuthorizationPrompt
    ) {
        self.prompt = prompt
    }
}

private enum CopilotOAuthTestError: Error {
    case noResponse
}
