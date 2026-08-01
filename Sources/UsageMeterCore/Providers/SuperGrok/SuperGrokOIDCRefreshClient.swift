import Foundation

struct SuperGrokOIDCRefreshClient: Sendable {
    private static let issuerHost = "auth.x.ai"
    private static let discoveryURL = URL(
        string:
            "https://auth.x.ai/.well-known/openid-configuration"
    )!

    private let transport: any HTTPTransport

    init(transport: any HTTPTransport) {
        self.transport = transport
    }

    func refresh(
        _ credential: SuperGrokCredential,
        now: Date
    ) async throws -> SuperGrokCredential {
        guard
            normalized(credential.authMode) == "oidc",
            let refreshToken = normalized(
                credential.refreshToken
            ),
            let clientID = normalized(
                credential.oidcClientID
            ),
            let issuer = validatedIssuer(
                credential.oidcIssuer
            )
        else {
            throw ProviderClientError
                .reauthenticationRequired
        }

        var discoveryRequest = URLRequest(
            url: Self.discoveryURL
        )
        discoveryRequest.httpMethod = "GET"
        let discoveryResponse = try await send(
            discoveryRequest
        )
        let discovery: DiscoveryDocument
        switch discoveryResponse.statusCode {
        case 200...299:
            do {
                discovery = try JSONDecoder().decode(
                    DiscoveryDocument.self,
                    from: discoveryResponse.data
                )
            } catch {
                throw ProviderClientError
                    .unsupportedResponse
            }
        case 429:
            throw ProviderClientError.retryAfter(
                discoveryResponse.retryDate(
                    relativeTo: now
                )
            )
        default:
            throw ProviderClientError
                .temporaryFailure
        }

        guard
            let tokenEndpoint = validatedTokenEndpoint(
                discovery.tokenEndpoint
            )
        else {
            throw ProviderClientError
                .unsupportedResponse
        }

        var tokenRequest = URLRequest(
            url: tokenEndpoint
        )
        tokenRequest.httpMethod = "POST"
        do {
            tokenRequest.httpBody = try oauthFormData([
                URLQueryItem(
                    name: "grant_type",
                    value: "refresh_token"
                ),
                URLQueryItem(
                    name: "refresh_token",
                    value: refreshToken
                ),
                URLQueryItem(
                    name: "client_id",
                    value: clientID
                ),
            ])
        } catch {
            throw ProviderClientError
                .temporaryFailure
        }
        tokenRequest.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )

        let tokenResponse = try await send(
            tokenRequest
        )
        switch tokenResponse.statusCode {
        case 200...299:
            return try applyTokenResponse(
                tokenResponse.data,
                to: credential,
                issuer: issuer,
                clientID: clientID,
                refreshToken: refreshToken,
                now: now
            )
        case 400:
            let code = try? JSONDecoder().decode(
                TokenError.self,
                from: tokenResponse.data
            ).error
            if code == "invalid_grant"
                || code == "invalid_client"
            {
                throw ProviderClientError
                    .reauthenticationRequired
            }
            throw ProviderClientError
                .temporaryFailure
        case 401, 403:
            throw ProviderClientError
                .reauthenticationRequired
        case 429:
            throw ProviderClientError.retryAfter(
                tokenResponse.retryDate(
                    relativeTo: now
                )
            )
        default:
            throw ProviderClientError
                .temporaryFailure
        }
    }

    private func send(
        _ request: URLRequest
    ) async throws -> HTTPResponse {
        do {
            return try await transport.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ProviderClientError
                .temporaryFailure
        }
    }

    private func applyTokenResponse(
        _ data: Data,
        to credential: SuperGrokCredential,
        issuer: String,
        clientID: String,
        refreshToken: String,
        now: Date
    ) throws -> SuperGrokCredential {
        let response: TokenResponse
        do {
            response = try JSONDecoder().decode(
                TokenResponse.self,
                from: data
            )
        } catch {
            throw ProviderClientError
                .unsupportedResponse
        }
        guard
            let accessToken = normalized(
                response.accessToken
            ),
            response.expiresIn.map({
                $0.isFinite && $0 > 0
            }) ?? true
        else {
            throw ProviderClientError
                .unsupportedResponse
        }

        return SuperGrokCredential(
            accessToken: accessToken,
            email: credential.email,
            teamID: credential.teamID,
            userID: credential.userID,
            authMode: credential.authMode,
            expiresAt: response.expiresIn.map {
                now.addingTimeInterval($0)
            },
            refreshToken: normalized(
                response.refreshToken
            ) ?? refreshToken,
            oidcIssuer: issuer,
            oidcClientID: clientID,
            createdAt: now
        )
    }

    private func validatedIssuer(
        _ value: String?
    ) -> String? {
        guard
            let value = normalized(value),
            let url = URL(string: value),
            url.scheme == "https",
            url.host == Self.issuerHost,
            url.port == nil,
            url.user == nil,
            url.password == nil,
            url.query == nil,
            url.fragment == nil,
            url.path.isEmpty || url.path == "/"
        else {
            return nil
        }
        return "https://\(Self.issuerHost)"
    }

    private func validatedTokenEndpoint(
        _ value: String
    ) -> URL? {
        guard
            let url = URL(string: value),
            url.scheme == "https",
            url.host == Self.issuerHost,
            url.port == nil,
            url.user == nil,
            url.password == nil
        else {
            return nil
        }
        return url
    }

    private func normalized(
        _ value: String?
    ) -> String? {
        guard
            let value = value?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
            !value.isEmpty
        else {
            return nil
        }
        return value
    }
}

private struct DiscoveryDocument: Decodable {
    let tokenEndpoint: String

    enum CodingKeys: String, CodingKey {
        case tokenEndpoint = "token_endpoint"
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct TokenError: Decodable {
    let error: String
}
