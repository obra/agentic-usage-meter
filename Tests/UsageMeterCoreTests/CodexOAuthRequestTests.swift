import Foundation
import Testing
@testable import UsageMeterCore

@Suite
struct CodexOAuthRequestTests {
    @Test
    func generatedStateMatchesCurrentCodexShape() throws {
        let state = try OAuthState.generate()

        #expect(state.count == 43)
        #expect(!state.contains("="))
        #expect(!state.contains("+"))
        #expect(!state.contains("/"))
    }

    @Test
    func authorizationRequestMatchesCurrentCodexBrowserFlow() throws {
        let redirectURL = try #require(
            URL(string: "http://127.0.0.1:1455/auth/callback")
        )
        let url = try CodexOAuthRequests.authorizationURL(
            redirectURL: redirectURL,
            pkce: PKCECodes(
                verifier: "verifier",
                challenge: "challenge"
            ),
            state: "state"
        )
        let components = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )
        let query = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).compactMap {
                item in item.value.map { (item.name, $0) }
            }
        )

        #expect(components.scheme == "https")
        #expect(components.host == "auth.openai.com")
        #expect(components.path == "/oauth/authorize")
        #expect(query["response_type"] == "code")
        #expect(query["client_id"] == CodexOAuthRequests.clientID)
        #expect(query["redirect_uri"] == redirectURL.absoluteString)
        #expect(
            query["scope"]
                == "openid profile email offline_access api.connectors.read api.connectors.invoke"
        )
        #expect(query["code_challenge"] == "challenge")
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["id_token_add_organizations"] == "true")
        #expect(query["codex_cli_simplified_flow"] == "true")
        #expect(query["state"] == "state")
        #expect(query["originator"] == "codex_cli_rs")
    }

    @Test
    func tokenExchangeUsesFormEncodedAuthorizationCodeGrant() throws {
        let redirectURL = try #require(
            URL(string: "http://127.0.0.1:1455/auth/callback")
        )
        let request = try CodexOAuthRequests.tokenExchangeRequest(
            code: "authorization code",
            redirectURL: redirectURL,
            verifier: "code verifier"
        )
        let form = try formValues(from: request)

        #expect(request.url?.absoluteString == "https://auth.openai.com/oauth/token")
        #expect(request.httpMethod == "POST")
        #expect(
            request.value(forHTTPHeaderField: "Content-Type")
                == "application/x-www-form-urlencoded"
        )
        #expect(form["grant_type"] == "authorization_code")
        #expect(form["code"] == "authorization code")
        #expect(form["redirect_uri"] == redirectURL.absoluteString)
        #expect(form["client_id"] == CodexOAuthRequests.clientID)
        #expect(form["code_verifier"] == "code verifier")
    }

    @Test
    func refreshUsesCurrentCodexJSONContract() throws {
        let request = try CodexOAuthRequests.refreshRequest(
            refreshToken: "refresh-secret"
        )
        let data = try #require(request.httpBody)
        let body = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: String]
        )

        #expect(request.url?.absoluteString == "https://auth.openai.com/oauth/token")
        #expect(request.httpMethod == "POST")
        #expect(
            request.value(forHTTPHeaderField: "Content-Type")
                == "application/json"
        )
        #expect(body["client_id"] == CodexOAuthRequests.clientID)
        #expect(body["grant_type"] == "refresh_token")
        #expect(body["refresh_token"] == "refresh-secret")
    }

    private func formValues(from request: URLRequest) throws -> [String: String] {
        let data = try #require(request.httpBody)
        let body = try #require(String(data: data, encoding: .utf8))
        var components = URLComponents()
        components.percentEncodedQuery = body
        return Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).compactMap {
                item in item.value.map { (item.name, $0) }
            }
        )
    }
}
