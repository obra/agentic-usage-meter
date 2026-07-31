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
                "expires_at": "2026-08-01T12:00:00Z"
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
        #expect(credential.identityKey == "user-1::team-1")
        #expect(
            credential.expiresAt
                == Date(
                    timeIntervalSince1970: 1_785_585_600
                )
        )
    }

    @Test
    func directCredentialFallsBackToEmailIdentity() throws {
        let data = Data(
            """
            {
              "key": "direct-token",
              "email": "User@Example.COM"
            }
            """.utf8
        )

        let credential = try SuperGrokAuthDocumentDecoder()
            .decode(data)

        #expect(credential.accessToken == "direct-token")
        #expect(credential.identityKey == "user@example.com")
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
