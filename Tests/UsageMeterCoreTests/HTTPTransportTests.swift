import Foundation
import Testing
@testable import UsageMeterCore

@Suite(.serialized)
struct HTTPTransportTests {
    @Test
    func transportReturnsStatusHeadersAndData() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let body = Data("{}".utf8)
        TestURLProtocol.setResponse(
            statusCode: 200,
            headers: ["Retry-After": "900"],
            body: body
        )
        let transport = URLSessionHTTPTransport(session: session)
        let request = URLRequest(
            url: try #require(URL(string: "https://example.test/usage"))
        )

        let response = try await transport.send(request)

        #expect(response.statusCode == 200)
        #expect(response.header(named: "Retry-After") == "900")
        #expect(response.header(named: "retry-after") == "900")
        #expect(response.data == body)
    }
}

private final class TestURLProtocol: URLProtocol, @unchecked Sendable {
    private struct Stub {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var stub: Stub?

    static func setResponse(
        statusCode: Int,
        headers: [String: String],
        body: Data
    ) {
        lock.lock()
        stub = Stub(statusCode: statusCode, headers: headers, body: body)
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        let stub = Self.stub
        Self.lock.unlock()

        guard
            let stub,
            let url = request.url,
            let response = HTTPURLResponse(
                url: url,
                statusCode: stub.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: stub.headers
            )
        else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.cannotParseResponse)
            )
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
