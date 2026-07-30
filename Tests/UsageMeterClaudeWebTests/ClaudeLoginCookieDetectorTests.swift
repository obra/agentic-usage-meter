import Foundation
import Testing
@testable import UsageMeterClaudeWeb

@Suite
struct ClaudeLoginCookieDetectorTests {
    @Test
    func recognizesOnlyClaudeSessionCookies() throws {
        let cookies = [
            try makeLoginCookie(
                name: "unrelated",
                value: "x",
                domain: ".claude.ai"
            ),
            try makeLoginCookie(
                name: "sessionKey",
                value: "secret",
                domain: ".claude.ai"
            )
        ]

        #expect(ClaudeLoginCookieDetector.hasSession(in: cookies))
    }

    @Test
    func rejectsSessionCookieFromAnotherDomain() throws {
        let cookies = [
            try makeLoginCookie(
                name: "sessionKey",
                value: "secret",
                domain: ".example.com"
            )
        ]

        #expect(!ClaudeLoginCookieDetector.hasSession(in: cookies))
    }

    @Test
    func rejectsEmptyClaudeSessionCookie() throws {
        let cookies = [
            try makeLoginCookie(
                name: "sessionKey",
                value: "",
                domain: "claude.ai"
            )
        ]

        #expect(!ClaudeLoginCookieDetector.hasSession(in: cookies))
    }
}

private func makeLoginCookie(
    name: String,
    value: String,
    domain: String
) throws -> HTTPCookie {
    try #require(
        HTTPCookie(
            properties: [
                .name: name,
                .value: value,
                .domain: domain,
                .path: "/",
                .secure: "TRUE"
            ]
        )
    )
}
