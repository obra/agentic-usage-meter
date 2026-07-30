import CryptoKit
import Foundation
import Security

public enum PKCEError: Error, Equatable, Sendable {
    case randomGenerationFailed(OSStatus)
}

public struct PKCECodes: Equatable, Sendable {
    public let verifier: String
    public let challenge: String

    public static func generate() throws -> Self {
        var bytes = [UInt8](repeating: 0, count: 64)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(
                kSecRandomDefault,
                buffer.count,
                buffer.baseAddress!
            )
        }
        guard status == errSecSuccess else {
            throw PKCEError.randomGenerationFailed(status)
        }

        let verifier = Data(bytes).base64URLEncodedString()
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return PKCECodes(
            verifier: verifier,
            challenge: Data(digest).base64URLEncodedString()
        )
    }
}

extension Data {
    fileprivate func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
