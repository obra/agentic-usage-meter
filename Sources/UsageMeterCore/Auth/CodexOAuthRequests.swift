import Foundation
import Security

public enum OAuthStateError: Error, Equatable, Sendable {
    case randomGenerationFailed(OSStatus)
}

public enum OAuthState {
    public static func generate() throws -> String {
        do {
            return try Data(
                secureRandomBytes(count: 32)
            ).base64URLEncodedString()
        } catch let SecureRandomError.generationFailed(status) {
            throw OAuthStateError.randomGenerationFailed(status)
        }
    }
}

public enum CodexOAuthRequestError: Error, Equatable, Sendable {
    case invalidURL
}

public enum CodexOAuthRequests {
    public static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    private static let authorizationEndpoint = URL(
        string: "https://auth.openai.com/oauth/authorize"
    )!
    private static let tokenEndpoint = URL(
        string: "https://auth.openai.com/oauth/token"
    )!

    public static func authorizationURL(
        redirectURL: URL,
        pkce: PKCECodes,
        state: String
    ) throws -> URL {
        var components = URLComponents(
            url: authorizationEndpoint,
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(
                name: "redirect_uri",
                value: redirectURL.absoluteString
            ),
            URLQueryItem(
                name: "scope",
                value: "openid profile email offline_access api.connectors.read api.connectors.invoke"
            ),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "originator", value: "codex_cli_rs"),
            URLQueryItem(name: "prompt", value: "select_account")
        ]

        guard let url = components?.url else {
            throw CodexOAuthRequestError.invalidURL
        }
        return url
    }

    public static func tokenExchangeRequest(
        code: String,
        redirectURL: URL,
        verifier: String
    ) throws -> URLRequest {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = try oauthFormData(
            [
                URLQueryItem(
                    name: "grant_type",
                    value: "authorization_code"
                ),
                URLQueryItem(name: "code", value: code),
                URLQueryItem(
                    name: "redirect_uri",
                    value: redirectURL.absoluteString
                ),
                URLQueryItem(name: "client_id", value: clientID),
                URLQueryItem(name: "code_verifier", value: verifier)
            ]
        )
        return request
    }

    public static func refreshRequest(
        refreshToken: String
    ) throws -> URLRequest {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = try JSONEncoder().encode(
            RefreshRequest(
                clientID: clientID,
                grantType: "refresh_token",
                refreshToken: refreshToken
            )
        )
        return request
    }

}

private struct RefreshRequest: Encodable {
    let clientID: String
    let grantType: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case grantType = "grant_type"
        case refreshToken = "refresh_token"
    }
}
