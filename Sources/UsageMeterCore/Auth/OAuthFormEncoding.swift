import Foundation

enum OAuthFormEncodingError: Error {
    case invalidForm
}

func oauthFormData(_ queryItems: [URLQueryItem]) throws -> Data {
    var components = URLComponents()
    components.queryItems = queryItems
    guard let query = components.percentEncodedQuery else {
        throw OAuthFormEncodingError.invalidForm
    }
    return Data(query.utf8)
}
