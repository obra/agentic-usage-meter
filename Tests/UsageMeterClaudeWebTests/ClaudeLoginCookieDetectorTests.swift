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

    @Test
    func capturesOnlyClaudeCookiesNeededForImmediateValidation() throws {
        let cookies = [
            try makeLoginCookie(
                name: "unrelated",
                value: "ignore",
                domain: ".claude.ai"
            ),
            try makeLoginCookie(
                name: "sessionKey",
                value: "session",
                domain: ".claude.ai"
            ),
            try makeLoginCookie(
                name: "cf_clearance",
                value: "clearance",
                domain: ".claude.ai"
            ),
            try makeLoginCookie(
                name: "__cf_bm",
                value: "challenge",
                domain: ".example.com"
            )
        ]

        let captured = try #require(
            ClaudeLoginCookieDetector.apiCookies(in: cookies)
        )

        #expect(
            captured.map(\.name)
                == ["sessionKey", "cf_clearance"]
        )
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
