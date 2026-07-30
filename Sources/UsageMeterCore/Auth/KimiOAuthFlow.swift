import Foundation

public enum KimiOAuthFlowError: Error, Equatable, Sendable {
    case browserOpenFailed
    case authorizationFailed
    case reauthenticationRequired
    case invalidResponse
    case temporaryFailure
}

extension KimiOAuthFlowError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .browserOpenFailed:
            "The system browser could not be opened."
        case .authorizationFailed:
            "Kimi authorization failed."
        case .reauthenticationRequired:
            "Kimi authentication must be repeated."
        case .invalidResponse:
            "Kimi returned an invalid OAuth response."
        case .temporaryFailure:
            "Kimi authentication is temporarily unavailable."
        }
    }
}

public struct KimiOAuthFlow: Sendable {
    public typealias Sleep = @Sendable (TimeInterval) async throws -> Void

    private let device: KimiDeviceInfo
    private let transport: any HTTPTransport
    private let browser: any BrowserOpening
    private let now: @Sendable () -> Date
    private let sleep: Sleep

    public init(
        device: KimiDeviceInfo,
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        browser: any BrowserOpening = SystemBrowserOpening(),
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping Sleep = { seconds in
            try await Task.sleep(
                for: .milliseconds(
                    Int64((seconds * 1_000).rounded())
                )
            )
        }
    ) {
        self.device = device
        self.transport = transport
        self.browser = browser
        self.now = now
        self.sleep = sleep
    }

    public func authenticate() async throws -> OAuthCredential {
        let authorizationRequest =
            try KimiOAuthRequests.deviceAuthorizationRequest(
                device: device
            )
        let authorizationResponse = try await send(authorizationRequest)
        guard authorizationResponse.statusCode == 200 else {
            throw KimiOAuthFlowError.temporaryFailure
        }

        let authorization: DeviceAuthorization
        do {
            authorization = try JSONDecoder().decode(
                DeviceAuthorization.self,
                from: authorizationResponse.data
            )
        } catch {
            throw KimiOAuthFlowError.invalidResponse
        }
        guard
            !authorization.deviceCode.isEmpty,
            let verificationURL = URL(
                string: authorization.verificationURIComplete
            ),
            verificationURL.scheme == "https",
            verificationURL.host == "auth.kimi.com"
        else {
            throw KimiOAuthFlowError.invalidResponse
        }

        guard await browser.open(verificationURL) else {
            throw KimiOAuthFlowError.browserOpenFailed
        }

        var interval = max(TimeInterval(authorization.interval), 1)
        var remaining = TimeInterval(
            authorization.expiresIn ?? 900
        )

        while remaining > 0 {
            let request = try KimiOAuthRequests.deviceTokenRequest(
                deviceCode: authorization.deviceCode,
                device: device
            )
            let response = try await send(request)

            if response.statusCode == 200 {
                return try decodeCredential(response.data)
            }

            let errorCode = tokenErrorCode(from: response.data)
            switch errorCode {
            case "authorization_pending":
                break
            case "slow_down":
                interval += 5
            case "expired_token", "access_denied":
                throw KimiOAuthFlowError.authorizationFailed
            default:
                if response.statusCode == 429
                    || response.statusCode >= 500
                {
                    break
                }
                throw KimiOAuthFlowError.authorizationFailed
            }

            try await sleep(interval)
            remaining -= interval
        }

        throw KimiOAuthFlowError.authorizationFailed
    }

    public func refresh(
        _ credential: OAuthCredential
    ) async throws -> OAuthCredential {
        guard
            let refreshToken = credential.refreshToken,
            !refreshToken.isEmpty
        else {
            throw KimiOAuthFlowError.reauthenticationRequired
        }

        let request = try KimiOAuthRequests.refreshRequest(
            refreshToken: refreshToken,
            device: device
        )
        let response = try await send(request)
        switch response.statusCode {
        case 200:
            return try decodeCredential(response.data)
        case 401, 403:
            throw KimiOAuthFlowError.reauthenticationRequired
        default:
            throw KimiOAuthFlowError.temporaryFailure
        }
    }

    private func send(_ request: URLRequest) async throws -> HTTPResponse {
        do {
            return try await transport.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw KimiOAuthFlowError.temporaryFailure
        }
    }

    private func decodeCredential(_ data: Data) throws -> OAuthCredential {
        let response: TokenResponse
        do {
            response = try JSONDecoder().decode(
                TokenResponse.self,
                from: data
            )
        } catch {
            throw KimiOAuthFlowError.invalidResponse
        }

        guard
            !response.accessToken.isEmpty,
            !response.refreshToken.isEmpty,
            response.expiresIn.isFinite,
            response.expiresIn > 0
        else {
            throw KimiOAuthFlowError.invalidResponse
        }
        return OAuthCredential(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: now().addingTimeInterval(response.expiresIn)
        )
    }

    private func tokenErrorCode(from data: Data) -> String? {
        try? JSONDecoder().decode(
            TokenErrorResponse.self,
            from: data
        ).error
    }
}

private struct DeviceAuthorization: Decodable {
    let deviceCode: String
    let verificationURIComplete: String
    let expiresIn: Int?
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case verificationURIComplete = "verification_uri_complete"
        case expiresIn = "expires_in"
        case interval
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct TokenErrorResponse: Decodable {
    let error: String
}
