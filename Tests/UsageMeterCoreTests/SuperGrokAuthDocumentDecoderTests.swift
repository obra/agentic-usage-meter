import Foundation
import Testing

@testable import UsageMeterCore

@Suite
struct SuperGrokAuthDocumentDecoderTests {
    @Test
    func oidcCredentialIsPreferredAndKeepsStableIdentity() throws {
        let data = Data(
            """
            {
              "https://accounts.x.ai/sign-in": {
                "key": "legacy-token",
                "email": "legacy@example.com"
              },
              "https://auth.x.ai::profile": {
                "key": "oidc-token",
                "email": "User@Example.COM",
                "team_id": "team-1",
                "user_id": "user-1",
                "auth_mode": "oidc",
                "create_time": "2026-08-01T11:00:00Z",
                "expires_at": "2026-08-01T12:00:00Z",
                "refresh_token": "refresh-token",
                "oidc_issuer": "https://auth.x.ai",
                "oidc_client_id": "client-1"
              }
            }
            """.utf8
        )

        let credential = try SuperGrokAuthDocumentDecoder()
            .decode(data)

        #expect(credential.accessToken == "oidc-token")
        #expect(credential.email == "User@Example.COM")
        #expect(credential.teamID == "team-1")
        #expect(credential.userID == "user-1")
        #expect(credential.authMode == "oidc")
        #expect(credential.refreshToken == "refresh-token")
        #expect(credential.oidcIssuer == "https://auth.x.ai")
        #expect(credential.oidcClientID == "client-1")
        #expect(
            credential.createdAt
                == Date(
                    timeIntervalSince1970: 1_785_582_000
                )
        )
        #expect(credential.identityKey == "user-1::team-1")
        #expect(
            credential.expiresAt
                == Date(
                    timeIntervalSince1970: 1_785_585_600
                )
        )
    }

    @Test
    func existingCredentialJSONRemainsReadable() throws {
        let credential = try JSONDecoder().decode(
            SuperGrokCredential.self,
            from: Data(
                #"""
                {
                  "accessToken": "existing-token",
                  "email": "user@example.com",
                  "teamID": "team-1",
                  "userID": "user-1",
                  "authMode": "oidc",
                  "expiresAt": null
                }
                """#.utf8
            )
        )

        #expect(credential.accessToken == "existing-token")
        #expect(credential.refreshToken == nil)
        #expect(credential.oidcIssuer == nil)
        #expect(credential.oidcClientID == nil)
        #expect(credential.createdAt == nil)
    }

    @Test
    func credentialWithoutBillingUserIDIsRejected() throws {
        let data = Data(
            """
            {
              "key": "direct-token",
              "email": "User@Example.COM"
            }
            """.utf8
        )

        #expect(
            throws:
                ProviderClientError
                .unsupportedResponse
        ) {
            _ = try SuperGrokAuthDocumentDecoder()
                .decode(data)
        }
    }

    @Test
    func missingAccessTokenIsRejected() {
        let data = Data(
            """
            {
              "https://auth.x.ai::profile": {
                "email": "user@example.com"
              }
            }
            """.utf8
        )

        #expect(
            throws:
                ProviderClientError
                .reauthenticationRequired
        ) {
            _ = try SuperGrokAuthDocumentDecoder()
                .decode(data)
        }
    }
}
