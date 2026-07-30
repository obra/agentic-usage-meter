import CryptoKit
import Foundation
import Testing
@testable import UsageMeterCore

@Suite
struct PKCETests {
    @Test
    func generatedVerifierMatchesCurrentCodexShape() throws {
        let codes = try PKCECodes.generate()

        #expect(codes.verifier.count == 86)
        #expect(!codes.verifier.contains("="))
        #expect(!codes.verifier.contains("+"))
        #expect(!codes.verifier.contains("/"))
    }

    @Test
    func challengeIsBase64URLSHA256OfTheVerifier() throws {
        let codes = try PKCECodes.generate()
        let digest = SHA256.hash(data: Data(codes.verifier.utf8))
        let expected = Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        #expect(codes.challenge == expected)
    }
}
