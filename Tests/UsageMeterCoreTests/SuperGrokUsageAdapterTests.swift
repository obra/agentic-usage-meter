import Foundation
import Testing

@testable import UsageMeterCore

@Suite
struct SuperGrokUsageAdapterTests {
    @Test
    func adapterCanRetryPersistedAuthenticationFailure() {
        let adapter = SuperGrokUsageAdapter(
            credentialStore:
                SuperGrokTestCredentialStore()
        )

        #expect(
            adapter
                .canRecoverAuthenticationWithoutReconnect
        )
    }

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

    @Test
    func credentialNearExpiryRefreshesBeforeBillingAndPersistsRotation()
        async throws
    {
        let now = Date(
            timeIntervalSince1970: 1_785_000_000
        )
        let account = SubscriptionAccount(
            provider: .superGrok,
            displayName: "Grok",
            displayOrder: 0
        )
        let store = SuperGrokTestCredentialStore()
        try await store.save(
            refreshableCredential(
                accessToken: "near-expiry-token",
                refreshToken: "old-refresh",
                expiresAt:
                    now.addingTimeInterval(4 * 60)
            ),
            for: account.id
        )
        let transport = SuperGrokSequencedTransport(
            responses: [
                discoveryResponse(),
                try tokenResponse(
                    accessToken: "fresh-token",
                    refreshToken: "new-refresh"
                ),
                HTTPResponse(
                    data: currentUsageResponse(),
                    statusCode: 200,
                    headers: [:]
                ),
            ]
        )
        let adapter = SuperGrokUsageAdapter(
            credentialStore: store,
            transport: transport
        )

        let snapshot = try await adapter.fetchUsage(
            for: account,
            now: now
        )

        #expect(snapshot.accountID == account.id)
        let requests = await transport.requests
        #expect(requests.count == 3)
        #expect(
            requests[0].url?.absoluteString
                == "https://auth.x.ai/.well-known/openid-configuration"
        )
        #expect(requests[0].httpMethod == "GET")
        #expect(
            requests[1].url?.absoluteString
                == "https://auth.x.ai/token"
        )
        #expect(requests[1].httpMethod == "POST")
        #expect(
            requests[1].value(
                forHTTPHeaderField: "Content-Type"
            ) == "application/x-www-form-urlencoded"
        )
        let form = try oauthFormValues(
            from: requests[1]
        )
        #expect(form["grant_type"] == "refresh_token")
        #expect(form["refresh_token"] == "old-refresh")
        #expect(form["client_id"] == "client-1")
        #expect(
            requests[2].value(
                forHTTPHeaderField: "Authorization"
            ) == "Bearer fresh-token"
        )
        let stored = try #require(
            try await store.load(
                SuperGrokCredential.self,
                for: account.id
            )
        )
        #expect(stored.accessToken == "fresh-token")
        #expect(stored.refreshToken == "new-refresh")
        #expect(
            stored.expiresAt
                == now.addingTimeInterval(3_600)
        )
        #expect(stored.createdAt == now)
    }

    @Test
    func legacyCredentialNearExpiryUsesItsStillValidAccessToken()
        async throws
    {
        let now = Date(
            timeIntervalSince1970: 1_785_000_000
        )
        let account = SubscriptionAccount(
            provider: .superGrok,
            displayName: "Grok",
            displayOrder: 0
        )
        let store = SuperGrokTestCredentialStore()
        try await store.save(
            SuperGrokCredential(
                accessToken: "legacy-token",
                email: "user@example.com",
                teamID: "team-1",
                userID: "user-1",
                authMode: "oidc",
                expiresAt:
                    now.addingTimeInterval(4 * 60)
            ),
            for: account.id
        )
        let transport = SuperGrokSequencedTransport(
            responses: [
                HTTPResponse(
                    data: currentUsageResponse(),
                    statusCode: 200,
                    headers: [:]
                )
            ]
        )
        let adapter = SuperGrokUsageAdapter(
            credentialStore: store,
            transport: transport
        )

        _ = try await adapter.fetchUsage(
            for: account,
            now: now
        )

        let requests = await transport.requests
        #expect(requests.count == 1)
        #expect(
            requests[0].value(
                forHTTPHeaderField: "Authorization"
            ) == "Bearer legacy-token"
        )
    }

    @Test
    func proactivelyRefreshedCredentialRetriesBillingOnceAfterUnauthorized()
        async throws
    {
        let now = Date(
            timeIntervalSince1970: 1_785_000_000
        )
        let account = SubscriptionAccount(
            provider: .superGrok,
            displayName: "Grok",
            displayOrder: 0
        )
        let store = SuperGrokTestCredentialStore()
        try await store.save(
            refreshableCredential(
                accessToken: "near-expiry-token",
                refreshToken: "old-refresh",
                expiresAt:
                    now.addingTimeInterval(4 * 60)
            ),
            for: account.id
        )
        let transport = SuperGrokSequencedTransport(
            responses: [
                discoveryResponse(),
                try tokenResponse(
                    accessToken: "fresh-token",
                    refreshToken: "new-refresh"
                ),
                HTTPResponse(
                    data: Data(),
                    statusCode: 401,
                    headers: [:]
                ),
                HTTPResponse(
                    data: currentUsageResponse(),
                    statusCode: 200,
                    headers: [:]
                ),
            ]
        )
        let adapter = SuperGrokUsageAdapter(
            credentialStore: store,
            transport: transport
        )

        _ = try await adapter.fetchUsage(
            for: account,
            now: now
        )

        let requests = await transport.requests
        #expect(requests.count == 4)
        #expect(
            requests[2].value(
                forHTTPHeaderField: "Authorization"
            ) == "Bearer fresh-token"
        )
        #expect(
            requests[3].value(
                forHTTPHeaderField: "Authorization"
            ) == "Bearer fresh-token"
        )
    }

    @Test
    func unauthorizedBillingRefreshesOnceAndRetriesWithRotatedToken()
        async throws
    {
        let now = Date(
            timeIntervalSince1970: 1_785_000_000
        )
        let account = SubscriptionAccount(
            provider: .superGrok,
            displayName: "Grok",
            displayOrder: 0
        )
        let store = SuperGrokTestCredentialStore()
        try await store.save(
            refreshableCredential(
                accessToken: "rejected-token",
                refreshToken: "old-refresh",
                expiresAt:
                    now.addingTimeInterval(3_600)
            ),
            for: account.id
        )
        let transport = SuperGrokSequencedTransport(
            responses: [
                HTTPResponse(
                    data: Data(),
                    statusCode: 401,
                    headers: [:]
                ),
                discoveryResponse(),
                try tokenResponse(
                    accessToken: "fresh-token",
                    refreshToken: nil
                ),
                HTTPResponse(
                    data: currentUsageResponse(),
                    statusCode: 200,
                    headers: [:]
                ),
            ]
        )
        let adapter = SuperGrokUsageAdapter(
            credentialStore: store,
            transport: transport
        )

        _ = try await adapter.fetchUsage(
            for: account,
            now: now
        )

        let requests = await transport.requests
        #expect(requests.count == 4)
        #expect(
            requests[0].value(
                forHTTPHeaderField: "Authorization"
            ) == "Bearer rejected-token"
        )
        #expect(
            requests[3].value(
                forHTTPHeaderField: "Authorization"
            ) == "Bearer fresh-token"
        )
        let stored = try #require(
            try await store.load(
                SuperGrokCredential.self,
                for: account.id
            )
        )
        #expect(stored.accessToken == "fresh-token")
        #expect(stored.refreshToken == "old-refresh")
    }

    @Test
    func untrustedOIDCIssuerIsRejectedWithoutSendingARequest()
        async throws
    {
        let now = Date(
            timeIntervalSince1970: 1_785_000_000
        )
        let account = SubscriptionAccount(
            provider: .superGrok,
            displayName: "Grok",
            displayOrder: 0
        )
        let store = SuperGrokTestCredentialStore()
        try await store.save(
            SuperGrokCredential(
                accessToken: "expired-token",
                email: "user@example.com",
                teamID: "team-1",
                userID: "user-1",
                authMode: "oidc",
                expiresAt:
                    now.addingTimeInterval(-1),
                refreshToken: "refresh-token",
                oidcIssuer:
                    "https://attacker.example",
                oidcClientID: "client-1",
                createdAt:
                    now.addingTimeInterval(-3_600)
            ),
            for: account.id
        )
        let transport = SuperGrokSequencedTransport(
            responses: []
        )
        let adapter = SuperGrokUsageAdapter(
            credentialStore: store,
            transport: transport
        )

        await #expect(throws: ProviderClientError
            .reauthenticationRequired) {
            _ = try await adapter.fetchUsage(
                for: account,
                now: now
            )
        }
        #expect(await transport.requests.isEmpty)
    }
}

