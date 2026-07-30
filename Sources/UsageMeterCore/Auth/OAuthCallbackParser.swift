import Foundation

public enum OAuthCallbackError: Error, Equatable, Sendable {
    case invalidPath
    case stateMismatch
    case missingCode
}

extension OAuthCallbackError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidPath:
            "The OAuth callback path is invalid."
        case .stateMismatch:
            "The OAuth callback state does not match."
        case .missingCode:
            "The OAuth callback has no authorization code."
        }
    }
}

public enum OAuthCallbackParser {
    public static func parse(
        url: URL,
        expectedState: String
    ) throws -> String {
        guard url.path == "/auth/callback" else {
            throw OAuthCallbackError.invalidPath
        }

        let queryItems = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )?.queryItems
        let state = queryItems?.first { $0.name == "state" }?.value
        guard state == expectedState else {
            throw OAuthCallbackError.stateMismatch
        }

        guard let code = queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty
        else {
            throw OAuthCallbackError.missingCode
        }

        return code
    }
}
