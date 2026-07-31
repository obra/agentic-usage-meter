import Foundation

public struct GitHubCopilotUsageAdapter:
    ProviderAccountAdapter
{
    public let provider =
        Provider.githubCopilot

    private let credentialStore: any CredentialStore
    private let transport: any HTTPTransport
    private let decoder: GitHubCopilotUsageDecoder

    public init(
        credentialStore: any CredentialStore,
        transport: any HTTPTransport =
            URLSessionHTTPTransport(),
        decoder: GitHubCopilotUsageDecoder =
            GitHubCopilotUsageDecoder()
    ) {
        self.credentialStore = credentialStore
        self.transport = transport
        self.decoder = decoder
    }

    public func fetchUsage(
        for account: SubscriptionAccount,
        now: Date
    ) async throws -> UsageSnapshot {
        guard account.provider == provider else {
            throw ProviderClientError
                .credentialMismatch
        }

        let credential: GitHubCopilotCredential?
        do {
            credential =
                try await credentialStore
                .load(
                    GitHubCopilotCredential.self,
                    for: account.id
                )
        } catch {
            throw ProviderClientError
                .credentialMismatch
        }
        guard
            let credential,
            !credential.accessToken.isEmpty,
            !credential.userID.isEmpty,
            !credential.login.isEmpty
        else {
            throw ProviderClientError
                .reauthenticationRequired
        }

        var request = URLRequest(
            url: URL(
                string:
                    "https://api.github.com/copilot_internal/user"
            )!
        )
        request.httpMethod = "GET"
        request.setValue(
            "token \(credential.accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(
            "vscode/1.96.2",
            forHTTPHeaderField: "Editor-Version"
        )
        request.setValue(
            "2025-04-01",
            forHTTPHeaderField:
                "X-GitHub-Api-Version"
        )

        let response = try await transport.send(
            request
        )
        switch response.statusCode {
        case 200...299:
            let result = try decoder.decode(
                response.data,
                accountID: account.id,
                fetchedAt: now
            )
            if let userID = result.userID,
                userID != credential.userID
            {
                throw ProviderClientError
                    .credentialMismatch
            }
            return result.snapshot
        case 401, 403:
            throw ProviderClientError
                .reauthenticationRequired
        case 429:
            throw ProviderClientError.retryAfter(
                response.retryDate(
                    relativeTo: now
                )
            )
        default:
            throw ProviderClientError
                .temporaryFailure
        }
    }

    public func removeAuthentication(
        for account: SubscriptionAccount
    ) async throws {
        try await credentialStore.delete(
            for: account.id
        )
    }
}
