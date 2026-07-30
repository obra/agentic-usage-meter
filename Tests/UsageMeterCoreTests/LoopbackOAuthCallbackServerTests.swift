import Foundation
import Testing
@testable import UsageMeterCore

@Suite(.serialized)
struct LoopbackOAuthCallbackServerTests {
    @Test
    func receivesAuthorizationCodeOverLoopbackHTTP() async throws {
        let server = try await LoopbackOAuthCallbackServer.start(
            expectedState: "expected-state",
            preferredPorts: [0]
        )
        defer { server.cancel() }

        let callbackURL = try callbackURL(
            basedOn: server.callbackURL,
            code: "authorization-code",
            state: "expected-state"
        )
        let waiting = Task {
            try await server.waitForCode()
        }

        let (_, response) = try await URLSession.shared.data(from: callbackURL)
        let httpResponse = try #require(response as? HTTPURLResponse)

        #expect(httpResponse.statusCode == 200)
        #expect(try await waiting.value == "authorization-code")
    }

    @Test
    func invalidStateDoesNotEndTheLoginAttempt() async throws {
        let server = try await LoopbackOAuthCallbackServer.start(
            expectedState: "expected-state",
            preferredPorts: [0]
        )
        defer { server.cancel() }

        let invalidURL = try callbackURL(
            basedOn: server.callbackURL,
            code: "untrusted-code",
            state: "wrong-state"
        )
        let validURL = try callbackURL(
            basedOn: server.callbackURL,
            code: "trusted-code",
            state: "expected-state"
        )
        let waiting = Task {
            try await server.waitForCode()
        }

        let (_, invalidResponse) = try await URLSession.shared.data(from: invalidURL)
        #expect(
            try #require(invalidResponse as? HTTPURLResponse).statusCode == 400
        )

        let (_, validResponse) = try await URLSession.shared.data(from: validURL)
        #expect(
            try #require(validResponse as? HTTPURLResponse).statusCode == 200
        )
        #expect(try await waiting.value == "trusted-code")
    }

    @Test
    func fallsBackWhenPreferredPortIsOccupied() async throws {
        let occupyingServer = try await LoopbackOAuthCallbackServer.start(
            expectedState: "first-state",
            preferredPorts: [0]
        )
        defer { occupyingServer.cancel() }
        let occupiedPort = try #require(occupyingServer.callbackURL.port)

        let fallbackServer = try await LoopbackOAuthCallbackServer.start(
            expectedState: "second-state",
            preferredPorts: [UInt16(occupiedPort), 0]
        )
        defer { fallbackServer.cancel() }

        #expect(fallbackServer.callbackURL.host == "127.0.0.1")
        #expect(fallbackServer.callbackURL.port != occupiedPort)
    }

    private func callbackURL(
        basedOn baseURL: URL,
        code: String,
        state: String
    ) throws -> URL {
        var components = try #require(
            URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        )
        components.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "state", value: state)
        ]
        return try #require(components.url)
    }
}
