import Foundation
import Testing

@testable import UsageMeterCore

@Suite
struct SuperGrokUsageAdapterTests {
    @Test
    func adapterUsesCurrentGrokBuildBillingContract()
        async throws
    {
        let account = SubscriptionAccount(
            provider: .superGrok,
            displayName: "Grok",
            displayOrder: 0
        )
        let store = SuperGrokTestCredentialStore()
        try await store.save(
            SuperGrokCredential(
                accessToken: "account-token",
                email: "user@example.com",
                teamID: "team-1",
                userID: "user-1",
                authMode: "oidc",
                expiresAt: nil
            ),
            for: account.id
        )
        let transport = SuperGrokRecordingTransport(
            response: HTTPResponse(
                data: currentUsageResponse(),
                statusCode: 200,
                headers: [:]
            )
        )
        let adapter = SuperGrokUsageAdapter(
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
        let request = try #require(
            await transport.lastRequest
        )
        #expect(
            request.url?.absoluteString
                == "https://cli-chat-proxy.grok.com/v1/billing?format=credits"
        )
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
        #expect(
            request.value(
                forHTTPHeaderField: "Authorization"
            ) == "Bearer account-token"
        )
        #expect(
            request.value(
                forHTTPHeaderField: "X-XAI-Token-Auth"
            ) == "xai-grok-cli"
        )
        #expect(
            request.value(
                forHTTPHeaderField: "x-userid"
            ) == "user-1"
        )
        #expect(
            request.value(
                forHTTPHeaderField:
                    "x-grok-client-version"
            ) == "0.2.118"
        )
        #expect(
            request.value(
                forHTTPHeaderField:
                    "x-grok-client-mode"
            ) == "headless"
        )
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
                provider: .superGrok,
                displayName: "Grok",
                displayOrder: 0
            )
            let store =
                SuperGrokTestCredentialStore()
            try await store.save(
                SuperGrokCredential(
                    accessToken: "token",
                    email: nil,
                    teamID: nil,
                    userID: "user",
                    authMode: "oidc",
                    expiresAt: nil
                ),
                for: account.id
            )
            let adapter = SuperGrokUsageAdapter(
                credentialStore: store,
                transport:
                    SuperGrokRecordingTransport(
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
    func wrongTypedCredentialDoesNotSendARequest()
        async throws
    {
        struct WrongCredential:
            Codable,
            Sendable
        {
            let token: String
        }

        let account = SubscriptionAccount(
            provider: .superGrok,
            displayName: "Grok",
            displayOrder: 0
        )
        let store = SuperGrokTestCredentialStore()
        try await store.save(
            WrongCredential(token: "wrong"),
            for: account.id
        )
        let transport = SuperGrokRecordingTransport(
            response: HTTPResponse(
                data: currentUsageResponse(),
                statusCode: 200,
                headers: [:]
            )
        )
        let adapter = SuperGrokUsageAdapter(
            credentialStore: store,
            transport: transport
        )

        await #expect(
            throws:
                ProviderClientError
                .credentialMismatch
        ) {
            _ = try await adapter.fetchUsage(
                for: account,
                now: Date()
            )
        }
        #expect(await transport.lastRequest == nil)
    }
}

private func currentUsageResponse() -> Data {
    Data(
        #"""
        {
          "config": {
            "creditUsagePercent": 20,
            "currentPeriod": {
              "type": "USAGE_PERIOD_TYPE_WEEKLY",
              "start": "2026-07-30T00:00:00Z",
              "end": "2026-08-06T00:00:00Z"
            },
            "prepaidBalance": { "val": 0 },
            "isUnifiedBillingUser": true
          },
          "onDemandEnabled": true,
          "subscriptionTier": "SuperGrok"
        }
        """#.utf8
    )
}

private actor SuperGrokRecordingTransport:
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

private actor SuperGrokTestCredentialStore:
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
