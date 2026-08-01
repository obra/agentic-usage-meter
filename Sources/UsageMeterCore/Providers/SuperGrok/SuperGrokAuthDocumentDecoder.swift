import Foundation

public struct SuperGrokAuthDocumentDecoder:
    Sendable
{
    public init() {}

    public func decode(
        _ data: Data
    ) throws -> SuperGrokCredential {
        let object: Any
        do {
            object =
                try JSONSerialization
                .jsonObject(with: data)
        } catch {
            throw ProviderClientError
                .unsupportedResponse
        }
        guard
            let root = object as? [String: Any],
            let entry = selectedEntry(in: root),
            let accessToken = nonEmptyString(
                entry["key"]
            )
        else {
            throw ProviderClientError
                .reauthenticationRequired
        }

        let credential = SuperGrokCredential(
            accessToken: accessToken,
            email: nonEmptyString(entry["email"]),
            teamID: nonEmptyString(
                entry["team_id"]
            ),
            userID: nonEmptyString(
                entry["user_id"]
            ),
            authMode: nonEmptyString(
                entry["auth_mode"]
            ),
            expiresAt: parseDate(
                entry["expires_at"]
            ),
            refreshToken: nonEmptyString(
                entry["refresh_token"]
            ),
            oidcIssuer: nonEmptyString(
                entry["oidc_issuer"]
            ),
            oidcClientID: nonEmptyString(
                entry["oidc_client_id"]
            ),
            createdAt: parseDate(
                entry["create_time"]
            )
        )
        guard
            credential.identityKey != nil,
            nonEmptyString(credential.userID) != nil
        else {
            throw ProviderClientError
                .unsupportedResponse
        }
        return credential
    }

    private func selectedEntry(
        in root: [String: Any]
    ) -> [String: Any]? {
        if nonEmptyString(root["key"]) != nil {
            return root
        }

        let entries = root.compactMap {
            scope,
            rawEntry
                -> (
                    priority: Int,
                    scope: String,
                    entry: [String: Any]
                )?
            in
            guard
                let entry =
                    rawEntry as? [String: Any],
                nonEmptyString(entry["key"])
                    != nil
            else {
                return nil
            }

            let priority: Int
            if scope.hasPrefix(
                "https://auth.x.ai::"
            ) {
                priority = 0
            } else if scope
                == "https://accounts.x.ai/sign-in"
                || scope.contains("/sign-in")
            {
                priority = 1
            } else {
                priority = 2
            }
            return (priority, scope, entry)
        }
        return entries.sorted {
            if $0.priority != $1.priority {
                return $0.priority < $1.priority
            }
            return $0.scope < $1.scope
        }.first?.entry
    }

    private func nonEmptyString(
        _ value: Any?
    ) -> String? {
        guard
            let value = value as? String
        else {
            return nil
        }
        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parseDate(
        _ value: Any?
    ) -> Date? {
        guard
            let value = nonEmptyString(value)
        else {
            return nil
        }

        let fractional =
            ISO8601DateFormatter()
        fractional.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        if let date = fractional.date(
            from: value
        ) {
            return date
        }

        let internet = ISO8601DateFormatter()
        internet.formatOptions = [
            .withInternetDateTime
        ]
        return internet.date(from: value)
    }
}
