import Foundation
import Testing

@testable import UsageMeterCore

@Suite
struct MiMoUsageAdapterTests {
    @Test
    func adapterSendsItsStoredCookiesToTheTokenPlanEndpoint()
        async throws
    {
        let account = SubscriptionAccount(
            provider: .mimo,
            displayName: "MiMo",
            displayOrder: 0
        )
        let store = MiMoTestCredentialStore()
        try await store.save(
            try #require(
                MiMoWebCredential(
                    cookieHeader: "session=abc; token=def"
                )
            ),
            for: account.id
        )
        let transport = MiMoRecordingTransport(
            response: HTTPResponse(
                data: try usageFixture(
                    named: "mimo-token-plan-usage"
                ),
                statusCode: 200,
                headers: [:]
            )
        )
        let adapter = MiMoUsageAdapter(
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
                == "https://platform.xiaomimimo.com/api/v1/tokenPlan/usage"
        )
        #expect(
            request.value(
                forHTTPHeaderField: "Cookie"
            ) == "session=abc; token=def"
        )
        #expect(
            request.value(
                forHTTPHeaderField: "Accept"
            ) == "application/json"
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
                (302, [:], .reauthenticationRequired),
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
                provider: .mimo,
                displayName: "MiMo",
                displayOrder: 0
            )
            let store = MiMoTestCredentialStore()
            try await store.save(
                try #require(
                    MiMoWebCredential(
                        cookieHeader: "session=abc"
                    )
                ),
                for: account.id
            )
            let adapter = MiMoUsageAdapter(
                credentialStore: store,
                transport: MiMoRecordingTransport(
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
            provider: .mimo,
            displayName: "MiMo",
            displayOrder: 0
        )
        let missingStore = MiMoTestCredentialStore()
        let missingTransport = MiMoRecordingTransport(
            response: HTTPResponse(
                data: Data(),
                statusCode: 200,
                headers: [:]
            )
        )
        let missingAdapter = MiMoUsageAdapter(
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

        let wrongStore = MiMoTestCredentialStore()
        try await wrongStore.save(
            AnotherCredential(token: "wrong"),
            for: account.id
        )
        let wrongTransport = MiMoRecordingTransport(
            response: HTTPResponse(
                data: Data(),
                statusCode: 200,
                headers: [:]
            )
        )
        let wrongAdapter = MiMoUsageAdapter(
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
        let store = MiMoTestCredentialStore()
        let transport = MiMoRecordingTransport(
            response: HTTPResponse(
                data: Data(),
                statusCode: 200,
                headers: [:]
            )
        )
        let adapter = MiMoUsageAdapter(
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
            provider: .mimo,
            displayName: "Work",
            displayOrder: 0
        )
        let second = SubscriptionAccount(
            provider: .mimo,
            displayName: "Personal",
            displayOrder: 1
        )
        let store = MiMoTestCredentialStore()
        let credential = try #require(
            MiMoWebCredential(cookieHeader: "session=abc")
        )
        try await store.save(credential, for: first.id)
        try await store.save(credential, for: second.id)
        let adapter = MiMoUsageAdapter(
            credentialStore: store
        )

        try await adapter.removeAuthentication(
            for: first
        )

        #expect(
            try await store.load(
                MiMoWebCredential.self,
                for: first.id
            ) == nil
        )
        #expect(
            try await store.load(
                MiMoWebCredential.self,
                for: second.id
            ) == credential
        )
    }
}

private actor MiMoRecordingTransport: HTTPTransport {
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

private actor MiMoTestCredentialStore: CredentialStore {
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