private func refreshableCredential(
    accessToken: String,
    refreshToken: String,
    expiresAt: Date
) -> SuperGrokCredential {
    SuperGrokCredential(
        accessToken: accessToken,
        email: "user@example.com",
        teamID: "team-1",
        userID: "user-1",
        authMode: "oidc",
        expiresAt: expiresAt,
        refreshToken: refreshToken,
        oidcIssuer: "https://auth.x.ai",
        oidcClientID: "client-1",
        createdAt:
            expiresAt.addingTimeInterval(-3_600)
    )
}

private func discoveryResponse() -> HTTPResponse {
    HTTPResponse(
        data: Data(
            #"""
            {
              "issuer": "https://auth.x.ai",
              "authorization_endpoint": "https://auth.x.ai/authorize",
              "token_endpoint": "https://auth.x.ai/token",
              "jwks_uri": "https://auth.x.ai/.well-known/jwks.json"
            }
            """#.utf8
        ),
        statusCode: 200,
        headers: [
            "Content-Type": "application/json"
        ]
    )
}

private func tokenResponse(
    accessToken: String,
    refreshToken: String?
) throws -> HTTPResponse {
    var object: [String: Any] = [
        "access_token": accessToken,
        "expires_in": 3_600,
        "token_type": "Bearer",
    ]
    object["refresh_token"] = refreshToken
    return HTTPResponse(
        data: try JSONSerialization.data(
            withJSONObject: object
        ),
        statusCode: 200,
        headers: [
            "Content-Type": "application/json"
        ]
    )
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

private actor SuperGrokSequencedTransport:
    HTTPTransport
{
    private(set) var requests: [URLRequest] = []
    private var responses: [HTTPResponse]

    init(responses: [HTTPResponse]) {
        self.responses = responses
    }

    func send(
        _ request: URLRequest
    ) throws -> HTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            throw ProviderClientError
                .temporaryFailure
        }
        return responses.removeFirst()
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
