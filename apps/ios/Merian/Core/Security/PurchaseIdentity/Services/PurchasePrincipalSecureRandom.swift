import Foundation
import Security

enum PurchasePrincipalSecureRandom {
    static func generateCapability() throws -> Data {
        try generateBytes(count: 32)
    }

    static func generateRotationSecret() throws -> String {
        PurchasePrincipalSecretPolicy.base64URL(
            try generateBytes(count: 32)
        )
    }

    private static func generateBytes(count: Int) throws -> Data {
        var bytes = Data(count: count)
        let status = bytes.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return errSecParam
            }
            return SecRandomCopyBytes(kSecRandomDefault, count, baseAddress)
        }
        guard status == errSecSuccess else {
            throw PurchasePrincipalResolverError.capabilityUnavailable
        }
        return bytes
    }
}
