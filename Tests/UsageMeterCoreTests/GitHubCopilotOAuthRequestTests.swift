import Foundation
import Testing

@testable import UsageMeterCore

@Suite
struct GitHubCopilotOAuthRequestTests {
    @Test
    func deviceAuthorizationRequestsADeviceCodeFromGitHub() throws {
        let request =
            try GitHubCopilotOAuthRequests
            .deviceAuthorizationRequest()
        let form = try oauthFormValues(from: request)

        #expect(
            request.url?.absoluteString
                == "https://github.com/login/device/code"
        )
        #expect(request.httpMethod == "POST")
        #expect(
            request.value(forHTTPHeaderField: "Accept")
                == "application/json"
        )
        #expect(
            request.value(forHTTPHeaderField: "Content-Type")
                == "application/x-www-form-urlencoded"
        )
        #expect(
            form
                == [
                    "client_id":
                        GitHubCopilotOAuthRequests.clientID
                ]
        )
    }

    @Test
    func accessTokenPollUsesGitHubDeviceGrant() throws {
        let request =
            try GitHubCopilotOAuthRequests
            .accessTokenRequest(
                deviceCode: "device-code"
            )
        let form = try oauthFormValues(from: request)

        #expect(
            request.url?.absoluteString
                == "https://github.com/login/oauth/access_token"
        )
        #expect(request.httpMethod == "POST")
        #expect(
            request.value(forHTTPHeaderField: "Accept")
                == "application/json"
        )
        #expect(
            form["client_id"]
                == GitHubCopilotOAuthRequests.clientID
        )
        #expect(form["device_code"] == "device-code")
        #expect(
            form["grant_type"]
                == "urn:ietf:params:oauth:grant-type:device_code"
        )
    }
}
