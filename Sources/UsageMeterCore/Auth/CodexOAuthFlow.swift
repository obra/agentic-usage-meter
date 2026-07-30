import AppKit
import Foundation

public protocol BrowserOpening: Sendable {
    func open(_ url: URL) async -> Bool
}

public struct SystemBrowserOpening: BrowserOpening {
    public init() {}

    public func open(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                NSWorkspace.shared.open(
                    url,
                    configuration: Self.openConfiguration()
                ) { application, error in
                    continuation.resume(
                        returning: application != nil && error == nil
                    )
                }
            }
        }
    }

    @MainActor
    static func openConfiguration() -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        return configuration
    }
}

public enum CodexOAuthFlowError: Error, Equatable, Sendable {
    case browserOpenFailed
    case authorizationFailed
    case reauthenticationRequired
    case invalidTokenResponse
    case temporaryFailure
}

extension CodexOAuthFlowError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .browserOpenFailed:
            "The system browser could not be opened."
        case .authorizationFailed:
            "Codex authorization failed."
        case .reauthenticationRequired:
            "Codex authentication must be repeated."
        case .invalidTokenResponse:
            "Codex returned an invalid token response."
        case .temporaryFailure:
            "Codex authentication is temporarily unavailable."
        }
    }
}

public struct CodexOAuthFlow: Sendable {
    private let transport: any HTTPTransport
    private let browser: any BrowserOpening
    private let callbackPorts: [UInt16]

    public init(
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        browser: any BrowserOpening = SystemBrowserOpening(),
        callbackPorts: [UInt16] = LoopbackOAuthCallbackServer.defaultPorts
    ) {
        self.transport = transport
        self.browser = browser
        self.callbackPorts = callbackPorts
    }

    public func authenticate() async throws -> CodexOAuthResult {
        let pkce = try PKCECodes.generate()
        let state = try OAuthState.generate()
        let server = try await LoopbackOAuthCallbackServer.start(
            expectedState: state,
            preferredPorts: callbackPorts
        )
        defer { server.cancel() }

        let authorizationURL = try CodexOAuthRequests.authorizationURL(
            redirectURL: server.callbackURL,
            pkce: pkce,
            state: state
        )
        guard await browser.open(authorizationURL) else {
            throw CodexOAuthFlowError.browserOpenFailed
        }

        let code = try await server.waitForCode()
        let request = try CodexOAuthRequests.tokenExchangeRequest(
            code: code,
            redirectURL: server.callbackURL,
            verifier: pkce.verifier
        )
        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch {
            throw CodexOAuthFlowError.temporaryFailure
        }

        guard (200 ... 299).contains(response.statusCode) else {
            throw CodexOAuthFlowError.authorizationFailed
        }
        do {
            return try CodexOAuthTokenDecoder.decodeInitial(response.data)
        } catch {
            throw CodexOAuthFlowError.invalidTokenResponse
        }
    }

    public func refresh(
        _ current: CodexOAuthResult
    ) async throws -> CodexOAuthResult {
        guard
            let refreshToken = current.credential.refreshToken,
            !refreshToken.isEmpty
        else {
            throw CodexOAuthFlowError.reauthenticationRequired
        }

        let request = try CodexOAuthRequests.refreshRequest(
            refreshToken: refreshToken
        )
        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch {
            throw CodexOAuthFlowError.temporaryFailure
        }

        switch response.statusCode {
        case 200 ... 299:
            do {
                return try CodexOAuthTokenDecoder.applyRefresh(
                    response.data,
                    to: current
                )
            } catch {
                throw CodexOAuthFlowError.invalidTokenResponse
            }
        case 400, 401, 403:
            throw CodexOAuthFlowError.reauthenticationRequired
        default:
            throw CodexOAuthFlowError.temporaryFailure
        }
    }
}
