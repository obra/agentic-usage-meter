import Foundation
import Testing
@testable import UsageMeterCore

@Suite
struct KimiOAuthFlowTests {
    private let device = KimiDeviceInfo(
        name: "Test Mac",
        model: "macOS arm64",
        osVersion: "Version 26",
        id: "device-id",
        clientVersion: "1.45.0"
    )

    @Test
    func deviceLoginOpensBrowserPollsAndReturnsCredential() async throws {
        let transport = KimiRecordingTransport(
            responses: [
                jsonResponse(
                    [
                        "user_code": "ABCD-EFGH",
                        "device_code": "device-code",
                        "verification_uri": "https://auth.kimi.com/device",
                        "verification_uri_complete":
                            "https://auth.kimi.com/device?user_code=ABCD-EFGH",
                        "expires_in": 600,
                        "interval": 5
                    ],
                    status: 200
                ),
                jsonResponse(
                    [
                        "error": "authorization_pending",
                        "error_description": "authorization pending"
                    ],
                    status: 400
                ),
                jsonResponse(
                    [
                        "access_token": "access-token",
                        "refresh_token": "refresh-token",
                        "expires_in": 3600,
                        "scope": "openid",
                        "token_type": "Bearer"
                    ],
                    status: 200
                )
            ]
        )
        let browser = KimiRecordingBrowser(result: true)
        let sleeper = KimiSleepRecorder()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let flow = KimiOAuthFlow(
            device: device,
            transport: transport,
            browser: browser,
            now: { now },
            sleep: { seconds in
                await sleeper.record(seconds)
            }
        )

        let credential = try await flow.authenticate()

        #expect(
            credential
                == OAuthCredential(
                    accessToken: "access-token",
                    refreshToken: "refresh-token",
                    expiresAt: now.addingTimeInterval(3_600)
                )
        )
        #expect(
            await browser.lastURL?.absoluteString
                == "https://auth.kimi.com/device?user_code=ABCD-EFGH"
        )
        #expect(await sleeper.seconds == [5])
        #expect(await transport.requests.count == 3)
    }

    @Test
    func browserRefusalStopsBeforeTokenPolling() async {
        let transport = KimiRecordingTransport(
            responses: [
                jsonResponse(
                    [
                        "user_code": "ABCD",
                        "device_code": "device-code",
                        "verification_uri_complete":
                            "https://auth.kimi.com/device?user_code=ABCD",
                        "interval": 5
                    ],
                    status: 200
                )
            ]
        )
        let flow = KimiOAuthFlow(
            device: device,
            transport: transport,
            browser: KimiRecordingBrowser(result: false),
            sleep: { _ in }
        )

        await #expect(throws: KimiOAuthFlowError.browserOpenFailed) {
            _ = try await flow.authenticate()
        }
        #expect(await transport.requests.count == 1)
    }

    @Test
    func refreshRotatesKimiCredential() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let transport = KimiRecordingTransport(
            responses: [
                jsonResponse(
                    [
                        "access_token": "new-access",
                        "refresh_token": "new-refresh",
                        "expires_in": 7200,
                        "scope": "openid",
                        "token_type": "Bearer"
                    ],
                    status: 200
                )
            ]
        )
        let flow = KimiOAuthFlow(
            device: device,
            transport: transport,
            browser: KimiRecordingBrowser(result: false),
            now: { now },
            sleep: { _ in }
        )

        let credential = try await flow.refresh(
            OAuthCredential(
                accessToken: "old-access",
                refreshToken: "old-refresh"
            )
        )

        #expect(credential.accessToken == "new-access")
        #expect(credential.refreshToken == "new-refresh")
        #expect(credential.expiresAt == now.addingTimeInterval(7_200))
        let request = try #require(await transport.requests.first)
        #expect(
            try oauthFormValues(from: request)["refresh_token"]
                == "old-refresh"
        )
    }

    @Test
    func missingRefreshTokenRequiresAuthentication() async {
        let transport = KimiRecordingTransport(responses: [])
        let flow = KimiOAuthFlow(
            device: device,
            transport: transport,
            browser: KimiRecordingBrowser(result: false),
            sleep: { _ in }
        )

        await #expect(
            throws: KimiOAuthFlowError.reauthenticationRequired
        ) {
            _ = try await flow.refresh(
                OAuthCredential(accessToken: "access")
            )
        }
        #expect(await transport.requests.isEmpty)
    }

    private func jsonResponse(
        _ object: [String: Any],
        status: Int
    ) -> HTTPResponse {
        HTTPResponse(
            data: try! JSONSerialization.data(withJSONObject: object),
            statusCode: status,
            headers: [:]
        )
    }
}

private actor KimiRecordingTransport: HTTPTransport {
    private var responses: [HTTPResponse]
    private(set) var requests: [URLRequest] = []

    init(responses: [HTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) throws -> HTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            throw KimiFlowTestError.noResponse
        }
        return responses.removeFirst()
    }
}

private actor KimiRecordingBrowser: BrowserOpening {
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

private actor KimiSleepRecorder {
    private(set) var seconds: [TimeInterval] = []

    func record(_ seconds: TimeInterval) {
        self.seconds.append(seconds)
    }
}

private enum KimiFlowTestError: Error {
    case noResponse
}
