import Foundation
import Testing
@testable import UsageMeterCore

func makeTestJWT(payload: [String: Any]) throws -> String {
    let header = try JSONSerialization.data(
        withJSONObject: ["alg": "none"]
    )
    let payload = try JSONSerialization.data(withJSONObject: payload)
    return [
        header.base64URLEncodedString(),
        payload.base64URLEncodedString(),
        "signature"
    ].joined(separator: ".")
}

func oauthFormValues(from request: URLRequest) throws -> [String: String] {
    let data = try #require(request.httpBody)
    let body = try #require(String(data: data, encoding: .utf8))
    var components = URLComponents()
    components.percentEncodedQuery = body
    return Dictionary(
        uniqueKeysWithValues: (components.queryItems ?? []).compactMap {
            item in item.value.map { (item.name, $0) }
        }
    )
}
