import Foundation
import Testing
@testable import UsageMeterCore

@Suite
struct KimiOAuthRequestTests {
    private let device = KimiDeviceInfo(
        name: "Jesse Mac",
        model: "macOS 26.5 arm64",
        osVersion: "Version 26.5",
        id: "device-123",
        clientVersion: "1.45.0"
    )

    @Test
    func deviceAuthorizationUsesCurrentKimiContract() throws {
        let request = try KimiOAuthRequests.deviceAuthorizationRequest(
            device: device
        )
        let form = try oauthFormValues(from: request)

        #expect(
            request.url?.absoluteString
                == "https://auth.kimi.com/api/oauth/device_authorization"
        )
        #expect(request.httpMethod == "POST")
        #expect(form == ["client_id": KimiOAuthRequests.clientID])
        expectDeviceHeaders(on: request)
    }

    @Test
    func deviceTokenPollUsesRFC8628Grant() throws {
        let request = try KimiOAuthRequests.deviceTokenRequest(
            deviceCode: "device-code",
            device: device
        )
        let form = try oauthFormValues(from: request)

        #expect(
            request.url?.absoluteString
                == "https://auth.kimi.com/api/oauth/token"
        )
        #expect(form["client_id"] == KimiOAuthRequests.clientID)
        #expect(form["device_code"] == "device-code")
        #expect(
            form["grant_type"]
                == "urn:ietf:params:oauth:grant-type:device_code"
        )
        expectDeviceHeaders(on: request)
    }

    @Test
    func refreshUsesKimiOAuthGrant() throws {
        let request = try KimiOAuthRequests.refreshRequest(
            refreshToken: "refresh-token",
            device: device
        )
        let form = try oauthFormValues(from: request)

        #expect(form["client_id"] == KimiOAuthRequests.clientID)
        #expect(form["grant_type"] == "refresh_token")
        #expect(form["refresh_token"] == "refresh-token")
        expectDeviceHeaders(on: request)
    }

    private func expectDeviceHeaders(on request: URLRequest) {
        #expect(
            request.value(forHTTPHeaderField: "Content-Type")
                == "application/x-www-form-urlencoded"
        )
        #expect(
            request.value(forHTTPHeaderField: "X-Msh-Platform")
                == "kimi_cli"
        )
        #expect(
            request.value(forHTTPHeaderField: "X-Msh-Version")
                == device.clientVersion
        )
        #expect(
            request.value(forHTTPHeaderField: "X-Msh-Device-Name")
                == device.name
        )
        #expect(
            request.value(forHTTPHeaderField: "X-Msh-Device-Model")
                == device.model
        )
        #expect(
            request.value(forHTTPHeaderField: "X-Msh-Os-Version")
                == device.osVersion
        )
        #expect(
            request.value(forHTTPHeaderField: "X-Msh-Device-Id")
                == device.id
        )
    }
}
