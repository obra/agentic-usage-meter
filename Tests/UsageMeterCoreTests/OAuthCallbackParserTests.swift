import Foundation
import Testing
@testable import UsageMeterCore

@Suite
struct OAuthCallbackParserTests {
    @Test
    func returnsAuthorizationCodeForMatchingCallback() throws {
        let url = try #require(
            URL(string: "http://127.0.0.1:1455/auth/callback?code=authorization-code&state=expected-state")
        )

        let code = try OAuthCallbackParser.parse(
            url: url,
            expectedState: "expected-state"
        )

        #expect(code == "authorization-code")
    }

    @Test
    func rejectsCallbackForAnotherPath() throws {
        let url = try #require(
            URL(string: "http://127.0.0.1:1455/not-the-callback?code=secret-code&state=expected-state")
        )

        #expect(throws: OAuthCallbackError.invalidPath) {
            try OAuthCallbackParser.parse(
                url: url,
                expectedState: "expected-state"
            )
        }
    }

    @Test
    func rejectsCallbackWithWrongOrMissingState() throws {
        let wrongStateURL = try #require(
            URL(string: "http://127.0.0.1:1455/auth/callback?code=secret-code&state=wrong-state")
        )
        let missingStateURL = try #require(
            URL(string: "http://127.0.0.1:1455/auth/callback?code=secret-code")
        )

        #expect(throws: OAuthCallbackError.stateMismatch) {
            try OAuthCallbackParser.parse(
                url: wrongStateURL,
                expectedState: "expected-state"
            )
        }
        #expect(throws: OAuthCallbackError.stateMismatch) {
            try OAuthCallbackParser.parse(
                url: missingStateURL,
                expectedState: "expected-state"
            )
        }
    }

    @Test
    func rejectsCallbackWithMissingOrEmptyCode() throws {
        let missingCodeURL = try #require(
            URL(string: "http://127.0.0.1:1455/auth/callback?state=expected-state")
        )
        let emptyCodeURL = try #require(
            URL(string: "http://127.0.0.1:1455/auth/callback?code=&state=expected-state")
        )

        #expect(throws: OAuthCallbackError.missingCode) {
            try OAuthCallbackParser.parse(
                url: missingCodeURL,
                expectedState: "expected-state"
            )
        }
        #expect(throws: OAuthCallbackError.missingCode) {
            try OAuthCallbackParser.parse(
                url: emptyCodeURL,
                expectedState: "expected-state"
            )
        }
    }

    @Test
    func errorDescriptionsDoNotIncludeCallbackSecrets() throws {
        let state = "private-state-value"
        let code = "private-authorization-code"
        let url = try #require(
            URL(string: "http://127.0.0.1:1455/wrong?code=\(code)&state=\(state)")
        )

        do {
            _ = try OAuthCallbackParser.parse(url: url, expectedState: state)
            Issue.record("Expected callback parsing to fail")
        } catch {
            let description = String(describing: error)
            #expect(!description.contains(state))
            #expect(!description.contains(code))
        }
    }
}
