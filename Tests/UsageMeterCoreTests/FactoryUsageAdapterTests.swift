import Foundation
import Testing

@testable import UsageMeterCore

@Suite
struct FactoryUsageAdapterTests {
    @Test
    func adapterLoadsItsTypedKeyAndRequestsBillingLimits()
        async throws
    {
        let account = SubscriptionAccount(
            provider: .factory,
            displayName: "Factory",
            displayOrder: 0
        )
        let store = FactoryTestCredentialStore()
        try await store.save(
            try #require(
                FactoryCredential(apiKey: "factory-key")
            ),
            for: account.id
        )
        let transport = FactoryRecordingTransport(
            response: HTTPResponse(
                data: try usageFixture(
                    named: "factory-limits"
                ),
                statusCode: 200,
                headers: [:]
            )
        )
        let adapter = FactoryUsageAdapter(
            credentialStore: store,
            transport: transport
        )

        let snapshot = try await adapter.fetchUsage(
            for: account,
            now: Date(
                timeIntervalSince1970: 1_775_088_000
            )
        )

        #expect(snapshot.accountID == account.id)
        let request = try #require(
            await transport.lastRequest
        )
        #expect(request.httpMethod == "GET")
        #expect(
            request.url?.absoluteString
                == "https://api.factory.ai/api/billing/limits"
        )
        #expect(
            request.value(
                forHTTPHeaderField: "Authorization"
            ) == "Bearer factory-key"
        )
    }

    @Test
    func statusCodesMapToProviderFailures() async throws {
        let now = Date(
            timeIntervalSince1970: 1_775_088_000
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

        for (statusCode, headers, expectedError) in cases {
            let account = SubscriptionAccount(
                provider: .factory,
                displayName: "Factory",
                displayOrder: 0
            )
            let store = FactoryTestCredentialStore()
            try await store.save(
                try #require(
                    FactoryCredential(apiKey: "factory-key")
                ),
                for: account.id
            )
            let adapter = FactoryUsageAdapter(
                credentialStore: store,
                transport: FactoryRecordingTransport(
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
            provider: .factory,
            displayName: "Factory",
            displayOrder: 0
        )
        let missingStore = FactoryTestCredentialStore()
        let missingTransport = FactoryRecordingTransport(
            response: HTTPResponse(
                data: Data(),
                statusCode: 200,
                headers: [:]
            )
        )
        let missingAdapter = FactoryUsageAdapter(
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

        let wrongStore = FactoryTestCredentialStore()
        try await wrongStore.save(
            AnotherCredential(token: "wrong"),
            for: account.id
        )
        let wrongTransport = FactoryRecordingTransport(
            response: HTTPResponse(
                data: Data(),
                statusCode: 200,
                headers: [:]
            )
        )
        let wrongAdapter = FactoryUsageAdapter(
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
        let store = FactoryTestCredentialStore()
        let transport = FactoryRecordingTransport(
            response: HTTPResponse(
                data: Data(),
                statusCode: 200,
                headers: [:]
            )
        )
        let adapter = FactoryUsageAdapter(
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
            provider: .factory,
            displayName: "Work",
            displayOrder: 0
        )
        let second = SubscriptionAccount(
            provider: .factory,
            displayName: "Personal",
            displayOrder: 1
        )
        let store = FactoryTestCredentialStore()
        let credential = try #require(
            FactoryCredential(apiKey: "factory-key")
        )
        try await store.save(credential, for: first.id)
        try await store.save(credential, for: second.id)
        let adapter = FactoryUsageAdapter(
            credentialStore: store
        )

        try await adapter.removeAuthentication(
            for: first
        )

        #expect(
            try await store.load(
                FactoryCredential.self,
                for: first.id
            ) == nil
        )
        #expect(
            try await store.load(
                FactoryCredential.self,
                for: second.id
            ) == credential
        )
    }

    @Test
    func credentialRejectsBlankKeys() {
        #expect(FactoryCredential(apiKey: " \n ") == nil)
        #expect(
            FactoryCredential(apiKey: " key ")?
                .apiKey == "key"
        )
    }
}

private actor FactoryRecordingTransport: HTTPTransport {
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

private actor FactoryTestCredentialStore: CredentialStore {
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
