import Foundation
import UsageMeterCore

@MainActor
public final class ClaudeWebUsageClient {
    private static let baseURL = URL(string: "https://claude.ai")!
    private static let userAgent = [
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
        "AppleWebKit/605.1.15 (KHTML, like Gecko)",
        "Version/17.0 Safari/605.1.15"
    ].joined(separator: " ")

    private let transport: any HTTPTransport
    private let cookieSource: any ClaudeWebCookieSource
    private let decoder: ClaudeUsageDecoder
    private let cookieRetryDelays: [Duration]

    public init(
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        cookieSource: any ClaudeWebCookieSource = WebKitClaudeCookieSource(),
        decoder: ClaudeUsageDecoder = ClaudeUsageDecoder()
    ) {
        self.transport = transport
        self.cookieSource = cookieSource
        self.decoder = decoder
        cookieRetryDelays = [
            .milliseconds(250),
            .milliseconds(500),
            .seconds(1)
        ]
    }

    init(
        transport: any HTTPTransport,
        cookieSource: any ClaudeWebCookieSource,
        decoder: ClaudeUsageDecoder = ClaudeUsageDecoder(),
        cookieRetryDelays: [Duration]
    ) {
        self.transport = transport
        self.cookieSource = cookieSource
        self.decoder = decoder
        self.cookieRetryDelays = cookieRetryDelays
    }

    public func authenticated(
        with cookies: [HTTPCookie]
    ) -> ClaudeWebUsageClient {
        ClaudeWebUsageClient(
            transport: transport,
            cookieSource: CapturedClaudeCookieSource(
                cookies: cookies
            ),
            decoder: decoder,
            cookieRetryDelays: cookieRetryDelays
        )
    }

    public func prepareProfileRemoval(profileID: UUID) {
        cookieSource.prepareForRemoval(profileID: profileID)
    }

    public func finishProfileRemoval(profileID: UUID) {
        cookieSource.finishRemoval(profileID: profileID)
    }

    public func organizations(profileID: UUID) async throws
        -> [ClaudeOrganization]
    {
        let url = Self.baseURL.appending(
            path: "api/organizations",
            directoryHint: .notDirectory
        )
        let response = try await sendRequest(url: url, profileID: profileID)
        try validate(response, relativeTo: Date())

        do {
            let organizations = try JSONDecoder().decode(
                [ClaudeOrganization].self,
                from: response.data
            )
            guard !organizations.isEmpty else {
                throw ProviderClientError.unsupportedResponse
            }
            return organizations
        } catch let error as ProviderClientError {
            throw error
        } catch {
            throw ProviderClientError.unsupportedResponse
        }
    }

    public func fetchUsage(
        accountID: UUID,
        profileID: UUID,
        organizationID: UUID,
        now: Date
    ) async throws -> UsageSnapshot {
        let url = Self.baseURL.appending(
            path: "api/organizations/\(organizationID.uuidString.lowercased())/usage",
            directoryHint: .notDirectory
        )
        let response = try await sendRequest(url: url, profileID: profileID)
        try validate(response, relativeTo: now)
        return try decoder.decode(
            response.data,
            accountID: accountID,
            fetchedAt: now
        )
    }

    private func sendRequest(
        url: URL,
        profileID: UUID
    ) async throws -> HTTPResponse {
        let selectedCookies = try await apiCookies(
            for: url,
            profileID: profileID
        )

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(
            selectedCookies
                .map { "\($0.name)=\($0.value)" }
                .joined(separator: "; "),
            forHTTPHeaderField: "Cookie"
        )
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(
            Self.baseURL.absoluteString,
            forHTTPHeaderField: "Origin"
        )
        request.setValue(
            Self.baseURL.absoluteString,
            forHTTPHeaderField: "Referer"
        )
        return try await transport.send(request)
    }

    private func apiCookies(
        for url: URL,
        profileID: UUID
    ) async throws -> [HTTPCookie] {
        let availableCookies = await cookieSource.cookies(
            for: url,
            profileID: profileID
        )
        if let selectedCookies = ClaudeLoginCookieDetector.apiCookies(
            in: availableCookies
        ) {
            return selectedCookies
        }

        for delay in cookieRetryDelays {
            try await Task.sleep(for: delay)
            let availableCookies = await cookieSource.cookies(
                for: url,
                profileID: profileID
            )
            if let selectedCookies = ClaudeLoginCookieDetector.apiCookies(
                in: availableCookies
            ) {
                return selectedCookies
            }
        }

        throw ProviderClientError.reauthenticationRequired
    }

    private func validate(
        _ response: HTTPResponse,
        relativeTo now: Date
    ) throws {
        switch response.statusCode {
        case 200 ... 299:
            return
        case 401, 403:
            throw ProviderClientError.reauthenticationRequired
        case 429:
            throw ProviderClientError.retryAfter(
                retryDate(from: response, relativeTo: now)
            )
        default:
            throw ProviderClientError.temporaryFailure
        }
    }

    private func retryDate(
        from response: HTTPResponse,
        relativeTo now: Date
    ) -> Date? {
        guard let value = response.header(named: "Retry-After") else {
            return nil
        }
        if let seconds = TimeInterval(value), seconds.isFinite, seconds >= 0 {
            return now.addingTimeInterval(seconds)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value)
    }
}

@MainActor
private final class CapturedClaudeCookieSource:
    ClaudeWebCookieSource
{
    private let capturedCookies: [HTTPCookie]

    init(cookies: [HTTPCookie]) {
        capturedCookies = cookies
    }

    func cookies(
        for _: URL,
        profileID _: UUID
    ) async -> [HTTPCookie] {
        capturedCookies
    }
}
