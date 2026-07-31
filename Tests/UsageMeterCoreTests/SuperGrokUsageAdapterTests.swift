import Foundation
import Testing

@testable import UsageMeterCore

@Suite
struct SuperGrokUsageAdapterTests {
    @Test
    func adapterUsesOnlyItsAccountCredential()
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
                data: validUsageResponse(),
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
                == "https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig"
        )
        #expect(request.httpMethod == "POST")
        #expect(
            request.value(
                forHTTPHeaderField: "Authorization"
            ) == "Bearer account-token"
        )
        #expect(
            request.value(
                forHTTPHeaderField: "Content-Type"
            ) == "application/grpc-web+proto"
        )
        #expect(request.httpBody == Data([0, 0, 0, 0, 0]))
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
                data: validUsageResponse(),
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

private func validUsageResponse() -> Data {
    let resetEpoch: UInt64 = 1_785_600_000
    var weekly = Data()
    weekly.append(superGrokFixed32Field(1, 20))
    weekly.append(
        superGrokLengthDelimitedField(
            5,
            superGrokVarintField(
                1,
                resetEpoch
            )
        )
    )
    return superGrokGrpcWebFrame(
        superGrokLengthDelimitedField(
            1,
            weekly
        )
    )
}

private func superGrokEncodeVarint(
    _ value: UInt64
) -> Data {
    var remaining = value
    var data = Data()
    while remaining >= 0x80 {
        data.append(
            UInt8(remaining & 0x7F) | 0x80
        )
        remaining >>= 7
    }
    data.append(UInt8(remaining))
    return data
}

private func superGrokVarintField(
    _ fieldNumber: UInt8,
    _ value: UInt64
) -> Data {
    var data = Data(
        [(fieldNumber << 3) | 0]
    )
    data.append(
        superGrokEncodeVarint(value)
    )
    return data
}

private func superGrokLengthDelimitedField(
    _ fieldNumber: UInt8,
    _ payload: Data
) -> Data {
    var data = Data(
        [(fieldNumber << 3) | 2]
    )
    data.append(
        superGrokEncodeVarint(
            UInt64(payload.count)
        )
    )
    data.append(payload)
    return data
}

private func superGrokFixed32Field(
    _ fieldNumber: UInt8,
    _ value: Float
) -> Data {
    var data = Data(
        [(fieldNumber << 3) | 5]
    )
    let bits = value.bitPattern
    data.append(
        contentsOf: [
            UInt8(bits & 0xFF),
            UInt8((bits >> 8) & 0xFF),
            UInt8((bits >> 16) & 0xFF),
            UInt8((bits >> 24) & 0xFF),
        ]
    )
    return data
}

private func superGrokGrpcWebFrame(
    _ payload: Data
) -> Data {
    var frame = Data([0])
    frame.append(
        contentsOf: [
            UInt8((payload.count >> 24) & 0xFF),
            UInt8((payload.count >> 16) & 0xFF),
            UInt8((payload.count >> 8) & 0xFF),
            UInt8(payload.count & 0xFF),
        ]
    )
    frame.append(payload)
    return frame
}
