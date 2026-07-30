import Foundation
import Testing
@testable import UsageMeterCore

@Suite(.serialized)
struct CodexOAuthFlowTests {
    @Test @MainActor
    func systemBrowserLaunchRequestsApplicationActivation() {
        #expect(SystemBrowserOpening.openConfiguration().activates)
    }

    @Test
    func regularBrowserLoginCompletesThroughLoopbackAndTokenExchange() async throws {
        let accessToken = try makeTestJWT(
            payload: ["exp": 2_000_000_000]
        )
        let idToken = try makeTestJWT(
            payload: [
                "email": "account@example.com",
                "https://api.openai.com/auth": [
                    "chatgpt_plan_type": "plus",
                    "chatgpt_account_id": "account-123"
                ]
            ]
        )
        let tokenResponse = try JSONSerialization.data(
            withJSONObject: [
                "access_token": accessToken,
                "refresh_token": "refresh-token",
                "id_token": idToken
            ]
        )
        let transport = OAuthRecordingTransport(
            responses: [
                HTTPResponse(
                    data: tokenResponse,
                    statusCode: 200,
                    headers: [:]
                )
            ]
        )
        let browser = CallbackBrowser()
        let flow = CodexOAuthFlow(
            transport: transport,
            browser: browser,
            callbackPorts: [0]
        )

        let result = try await flow.authenticate()

        #expect(result.identity.email == "account@example.com")
        #expect(result.identity.plan == "plus")
        #expect(result.credential.accountID == "account-123")
        let authorizationURL = try #require(await browser.lastURL)
        #expect(authorizationURL.host == "auth.openai.com")
        let request = try #require(await transport.requests.first)
        #expect(request.url?.absoluteString == "https://auth.openai.com/oauth/token")
    }

    @Test
    func failedBrowserOpenDoesNotExchangeTokens() async {
        let transport = OAuthRecordingTransport(responses: [])
        let flow = CodexOAuthFlow(
            transport: transport,
            browser: RefusingBrowser(),
            callbackPorts: [0]
        )

        await #expect(throws: CodexOAuthFlowError.browserOpenFailed) {
            _ = try await flow.authenticate()
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test
    func refreshRotatesCredentialThroughTokenEndpoint() async throws {
        let idToken = try makeTestJWT(
            payload: [
                "email": "account@example.com",
                "https://api.openai.com/auth": [
                    "chatgpt_plan_type": "business",
                    "chatgpt_account_id": "account-123"
                ]
            ]
        )
        let current = CodexOAuthResult(
            credential: OAuthCredential(
                accessToken: "old-access",
                refreshToken: "old-refresh",
                idToken: idToken,
                accountID: "account-123"
            ),
            identity: try CodexOAuthIdentity.decode(from: idToken)
        )
        let response = try JSONSerialization.data(
            withJSONObject: [
                "access_token": "new-access",
                "refresh_token": "new-refresh"
            ]
        )
        let transport = OAuthRecordingTransport(
            responses: [
                HTTPResponse(data: response, statusCode: 200, headers: [:])
            ]
        )
        let flow = CodexOAuthFlow(
            transport: transport,
            browser: RefusingBrowser(),
            callbackPorts: [0]
        )

        let refreshed = try await flow.refresh(current)

        #expect(refreshed.credential.accessToken == "new-access")
        #expect(refreshed.credential.refreshToken == "new-refresh")
        #expect(refreshed.identity == current.identity)
    }

    @Test
    func refreshWithoutRefreshTokenRequiresAuthentication() async throws {
        let idToken = try makeTestJWT(payload: ["email": "account@example.com"])
        let current = CodexOAuthResult(
            credential: OAuthCredential(
                accessToken: "access",
                idToken: idToken
            ),
            identity: try CodexOAuthIdentity.decode(from: idToken)
        )
        let transport = OAuthRecordingTransport(responses: [])
        let flow = CodexOAuthFlow(
            transport: transport,
            browser: RefusingBrowser(),
            callbackPorts: [0]
        )

        await #expect(
            throws: CodexOAuthFlowError.reauthenticationRequired
        ) {
            _ = try await flow.refresh(current)
        }
        #expect(await transport.requests.isEmpty)
    }
}

private actor CallbackBrowser: BrowserOpening {
    private(set) var lastURL: URL?

    func open(_ url: URL) async -> Bool {
        lastURL = url

        guard
            let components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            ),
            let redirect = components.queryItems?.first(
                where: { $0.name == "redirect_uri" }
            )?.value,
            let state = components.queryItems?.first(
                where: { $0.name == "state" }
            )?.value,
            var callback = URLComponents(string: redirect)
        else {
            return false
        }

        callback.queryItems = [
            URLQueryItem(name: "code", value: "authorization-code"),
            URLQueryItem(name: "state", value: state)
        ]
        guard let callbackURL = callback.url else {
            return false
        }

        do {
            let (_, response) = try await URLSession.shared.data(
                from: callbackURL
            )
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}

private struct RefusingBrowser: BrowserOpening {
    func open(_ url: URL) async -> Bool {
        false
    }
}

private actor OAuthRecordingTransport: HTTPTransport {
    private var responses: [HTTPResponse]
    private(set) var requests: [URLRequest] = []

    init(responses: [HTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) throws -> HTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            throw OAuthRecordingTransportError.noResponse
        }
        return responses.removeFirst()
    }
}

private enum OAuthRecordingTransportError: Error {
    case noResponse
}
