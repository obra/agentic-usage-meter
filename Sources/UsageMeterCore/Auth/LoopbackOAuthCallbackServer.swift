import Foundation
import Network

public enum LoopbackOAuthCallbackServerError: Error, Equatable, Sendable {
    case unableToBind
    case cancelled
    case alreadyWaiting
}

public final class LoopbackOAuthCallbackServer: @unchecked Sendable {
    public static let defaultPorts: [UInt16] = [1455, 1457]

    private struct CallbackState {
        var result: Result<String, Error>?
        var continuation: CheckedContinuation<String, Error>?
        var isWaiting = false
        var isFinished = false
    }

    private let expectedState: String
    private let listener: NWListener
    private let queue = DispatchQueue(label: "UsageMeter.loopback-oauth")
    private let callbackLock = NSLock()
    private var callbackState = CallbackState()

    public var callbackURL: URL {
        let port = listener.port?.rawValue ?? 0
        return URL(string: "http://127.0.0.1:\(port)/auth/callback")!
    }

    public static func start(
        expectedState: String,
        preferredPorts: [UInt16] = defaultPorts
    ) async throws -> LoopbackOAuthCallbackServer {
        for port in preferredPorts {
            do {
                let server = try LoopbackOAuthCallbackServer(
                    expectedState: expectedState,
                    port: port
                )
                try await server.start()
                return server
            } catch {
                continue
            }
        }

        throw LoopbackOAuthCallbackServerError.unableToBind
    }

    private init(expectedState: String, port: UInt16) throws {
        self.expectedState = expectedState

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: "127.0.0.1",
            port: port == 0 ? .any : NWEndpoint.Port(rawValue: port)!
        )
        listener = try NWListener(using: parameters)
    }

    deinit {
        listener.cancel()
    }

    public func waitForCode() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            callbackLock.lock()
            defer { callbackLock.unlock() }

            if let result = callbackState.result {
                continuation.resume(with: result)
                return
            }

            guard !callbackState.isWaiting else {
                continuation.resume(
                    throwing: LoopbackOAuthCallbackServerError.alreadyWaiting
                )
                return
            }

            callbackState.isWaiting = true
            callbackState.continuation = continuation
        }
    }

    public func cancel() {
        listener.cancel()
        finish(.failure(LoopbackOAuthCallbackServerError.cancelled))
    }

    private func start() async throws {
        let readiness = ListenerReadiness()

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                readiness.resolve(.success(()))
            case .failed:
                readiness.resolve(
                    .failure(LoopbackOAuthCallbackServerError.unableToBind)
                )
            case .cancelled:
                readiness.resolve(
                    .failure(LoopbackOAuthCallbackServerError.cancelled)
                )
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.receiveRequest(on: connection)
        }
        listener.start(queue: queue)

        do {
            try await readiness.wait()
        } catch {
            listener.cancel()
            throw error
        }
    }

    private func receiveRequest(on connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, accumulated: Data())
    }

    private func receiveRequest(
        on connection: NWConnection,
        accumulated: Data
    ) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 16_384
        ) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            var request = accumulated
            if let data {
                request.append(data)
            }

            if request.range(of: Data("\r\n\r\n".utf8)) != nil {
                process(request: request, on: connection)
            } else if error != nil || isComplete || request.count >= 32_768 {
                respond(
                    status: 400,
                    body: "Invalid OAuth callback.",
                    on: connection
                )
            } else {
                receiveRequest(on: connection, accumulated: request)
            }
        }
    }

    private func process(request: Data, on connection: NWConnection) {
        guard let text = String(data: request, encoding: .utf8),
              let requestLine = text.components(
                separatedBy: "\r\n"
              ).first
        else {
            respond(
                status: 400,
                body: "Invalid OAuth callback.",
                on: connection
            )
            return
        }

        let components = requestLine.split(
            separator: " ",
            omittingEmptySubsequences: true
        )
        guard components.count == 3,
              components[0] == "GET",
              let url = URL(
                string: String(components[1]),
                relativeTo: callbackURL
              )?.absoluteURL
        else {
            respond(
                status: 400,
                body: "Invalid OAuth callback.",
                on: connection
            )
            return
        }

        do {
            let code = try OAuthCallbackParser.parse(
                url: url,
                expectedState: expectedState
            )
            respond(
                status: 200,
                body: "Authorization complete. You can close this window.",
                on: connection
            ) { [weak self] in
                self?.finish(.success(code))
            }
        } catch {
            respond(
                status: 400,
                body: "Invalid OAuth callback.",
                on: connection
            )
        }
    }

    private func respond(
        status: Int,
        body: String,
        on connection: NWConnection,
        completion: (@Sendable () -> Void)? = nil
    ) {
        let bodyData = Data(body.utf8)
        let reason = status == 200 ? "OK" : "Bad Request"
        let headers = [
            "HTTP/1.1 \(status) \(reason)",
            "Content-Type: text/plain; charset=utf-8",
            "Content-Length: \(bodyData.count)",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        var response = Data(headers.utf8)
        response.append(bodyData)

        connection.send(
            content: response,
            contentContext: .defaultMessage,
            isComplete: true,
            completion: .contentProcessed { _ in
                connection.cancel()
                completion?()
            }
        )
    }

    private func finish(_ result: Result<String, Error>) {
        let continuation: CheckedContinuation<String, Error>?

        callbackLock.lock()
        guard !callbackState.isFinished else {
            callbackLock.unlock()
            return
        }
        callbackState.isFinished = true
        callbackState.result = result
        continuation = callbackState.continuation
        callbackState.continuation = nil
        callbackLock.unlock()

        continuation?.resume(with: result)
        listener.cancel()
    }
}

private final class ListenerReadiness: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Void, Error>?
    private var continuation: CheckedContinuation<Void, Error>?

    func wait() async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            defer { lock.unlock() }

            if let result {
                continuation.resume(with: result)
            } else {
                self.continuation = continuation
            }
        }
    }

    func resolve(_ result: Result<Void, Error>) {
        let continuation: CheckedContinuation<Void, Error>?

        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        continuation?.resume(with: result)
    }
}
