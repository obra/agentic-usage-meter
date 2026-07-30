import Foundation

public enum CodexOAuthTokenError: Error, Equatable, Sendable {
    case invalidResponse
    case invalidIDToken
}

extension CodexOAuthTokenError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidResponse:
            "The OAuth token response is invalid."
        case .invalidIDToken:
            "The OAuth identity token is invalid."
        }
    }
}

public struct CodexOAuthIdentity: Equatable, Sendable {
    public let email: String?
    public let plan: String?
    public let userID: String?
    public let accountID: String?

    public init(
        email: String?,
        plan: String?,
        userID: String?,
        accountID: String?
    ) {
        self.email = email
        self.plan = plan
        self.userID = userID
        self.accountID = accountID
    }

    public static func decode(from idToken: String) throws -> Self {
        let claims: IdentityClaims
        do {
            claims = try JWTMetadataDecoder.decode(
                IdentityClaims.self,
                from: idToken
            )
        } catch {
            throw CodexOAuthTokenError.invalidIDToken
        }

        return CodexOAuthIdentity(
            email: claims.email ?? claims.profile?.email,
            plan: claims.auth?.plan,
            userID: claims.auth?.chatGPTUserID ?? claims.auth?.userID,
            accountID: claims.auth?.accountID
        )
    }
}

public struct CodexOAuthResult: Equatable, Sendable {
    public let credential: OAuthCredential
    public let identity: CodexOAuthIdentity

    public init(
        credential: OAuthCredential,
        identity: CodexOAuthIdentity
    ) {
        self.credential = credential
        self.identity = identity
    }
}

public enum CodexOAuthTokenDecoder {
    public static func decodeInitial(_ data: Data) throws -> CodexOAuthResult {
        let response: InitialTokenResponse
        do {
            response = try JSONDecoder().decode(
                InitialTokenResponse.self,
                from: data
            )
        } catch {
            throw CodexOAuthTokenError.invalidResponse
        }

        guard
            !response.accessToken.isEmpty,
            !response.refreshToken.isEmpty,
            !response.idToken.isEmpty
        else {
            throw CodexOAuthTokenError.invalidResponse
        }

        let identity = try CodexOAuthIdentity.decode(from: response.idToken)
        return CodexOAuthResult(
            credential: OAuthCredential(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                idToken: response.idToken,
                accountID: identity.accountID,
                expiresAt: expiration(of: response.accessToken)
            ),
            identity: identity
        )
    }

    public static func applyRefresh(
        _ data: Data,
        to original: CodexOAuthResult
    ) throws -> CodexOAuthResult {
        let response: RefreshTokenResponse
        do {
            response = try JSONDecoder().decode(
                RefreshTokenResponse.self,
                from: data
            )
        } catch {
            throw CodexOAuthTokenError.invalidResponse
        }

        let accessToken = nonempty(response.accessToken)
            ?? original.credential.accessToken
        let refreshToken = nonempty(response.refreshToken)
            ?? original.credential.refreshToken
        let idToken = nonempty(response.idToken)
            ?? original.credential.idToken

        guard !accessToken.isEmpty else {
            throw CodexOAuthTokenError.invalidResponse
        }

        let identity: CodexOAuthIdentity
        if let refreshedIDToken = nonempty(response.idToken) {
            identity = try CodexOAuthIdentity.decode(from: refreshedIDToken)
        } else {
            identity = original.identity
        }

        return CodexOAuthResult(
            credential: OAuthCredential(
                accessToken: accessToken,
                refreshToken: refreshToken,
                idToken: idToken,
                accountID: identity.accountID
                    ?? original.credential.accountID,
                expiresAt: expiration(of: accessToken)
                    ?? original.credential.expiresAt
            ),
            identity: identity
        )
    }

    private static func expiration(of token: String) -> Date? {
        let claims = try? JWTMetadataDecoder.decode(
            ExpirationClaims.self,
            from: token
        )
        guard let seconds = claims?.expiration else {
            return nil
        }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }
}

private struct InitialTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let idToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
    }
}

private struct RefreshTokenResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
    }
}

private struct IdentityClaims: Decodable {
    let email: String?
    let profile: ProfileClaims?
    let auth: AuthClaims?

    enum CodingKeys: String, CodingKey {
        case email
        case profile = "https://api.openai.com/profile"
        case auth = "https://api.openai.com/auth"
    }
}

private struct ProfileClaims: Decodable {
    let email: String?
}

private struct AuthClaims: Decodable {
    let plan: String?
    let chatGPTUserID: String?
    let userID: String?
    let accountID: String?

    enum CodingKeys: String, CodingKey {
        case plan = "chatgpt_plan_type"
        case chatGPTUserID = "chatgpt_user_id"
        case userID = "user_id"
        case accountID = "chatgpt_account_id"
    }
}

private struct ExpirationClaims: Decodable {
    let expiration: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case expiration = "exp"
    }
}

private enum JWTMetadataDecoder {
    static func decode<Value: Decodable>(
        _ type: Value.Type,
        from token: String
    ) throws -> Value {
        // These claims are display metadata from a TLS-protected token response;
        // the bearer token itself remains the authorization authority.
        let components = token.split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard
            components.count == 3,
            components.allSatisfy({ !$0.isEmpty }),
            let payload = Data(base64URLEncoded: String(components[1]))
        else {
            throw CodexOAuthTokenError.invalidIDToken
        }
        return try JSONDecoder().decode(Value.self, from: payload)
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var encoded = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = encoded.count % 4
        if remainder != 0 {
            encoded.append(String(repeating: "=", count: 4 - remainder))
        }
        self.init(base64Encoded: encoded)
    }
}
