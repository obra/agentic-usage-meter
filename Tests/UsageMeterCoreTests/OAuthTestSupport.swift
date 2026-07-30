import Foundation
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
