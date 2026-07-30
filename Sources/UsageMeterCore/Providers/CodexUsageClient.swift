import Foundation

public struct CodexUsageClient: UsageProviderClient {
    public let provider = Provider.codex

    private let transport: any HTTPTransport
    private let decoder: CodexUsageDecoder

    public init(
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        decoder: CodexUsageDecoder = CodexUsageDecoder()
    ) {
        self.transport = transport
        self.decoder = decoder
    }

    public func fetchUsage(
        accountID: UUID,
        credential: ProviderCredential,
        now: Date
    ) async throws -> UsageSnapshot {
        guard
            case let .codex(oauth) = credential,
            !oauth.accessToken.isEmpty,
            let providerAccountID = oauth.accountID,
            !providerAccountID.isEmpty
        else {
            throw ProviderClientError.credentialMismatch
        }

        var request = URLRequest(
            url: URL(
                string: "https://chatgpt.com/backend-api/wham/usage"
            )!
        )
        request.httpMethod = "GET"
        request.setValue(
            "Bearer \(oauth.accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            providerAccountID,
            forHTTPHeaderField: "ChatGPT-Account-Id"
        )
        request.setValue("codex-cli", forHTTPHeaderField: "User-Agent")

        let response = try await transport.send(request)
        switch response.statusCode {
        case 200 ... 299:
            return try decoder.decode(
                response.data,
                accountID: accountID,
                fetchedAt: now
            )
        case 401, 403:
            throw ProviderClientError.reauthenticationRequired
        case 429:
            throw ProviderClientError.retryAfter(
                response.retryDate(relativeTo: now)
            )
        default:
            throw ProviderClientError.temporaryFailure
        }
    }
}

public struct CodexUsageDecoder: Sendable {
    public init() {}

    public func decode(
        _ data: Data,
        accountID: UUID,
        fetchedAt: Date
    ) throws -> UsageSnapshot {
        let response: CodexUsageResponse
        do {
            response = try JSONDecoder().decode(
                CodexUsageResponse.self,
                from: data
            )
        } catch {
            throw ProviderClientError.unsupportedResponse
        }

        let candidates = [
            response.rateLimit.primaryWindow,
            response.rateLimit.secondaryWindow
        ].compactMap(\.self)
        var windowsByKind: [UsageWindowKind: UsageWindow] = [:]

        for candidate in candidates {
            guard let kind = windowKind(for: candidate.duration) else {
                continue
            }
            guard
                windowsByKind[kind] == nil,
                candidate.usedPercent.isFinite,
                (0 ... 100).contains(candidate.usedPercent),
                candidate.resetAt.isFinite,
                candidate.resetAt > 0,
                let window = UsageWindow(
                    id: "codex-\(kind.rawValue)",
                    kind: kind,
                    duration: candidate.duration,
                    resetAt: Date(
                        timeIntervalSince1970: candidate.resetAt
                    ),
                    consumedFraction: candidate.usedPercent / 100
                )
            else {
                throw ProviderClientError.unsupportedResponse
            }
            windowsByKind[kind] = window
        }

        let windows = [
            windowsByKind[.short],
            windowsByKind[.weekly]
        ].compactMap(\.self)
        guard !windows.isEmpty else {
            throw ProviderClientError.unsupportedResponse
        }

        return UsageSnapshot(
            accountID: accountID,
            fetchedAt: fetchedAt,
            windows: windows
        )
    }

    private func windowKind(
        for duration: TimeInterval
    ) -> UsageWindowKind? {
        switch duration {
        case 18_000:
            .short
        case 604_800:
            .weekly
        default:
            nil
        }
    }
}

private struct CodexUsageResponse: Decodable {
    let rateLimit: RateLimit

    enum CodingKeys: String, CodingKey {
        case rateLimit = "rate_limit"
    }

    struct RateLimit: Decodable {
        let primaryWindow: Window?
        let secondaryWindow: Window?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    struct Window: Decodable {
        let usedPercent: Double
        let duration: TimeInterval
        let resetAt: TimeInterval

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case duration = "limit_window_seconds"
            case resetAt = "reset_at"
        }
    }
}
