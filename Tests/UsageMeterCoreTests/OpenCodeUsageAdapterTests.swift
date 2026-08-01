import Foundation
import Testing

@testable import UsageMeterCore

@Suite
struct OpenCodeUsageAdapterTests {
    @Test
    func goRequestsItsWorkspaceDashboardWithAccountCookie()
        async throws
    {
        let account = SubscriptionAccount(
            provider: .openCodeGo,
            displayName: "Go",
            displayOrder: 0
        )
        let store = OpenCodeTestCredentialStore()
        try await store.save(
            OpenCodeDashboardCredential(
                workspaceID:
                    "wrk_01ABCDEF0123456789",
                authCookie: "go-cookie"
            ),
            for: account.id
        )
        let transport = OpenCodeRecordingTransport(
            response: HTTPResponse(
                data: goHTML(),
                statusCode: 200,
                headers: [:]
            )
        )
        let adapter = OpenCodeGoUsageAdapter(
            credentialStore: store,
            transport: transport
        )

        let snapshot = try await adapter.fetchUsage(
            for: account,
            now: Date(
                timeIntervalSince1970:
                    1_800_000_000
            )
        )

        #expect(snapshot.windows.count == 1)
        let request = try #require(
            await transport.lastRequest
        )
        #expect(
            request.url?.absoluteString
                == "https://opencode.ai/workspace/wrk_01ABCDEF0123456789/go"
        )
        #expect(
            request.value(
                forHTTPHeaderField: "Cookie"
            ) == "auth=go-cookie"
        )
    }

    @Test
    func zenRequestsBillingForItsOwnWorkspace()
        async throws
    {
        let account = SubscriptionAccount(
            provider: .openCodeZen,
            displayName: "Zen",
            displayOrder: 0
        )
        let store = OpenCodeTestCredentialStore()
        try await store.save(
            OpenCodeDashboardCredential(
                workspaceID: "wrk_ZEN",
                authCookie:
                    "auth=complete-cookie"
            ),
            for: account.id
        )
        let transport = OpenCodeRecordingTransport(
            response: HTTPResponse(
                data: zenHTML(),
                statusCode: 200,
                headers: [:]
            )
        )
        let adapter = OpenCodeZenUsageAdapter(
            credentialStore: store,
            transport: transport
        )

        let snapshot = try await adapter.fetchUsage(
            for: account,
            now: Date(
                timeIntervalSince1970:
                    1_775_000_000
            )
        )

        #expect(snapshot.balances.count == 1)
        let request = try #require(
            await transport.lastRequest
        )
        #expect(
            request.url?.absoluteString
                == "https://opencode.ai/workspace/wrk_ZEN/billing"
        )
        #expect(
            request.value(
                forHTTPHeaderField: "Cookie"
            ) == "auth=complete-cookie"
        )
    }

    @Test
    func authenticationAndRateFailuresAreMapped()
        async throws
    {
        let now = Date(
            timeIntervalSince1970: 1_800_000_000
        )
        let cases: [(Int, [String: String], ProviderClientError)] =
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

        for (statusCode, headers, expected) in cases {
            let account = SubscriptionAccount(
                provider: .openCodeGo,
                displayName: "Go",
                displayOrder: 0
            )
            let store =
                OpenCodeTestCredentialStore()
            try await store.save(
                OpenCodeDashboardCredential(
                    workspaceID: "wrk_GO",
                    authCookie: "cookie"
                ),
                for: account.id
            )
            let adapter = OpenCodeGoUsageAdapter(
                credentialStore: store,
                transport:
                    OpenCodeRecordingTransport(
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
}

private actor OpenCodeRecordingTransport:
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

private actor OpenCodeTestCredentialStore:
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

private func goHTML() -> Data {
    Data(
        #"""
        <script>
        self.__next_f.push([1,"{\"rollingUsage\":{\"usagePercent\":12.5,\"resetInSec\":3600}}"])
        </script>
        """#.utf8
    )
}

private func zenHTML() -> Data {
    Data(
        #"""
        <script>
        self.__next_f.push([1,"{\"balance\":1500000000,\"monthlyLimit\":null,\"monthlyUsage\":null}"])
        </script>
        """#.utf8
    )
}
