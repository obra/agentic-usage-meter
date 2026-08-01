import Foundation

public struct OpenCodeGoUsageAdapter:
    ProviderAccountAdapter
{
    public let provider = Provider.openCodeGo

    private let client: OpenCodeDashboardUsageClient

    public init(
        credentialStore: any CredentialStore,
        transport: any HTTPTransport =
            URLSessionHTTPTransport(
                configuration: .ephemeral,
                followsRedirects: false
            ),
        decoder: OpenCodeGoUsageDecoder =
            OpenCodeGoUsageDecoder()
    ) {
        client = OpenCodeDashboardUsageClient(
            provider: .openCodeGo,
            page: "go",
            credentialStore: credentialStore,
            transport: transport,
            decode: decoder.decode
        )
    }

    public func fetchUsage(
        for account: SubscriptionAccount,
        now: Date
    ) async throws -> UsageSnapshot {
        try await client.fetchUsage(
            for: account,
            now: now
        )
    }

    public func removeAuthentication(
        for account: SubscriptionAccount
    ) async throws {
        try await client.removeAuthentication(
            for: account
        )
    }
}

public struct OpenCodeZenUsageAdapter:
    ProviderAccountAdapter
{
    public let provider = Provider.openCodeZen

    private let client: OpenCodeDashboardUsageClient

    public init(
        credentialStore: any CredentialStore,
        transport: any HTTPTransport =
            URLSessionHTTPTransport(
                configuration: .ephemeral,
                followsRedirects: false
            ),
        decoder: OpenCodeZenUsageDecoder =
            OpenCodeZenUsageDecoder()
    ) {
        client = OpenCodeDashboardUsageClient(
            provider: .openCodeZen,
            page: "billing",
            credentialStore: credentialStore,
            transport: transport,
            decode: decoder.decode
        )
    }

    public func fetchUsage(
        for account: SubscriptionAccount,
        now: Date
    ) async throws -> UsageSnapshot {
        try await client.fetchUsage(
            for: account,
            now: now
        )
    }

    public func removeAuthentication(
        for account: SubscriptionAccount
    ) async throws {
        try await client.removeAuthentication(
            for: account
        )
    }
}

private struct OpenCodeDashboardUsageClient:
    Sendable
{
    typealias Decode =
        @Sendable (
            Data,
            UUID,
            Date
        ) throws -> UsageSnapshot

    let provider: Provider
    let page: String
    let credentialStore: any CredentialStore
    let transport: any HTTPTransport
    let decode: Decode

    func fetchUsage(
        for account: SubscriptionAccount,
        now: Date
    ) async throws -> UsageSnapshot {
        guard account.provider == provider else {
            throw ProviderClientError
                .credentialMismatch
        }

        let credential: OpenCodeDashboardCredential?
        do {
            credential =
                try await credentialStore.load(
                    OpenCodeDashboardCredential.self,
                    for: account.id
                )
        } catch {
            throw ProviderClientError
                .credentialMismatch
        }
        guard
            let credential,
            let workspaceID =
                credential.identityKey,
            !credential.authCookie.isEmpty
        else {
            throw ProviderClientError
                .reauthenticationRequired
        }
        let encodedWorkspaceID =
            workspaceID.addingPercentEncoding(
                withAllowedCharacters:
                    .urlPathAllowed
            ) ?? workspaceID
        var request = URLRequest(
            url: URL(
                string:
                    "https://opencode.ai/workspace/\(encodedWorkspaceID)/\(page)"
            )!
        )
        request.httpMethod = "GET"
        request.setValue(
            "text/html,application/xhtml+xml",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(
            cookieHeader(
                credential.authCookie
            ),
            forHTTPHeaderField: "Cookie"
        )

        let response =
            try await transport
            .send(request)
        switch response.statusCode {
        case 200...299:
            return try decode(
                response.data,
                account.id,
                now
            )
        case 300...399, 401, 403:
            throw ProviderClientError
                .reauthenticationRequired
        case 429:
            throw
                ProviderClientError
                .retryAfter(
                    response.retryDate(
                        relativeTo: now
                    )
                )
        default:
            throw ProviderClientError
                .temporaryFailure
        }
    }

    func removeAuthentication(
        for account: SubscriptionAccount
    ) async throws {
        try await credentialStore.delete(
            for: account.id
        )
    }

    private func cookieHeader(
        _ value: String
    ) -> String {
        value.contains("auth=")
            ? value
            : "auth=\(value)"
    }
}
