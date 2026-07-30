import Foundation
import Testing
@testable import UsageMeterCore

@Suite
struct CodexOAuthTokenTests {
    @Test
    func decodesCredentialAndIdentityFromInitialTokenResponse() throws {
        let accessToken = try jwt(
            payload: [
                "exp": 2_000_000_000
            ]
        )
        let idToken = try jwt(
            payload: [
                "email": "work@example.com",
                "https://api.openai.com/auth": [
                    "chatgpt_plan_type": "business",
                    "chatgpt_user_id": "user-123",
                    "chatgpt_account_id": "account-123"
                ]
            ]
        )
        let response = try JSONSerialization.data(
            withJSONObject: [
                "access_token": accessToken,
                "refresh_token": "refresh-token",
                "id_token": idToken
            ]
        )

        let result = try CodexOAuthTokenDecoder.decodeInitial(response)

        #expect(
            result.credential
                == OAuthCredential(
                    accessToken: accessToken,
                    refreshToken: "refresh-token",
                    idToken: idToken,
                    accountID: "account-123",
                    expiresAt: Date(timeIntervalSince1970: 2_000_000_000)
                )
        )
        #expect(result.identity.email == "work@example.com")
        #expect(result.identity.plan == "business")
        #expect(result.identity.userID == "user-123")
        #expect(result.identity.accountID == "account-123")
    }

    @Test
    func identityFallsBackToProfileEmailAndLegacyUserID() throws {
        let idToken = try jwt(
            payload: [
                "https://api.openai.com/profile": [
                    "email": "personal@example.com"
                ],
                "https://api.openai.com/auth": [
                    "chatgpt_plan_type": "plus",
                    "user_id": "legacy-user"
                ]
            ]
        )

        let identity = try CodexOAuthIdentity.decode(from: idToken)

        #expect(identity.email == "personal@example.com")
        #expect(identity.plan == "plus")
        #expect(identity.userID == "legacy-user")
        #expect(identity.accountID == nil)
    }

    @Test
    func refreshRotatesPresentTokensAndPreservesOmittedTokens() throws {
        let originalIDToken = try jwt(
            payload: [
                "email": "original@example.com",
                "https://api.openai.com/auth": [
                    "chatgpt_plan_type": "plus",
                    "chatgpt_account_id": "original-account"
                ]
            ]
        )
        let original = CodexOAuthResult(
            credential: OAuthCredential(
                accessToken: "original-access",
                refreshToken: "original-refresh",
                idToken: originalIDToken,
                accountID: "original-account"
            ),
            identity: try CodexOAuthIdentity.decode(from: originalIDToken)
        )
        let refreshedAccessToken = try jwt(
            payload: [
                "exp": 2_000_003_600
            ]
        )
        let response = try JSONSerialization.data(
            withJSONObject: [
                "access_token": refreshedAccessToken,
                "refresh_token": "rotated-refresh"
            ]
        )

        let refreshed = try CodexOAuthTokenDecoder.applyRefresh(
            response,
            to: original
        )

        #expect(refreshed.credential.accessToken == refreshedAccessToken)
        #expect(refreshed.credential.refreshToken == "rotated-refresh")
        #expect(refreshed.credential.idToken == originalIDToken)
        #expect(refreshed.credential.accountID == "original-account")
        #expect(
            refreshed.credential.expiresAt
                == Date(timeIntervalSince1970: 2_000_003_600)
        )
        #expect(refreshed.identity == original.identity)
    }

    @Test
    func rejectsMalformedInitialTokenResponseWithoutEchoingIt() throws {
        let secret = "sensitive-response-value"
        let response = Data(
            #"{"access_token":"\#(secret)","refresh_token":"","id_token":"invalid"}"#.utf8
        )

        do {
            _ = try CodexOAuthTokenDecoder.decodeInitial(response)
            Issue.record("Expected token decoding to fail")
        } catch {
            #expect(!String(describing: error).contains(secret))
        }
    }

    private func jwt(payload: [String: Any]) throws -> String {
        let header = try JSONSerialization.data(
            withJSONObject: ["alg": "none"]
        )
        let payload = try JSONSerialization.data(withJSONObject: payload)
        return [
            header.base64URLEncodedString(),
            payload.base64URLEncodedString(),
            "signature"
        ].joined(separator: ".")
    }
}
