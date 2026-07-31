import Foundation

public enum GitHubCopilotOAuthFlowError:
    Error,
    Equatable,
    Sendable
{
    case browserOpenFailed
    case authorizationFailed
    case invalidResponse
    case temporaryFailure
}

public struct GitHubCopilotAuthorizationPrompt:
    Equatable,
    Sendable
{
    public let verificationURL: URL
    public let userCode: String
    public let expiresAt: Date

    public init(
        verificationURL: URL,
        userCode: String,
        expiresAt: Date
    ) {
        self.verificationURL = verificationURL
        self.userCode = userCode
        self.expiresAt = expiresAt
    }
}

public struct GitHubCopilotOAuthFlow: Sendable {
    public typealias Sleep =
        @Sendable (TimeInterval) async throws -> Void
    public typealias AuthorizationUpdate =
        @Sendable (
            GitHubCopilotAuthorizationPrompt
        ) async -> Void

    private let transport: any HTTPTransport
    private let browser: any BrowserOpening
    private let now: @Sendable () -> Date
    private let sleep: Sleep

    public init(
        transport: any HTTPTransport =
            URLSessionHTTPTransport(),
        browser: any BrowserOpening =
            SystemBrowserOpening(),
        now: @escaping @Sendable () -> Date = {
            Date()
        },
        sleep: @escaping Sleep = { seconds in
            try await Task.sleep(
                for: .milliseconds(
                    Int64(
                        (seconds * 1_000).rounded()
                    )
                )
            )
        }
    ) {
        self.transport = transport
        self.browser = browser
        self.now = now
        self.sleep = sleep
    }

    public func authenticate(
        onPrompt:
            @escaping AuthorizationUpdate = { _ in }
    ) async throws -> GitHubCopilotOAuthResult {
        let authorizationResponse = try await send(
            GitHubCopilotOAuthRequests
                .deviceAuthorizationRequest()
        )
        guard authorizationResponse.statusCode == 200 else {
            throw GitHubCopilotOAuthFlowError
                .temporaryFailure
        }

        let authorization: DeviceAuthorization
        do {
            authorization = try JSONDecoder().decode(
                DeviceAuthorization.self,
                from: authorizationResponse.data
            )
        } catch {
            throw GitHubCopilotOAuthFlowError
                .invalidResponse
        }
        guard
            !authorization.deviceCode.isEmpty,
            !authorization.userCode.isEmpty,
            authorization.expiresIn > 0,
            authorization.interval > 0,
            let verificationURL = URL(
                string: authorization.verificationURI
            ),
            verificationURL.scheme == "https",
            verificationURL.host == "github.com"
        else {
            throw GitHubCopilotOAuthFlowError
                .invalidResponse
        }

        await onPrompt(
            GitHubCopilotAuthorizationPrompt(
                verificationURL: verificationURL,
                userCode: authorization.userCode,
                expiresAt: now().addingTimeInterval(
                    TimeInterval(
                        authorization.expiresIn
                    )
                )
            )
        )
        guard await browser.open(verificationURL) else {
            throw GitHubCopilotOAuthFlowError
                .browserOpenFailed
        }

        var interval = TimeInterval(
            authorization.interval
        )
        var remaining = TimeInterval(
            authorization.expiresIn
        )
        while remaining > 0 {
            let response = try await send(
                GitHubCopilotOAuthRequests
                    .accessTokenRequest(
                        deviceCode:
                            authorization.deviceCode
                    )
            )
            let token = try tokenResult(
                from: response.data
            )
            if let accessToken = token.accessToken {
                return try await identity(
                    accessToken: accessToken
                )
            }

            switch token.error {
            case "authorization_pending":
                break
            case "slow_down":
                interval += 5
            case "expired_token", "access_denied":
                throw GitHubCopilotOAuthFlowError
                    .authorizationFailed
            default:
                throw GitHubCopilotOAuthFlowError
                    .authorizationFailed
            }

            try await sleep(interval)
            remaining -= interval
        }

        throw GitHubCopilotOAuthFlowError
            .authorizationFailed
    }

    private func identity(
        accessToken: String
    ) async throws -> GitHubCopilotOAuthResult {
        var request = URLRequest(
            url: URL(
                string: "https://api.github.com/user"
            )!
        )
        request.httpMethod = "GET"
        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "application/vnd.github+json",
            forHTTPHeaderField: "Accept"
        )
        let response = try await send(request)
        guard response.statusCode == 200 else {
            throw GitHubCopilotOAuthFlowError
                .authorizationFailed
        }

        let identity: UserIdentity
        do {
            identity = try JSONDecoder().decode(
                UserIdentity.self,
                from: response.data
            )
        } catch {
            throw GitHubCopilotOAuthFlowError
                .invalidResponse
        }
        guard
            !identity.login.isEmpty,
            identity.id > 0
        else {
            throw GitHubCopilotOAuthFlowError
                .invalidResponse
        }

        return GitHubCopilotOAuthResult(
            credential: GitHubCopilotCredential(
                accessToken: accessToken,
                userID: String(identity.id),
                login: identity.login
            )
        )
    }

    private func send(
        _ request: URLRequest
    ) async throws -> HTTPResponse {
        do {
            return try await transport.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GitHubCopilotOAuthFlowError
                .temporaryFailure
        }
    }

    private func tokenResult(
        from data: Data
    ) throws -> TokenResult {
        do {
            return try JSONDecoder().decode(
                TokenResult.self,
                from: data
            )
        } catch {
            throw GitHubCopilotOAuthFlowError
                .invalidResponse
        }
    }
}

private struct DeviceAuthorization: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationURI: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

private struct TokenResult: Decodable {
    let accessToken: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case error
    }
}

private struct UserIdentity: Decodable {
    let login: String
    let id: Int
}
