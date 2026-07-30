import Foundation
import Testing

@testable import UsageMeterCore

@Suite
struct MiniMaxUsageAdapterTests {
    @Test
    func adapterLoadsItsTypedKeyAndRequestsCodingPlanRemains()
        async throws
    {
        let account = SubscriptionAccount(
            provider: .minimax,
            displayName: "MiniMax",
            displayOrder: 0
        )
        let store = MiniMaxTestCredentialStore()
        try await store.save(
            try #require(
                MiniMaxCredential(apiKey: "plan-key")
            ),
            for: account.id
        )
        let transport = MiniMaxRecordingTransport(
            response: HTTPResponse(
                data: try usageFixture(
                    named: "minimax-usage"
                ),
                statusCode: 200,
                headers: [:]
            )
        )
        let adapter = MiniMaxUsageAdapter(
            credentialStore: store,
            transport: transport
        )

        let snapshot = try await adapter.fetchUsage(
            for: account,
            now: Date(
                timeIntervalSince1970: 1_774_587_600
            )
        )

        #expect(snapshot.accountID == account.id)
        let request = try #require(
            await transport.lastRequest
        )
        #expect(request.httpMethod == "GET")
        #expect(
            request.url?.absoluteString
                == "https://api.minimax.io/v1/api/openplatform/coding_plan/remains"
        )
        #expect(
            request.value(
                forHTTPHeaderField: "Authorization"
            ) == "Bearer plan-key"
        )
    }

    @Test
    func statusCodesMapToProviderFailures() async throws {
        let now = Date(
            timeIntervalSince1970: 1_774_587_600
        )
        let cases:
            [(Int, [String: String], ProviderClientError)] =
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

        for (statusCode, headers, expectedError) in cases {
            let account = SubscriptionAccount(
                provider: .minimax,
                displayName: "MiniMax",
                displayOrder: 0
            )
            let store = MiniMaxTestCredentialStore()
            try await store.save(
                try #require(
                    MiniMaxCredential(apiKey: "plan-key")
                ),
                for: account.id
            )
            let adapter = MiniMaxUsageAdapter(
                credentialStore: store,
                transport: MiniMaxRecordingTransport(
                    response: HTTPResponse(
                        data: Data(),
                        statusCode: statusCode,
                        headers: headers
                    )
                )
            )

            await #expect(throws: expectedError) {
                _ = try await adapter.fetchUsage(
                    for: account,
                    now: now
                )
            }
        }
    }

    @Test
    func missingOrWrongTypedCredentialDoesNotSendARequest()
        async throws
    {
        struct AnotherCredential: Codable, Sendable {
            let token: String
        }

        let account = SubscriptionAccount(
            provider: .minimax,
            displayName: "MiniMax",
            displayOrder: 0
        )
        let missingStore = MiniMaxTestCredentialStore()
        let missingTransport = MiniMaxRecordingTransport(
            response: HTTPResponse(
                data: Data(),
                statusCode: 200,
                headers: [:]
            )
        )
        let missingAdapter = MiniMaxUsageAdapter(
            credentialStore: missingStore,
            transport: missingTransport
        )

        await #expect(
            throws:
                ProviderClientError.reauthenticationRequired
        ) {
            _ = try await missingAdapter.fetchUsage(
                for: account,
                now: Date()
            )
        }
        #expect(await missingTransport.lastRequest == nil)

        let wrongStore = MiniMaxTestCredentialStore()
        try await wrongStore.save(
            AnotherCredential(token: "wrong"),
            for: account.id
        )
        let wrongTransport = MiniMaxRecordingTransport(
            response: HTTPResponse(
                data: Data(),
                statusCode: 200,
                headers: [:]
            )
        )
        let wrongAdapter = MiniMaxUsageAdapter(
            credentialStore: wrongStore,
            transport: wrongTransport
        )

        await #expect(
            throws: ProviderClientError.credentialMismatch
        ) {
            _ = try await wrongAdapter.fetchUsage(
                for: account,
                now: Date()
            )
        }
        #expect(await wrongTransport.lastRequest == nil)
    }

    @Test
    func wrongProviderDoesNotLoadCredentialsOrSendARequest()
        async
    {
        let store = MiniMaxTestCredentialStore()
        let transport = MiniMaxRecordingTransport(
            response: HTTPResponse(
                data: Data(),
                statusCode: 200,
                headers: [:]
            )
        )
        let adapter = MiniMaxUsageAdapter(
            credentialStore: store,
            transport: transport
        )
        let account = SubscriptionAccount(
            provider: .kimi,
            displayName: "Kimi",
            displayOrder: 0
        )

        await #expect(
            throws: ProviderClientError.credentialMismatch
        ) {
            _ = try await adapter.fetchUsage(
                for: account,
                now: Date()
            )
        }

        #expect(await store.loadCount == 0)
        #expect(await transport.lastRequest == nil)
    }

    @Test
    func removingAuthenticationDeletesOnlyThatAccount()
        async throws
    {
        let first = SubscriptionAccount(
            provider: .minimax,
            displayName: "Work",
            displayOrder: 0
        )
        let second = SubscriptionAccount(
            provider: .minimax,
            displayName: "Personal",
            displayOrder: 1
        )
        let store = MiniMaxTestCredentialStore()
        let credential = try #require(
            MiniMaxCredential(apiKey: "plan-key")
        )
        try await store.save(credential, for: first.id)
        try await store.save(credential, for: second.id)
        let adapter = MiniMaxUsageAdapter(
            credentialStore: store
        )

        try await adapter.removeAuthentication(
            for: first
        )

        #expect(
            try await store.load(
                MiniMaxCredential.self,
                for: first.id
            ) == nil
        )
        #expect(
            try await store.load(
                MiniMaxCredential.self,
                for: second.id
            ) == credential
        )
    }
}

private actor MiniMaxRecordingTransport: HTTPTransport {
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

private actor MiniMaxTestCredentialStore: CredentialStore {
    private var dataByAccountID: [UUID: Data] = [:]
    private(set) var loadCount = 0

    func saveData(
        _ data: Data,
        for accountID: UUID
    ) {
        dataByAccountID[accountID] = data
    }

    func loadData(for accountID: UUID) -> Data? {
        loadCount += 1
        return dataByAccountID[accountID]
    }

    func delete(for accountID: UUID) {
        dataByAccountID.removeValue(forKey: accountID)
    }
}
