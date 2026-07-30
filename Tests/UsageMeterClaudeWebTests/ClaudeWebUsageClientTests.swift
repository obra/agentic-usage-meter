import Foundation
import Testing
@testable import UsageMeterClaudeWeb
import UsageMeterCore

@MainActor
@Suite
struct ClaudeWebUsageClientTests {
    private let firstProfile = UUID(
        uuidString: "20000000-0000-0000-0000-000000000001"
    )!
    private let secondProfile = UUID(
        uuidString: "20000000-0000-0000-0000-000000000002"
    )!
    private let organizationID = UUID(
        uuidString: "10000000-0000-0000-0000-000000000001"
    )!

    @Test
    func organizationsUseTheSelectedProfilesBrowserCookies() async throws {
        let transport = RecordingHTTPTransport(
            response: HTTPResponse(
                data: try fixture(named: "claude-organizations"),
                statusCode: 200,
                headers: [:]
            )
        )
        let cookieSource = TestCookieSource(
            cookiesByProfile: [
                firstProfile: [
                    cookie(
                        name: "sessionKey",
                        value: "first-session"
                    ),
                    cookie(
                        name: "cf_clearance",
                        value: "first-clearance"
                    ),
                    cookie(name: "__cf_bm", value: "first-bm")
                ],
                secondProfile: [
                    cookie(
                        name: "sessionKey",
                        value: "second-session"
                    )
                ]
            ]
        )
        let client = ClaudeWebUsageClient(
            transport: transport,
            cookieSource: cookieSource
        )

        let organizations = try await client.organizations(
            profileID: firstProfile
        )

        #expect(
            organizations == [
                ClaudeOrganization(
                    id: organizationID,
                    name: "Personal",
                    capabilities: ["chat", "claude_max"]
                )
            ]
        )
        let request = try #require(await transport.lastRequest)
        #expect(
            request.url?.absoluteString
                == "https://claude.ai/api/organizations"
        )
        #expect(
            request.value(forHTTPHeaderField: "Cookie")
                == [
                    "sessionKey=first-session",
                    "cf_clearance=first-clearance",
                    "__cf_bm=first-bm"
                ].joined(separator: "; ")
        )
        #expect(
            request.value(forHTTPHeaderField: "Accept")
                == "application/json"
        )
        #expect(
            request.value(forHTTPHeaderField: "Origin")
                == "https://claude.ai"
        )
        #expect(
            request.value(forHTTPHeaderField: "Referer")
                == "https://claude.ai"
        )
    }

    @Test
    func usageUsesOnlyTheSelectedProfileAndNormalizesWindows() async throws {
        let transport = RecordingHTTPTransport(
            response: HTTPResponse(
                data: try fixture(named: "claude-usage"),
                statusCode: 200,
                headers: [:]
            )
        )
        let cookieSource = TestCookieSource(
            cookiesByProfile: [
                firstProfile: [
                    cookie(name: "sessionKey", value: "first-session")
                ],
                secondProfile: [
                    cookie(name: "sessionKey", value: "second-session"),
                    cookie(name: "__cf_bm", value: "second-bm")
                ]
            ]
        )
        let client = ClaudeWebUsageClient(
            transport: transport,
            cookieSource: cookieSource
        )
        let accountID = UUID()
        let fetchedAt = Date(timeIntervalSince1970: 2_000_000_000)

        let snapshot = try await client.fetchUsage(
            accountID: accountID,
            profileID: secondProfile,
            organizationID: organizationID,
            now: fetchedAt
        )

        #expect(snapshot.accountID == accountID)
        #expect(snapshot.fetchedAt == fetchedAt)
        #expect(snapshot.windows.map(\.kind) == [.short, .weekly])
        #expect(snapshot.windows.map(\.duration) == [18_000, 604_800])
        let request = try #require(await transport.lastRequest)
        #expect(
            request.url?.absoluteString
                == "https://claude.ai/api/organizations/"
                + "\(organizationID.uuidString.lowercased())/usage"
        )
        #expect(
            request.value(forHTTPHeaderField: "Cookie")
                == "sessionKey=second-session; __cf_bm=second-bm"
        )
    }

    @Test
    func missingSessionCookieDoesNotSendARequest() async {
        let transport = RecordingHTTPTransport(
            response: HTTPResponse(
                data: Data(),
                statusCode: 200,
                headers: [:]
            )
        )
        let client = ClaudeWebUsageClient(
            transport: transport,
            cookieSource: TestCookieSource(cookiesByProfile: [:])
        )

        await #expect(throws: ProviderClientError.reauthenticationRequired) {
            _ = try await client.organizations(profileID: firstProfile)
        }
        #expect(await transport.lastRequest == nil)
    }

    @Test
    func authenticationStatusStopsTheAccount() async {
        for statusCode in [401, 403] {
            let transport = RecordingHTTPTransport(
                response: HTTPResponse(
                    data: Data(),
                    statusCode: statusCode,
                    headers: [:]
                )
            )
            let client = ClaudeWebUsageClient(
                transport: transport,
                cookieSource: TestCookieSource(
                    cookiesByProfile: [
                        firstProfile: [
                            cookie(
                                name: "sessionKey",
                                value: "session"
                            )
                        ]
                    ]
                )
            )

            await #expect(
                throws: ProviderClientError.reauthenticationRequired
            ) {
                _ = try await client.organizations(profileID: firstProfile)
            }
        }
    }

    @Test
    func retryAfterIsPreserved() async {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let transport = RecordingHTTPTransport(
            response: HTTPResponse(
                data: Data(),
                statusCode: 429,
                headers: ["Retry-After": "900"]
            )
        )
        let client = ClaudeWebUsageClient(
            transport: transport,
            cookieSource: TestCookieSource(
                cookiesByProfile: [
                    firstProfile: [
                        cookie(name: "sessionKey", value: "session")
                    ]
                ]
            )
        )

        await #expect(
            throws: ProviderClientError.retryAfter(
                now.addingTimeInterval(900)
            )
        ) {
            _ = try await client.fetchUsage(
                accountID: UUID(),
                profileID: firstProfile,
                organizationID: organizationID,
                now: now
            )
        }
    }

    @Test
    func malformedOrganizationIsRejected() async {
        let transport = RecordingHTTPTransport(
            response: HTTPResponse(
                data: Data(
                    #"[{"uuid":"not-a-uuid","name":"Broken","capabilities":[]}]"#
                        .utf8
                ),
                statusCode: 200,
                headers: [:]
            )
        )
        let client = ClaudeWebUsageClient(
            transport: transport,
            cookieSource: TestCookieSource(
                cookiesByProfile: [
                    firstProfile: [
                        cookie(name: "sessionKey", value: "session")
                    ]
                ]
            )
        )

        await #expect(throws: ProviderClientError.unsupportedResponse) {
            _ = try await client.organizations(profileID: firstProfile)
        }
    }
}

@MainActor
private final class TestCookieSource: ClaudeWebCookieSource {
    private let cookiesByProfile: [UUID: [HTTPCookie]]

    init(cookiesByProfile: [UUID: [HTTPCookie]]) {
        self.cookiesByProfile = cookiesByProfile
    }

    func cookies(for url: URL, profileID: UUID) async -> [HTTPCookie] {
        cookiesByProfile[profileID] ?? []
    }
}

private actor RecordingHTTPTransport: HTTPTransport {
    private let response: HTTPResponse
    private(set) var lastRequest: URLRequest?

    init(response: HTTPResponse) {
        self.response = response
    }

    func send(_ request: URLRequest) -> HTTPResponse {
        lastRequest = request
        return response
    }
}

private func cookie(name: String, value: String) -> HTTPCookie {
    HTTPCookie(
        properties: [
            .domain: ".claude.ai",
            .path: "/",
            .name: name,
            .value: value,
            .secure: "TRUE"
        ]
    )!
}

private func fixture(named name: String) throws -> Data {
    let url = try #require(
        Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures"
        )
    )
    return try Data(contentsOf: url)
}
