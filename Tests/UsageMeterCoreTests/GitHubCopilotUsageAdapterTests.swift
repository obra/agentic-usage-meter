import Foundation
import Testing

@testable import UsageMeterCore

@Suite
struct GitHubCopilotUsageAdapterTests {
    @Test
    func adapterLoadsItsAccountTokenAndRequestsCopilotUsage()
        async throws
    {
        let account = SubscriptionAccount(
            provider: .githubCopilot,
            displayName: "GitHub",
            authenticatedIdentity: "octocat",
            displayOrder: 0
        )
        let store = CopilotTestCredentialStore()
        try await store.save(
            GitHubCopilotCredential(
                accessToken: "github-token",
                userID: "42",
                login: "octocat"
            ),
            for: account.id
        )
        let transport = CopilotUsageRecordingTransport(
            response: HTTPResponse(
                data: try usageFixture(
                    named: "github-copilot-usage"
                ),
                statusCode: 200,
                headers: [:]
            )
        )
        let adapter = GitHubCopilotUsageAdapter(
            credentialStore: store,
            transport: transport
        )

        let snapshot = try await adapter.fetchUsage(
            for: account,
            now: Date(
                timeIntervalSince1970:
                    1_785_000_000
            )
        )

        #expect(snapshot.accountID == account.id)
        #expect(snapshot.windows.count == 2)
        let request = try #require(
            await transport.lastRequest
        )
        #expect(
            request.url?.absoluteString
                == "https://api.github.com/copilot_internal/user"
        )
        #expect(request.httpMethod == "GET")
        #expect(
            request.value(
                forHTTPHeaderField: "Authorization"
            ) == "token github-token"
        )
        #expect(
            request.value(
                forHTTPHeaderField: "Editor-Version"
            ) == "vscode/1.96.2"
        )
        #expect(
            request.value(
                forHTTPHeaderField:
                    "X-GitHub-Api-Version"
            ) == "2025-04-01"
        )
    }

    @Test
    func responseForAnotherGitHubUserIsRejected()
        async throws
    {
        let account = SubscriptionAccount(
            provider: .githubCopilot,
            displayName: "GitHub",
            displayOrder: 0
        )
        let store = CopilotTestCredentialStore()
        try await store.save(
            GitHubCopilotCredential(
                accessToken: "github-token",
                userID: "42",
                login: "octocat"
            ),
            for: account.id
        )
        let response = HTTPResponse(
            data: Data(
                """
                {
                  "copilot_plan": "individual_pro",
                  "user_id": 99,
                  "quota_snapshots": {}
                }
                """.utf8
            ),
            statusCode: 200,
            headers: [:]
        )
        let adapter = GitHubCopilotUsageAdapter(
            credentialStore: store,
            transport: CopilotUsageRecordingTransport(
                response: response
            )
        )

        await #expect(
            throws:
                ProviderClientError.credentialMismatch
        ) {
            _ = try await adapter.fetchUsage(
                for: account,
                now: Date()
            )
        }
    }

    @Test
    func statusCodesMapToProviderFailures()
        async throws
    {
        let now = Date(
            timeIntervalSince1970: 1_785_000_000
        )
        let cases: [(Int, [String: String], ProviderClientError)] =
            [
                (401, [:], .reauthenticationRequired),
                (403, [:], .reauthenticationRequired),
                (
                    429,
                    ["Retry-After": "600"],
                    .retryAfter(
                        now.addingTimeInterval(600)
                    )
                ),
                (500, [:], .temporaryFailure),
            ]

        for (statusCode, headers, expected) in cases {
            let account = SubscriptionAccount(
                provider: .githubCopilot,
                displayName: "GitHub",
                displayOrder: 0
            )
            let store = CopilotTestCredentialStore()
            try await store.save(
                GitHubCopilotCredential(
                    accessToken: "github-token",
                    userID: "42",
                    login: "octocat"
                ),
                for: account.id
            )
            let adapter =
                GitHubCopilotUsageAdapter(
                    credentialStore: store,
                    transport:
                        CopilotUsageRecordingTransport(
                            response: HTTPResponse(
                                data: Data(),
                                statusCode: statusCode,
                                headers: headers
                            )
                        )
                )

            await #expect(throws: expected) {
                _ = try await adapter.fetchUsage(
                    for: account,
                    now: now
                )
            }
        }
    }

    @Test
    func removingAuthenticationDeletesOnlyThatAccount()
        async throws
    {
        let first = SubscriptionAccount(
            provider: .githubCopilot,
            displayName: "Work",
            displayOrder: 0
        )
        let second = SubscriptionAccount(
            provider: .githubCopilot,
            displayName: "Personal",
            displayOrder: 1
        )
        let store = CopilotTestCredentialStore()
        let credential = GitHubCopilotCredential(
            accessToken: "github-token",
            userID: "42",
            login: "octocat"
        )
        try await store.save(
            credential,
            for: first.id
        )
        try await store.save(
            credential,
            for: second.id
        )
        let adapter = GitHubCopilotUsageAdapter(
            credentialStore: store
        )

        try await adapter.removeAuthentication(
            for: first
        )

        #expect(
            try await store.load(
                GitHubCopilotCredential.self,
                for: first.id
            ) == nil
        )
        #expect(
            try await store.load(
                GitHubCopilotCredential.self,
                for: second.id
            ) == credential
        )
    }
}

private actor CopilotUsageRecordingTransport:
    HTTPTransport
{
    private(set) var lastRequest: URLRequest?
    let response: HTTPResponse

    init(response: HTTPResponse) {
        self.response = response
    }

    func send(_ request: URLRequest) -> HTTPResponse {
        lastRequest = request
        return response
    }
}

private actor CopilotTestCredentialStore:
    CredentialStore
{
    private var dataByAccountID: [UUID: Data] = [:]

    func saveData(
        _ data: Data,
        for accountID: UUID
    ) {
        dataByAccountID[accountID] = data
    }

    func loadData(
        for accountID: UUID
    ) -> Data? {
        dataByAccountID[accountID]
    }

    func delete(for accountID: UUID) {
        dataByAccountID.removeValue(
            forKey: accountID
        )
    }
}
