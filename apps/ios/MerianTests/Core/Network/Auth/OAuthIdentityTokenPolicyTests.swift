import Foundation
@testable import Merian
import XCTest

final class OAuthIdentityTokenPolicyTests: XCTestCase {
    func testProviderSubjectReadsBase64URLJWTSubject() throws {
        let token = try makeUnsignedJWT(
            payload: ["sub": "001234.abcd9876", "aud": "merian"]
        )

        XCTAssertEqual(
            try OAuthIdentityTokenPolicy.providerSubject(from: token),
            "001234.abcd9876"
        )
    }

    func testProviderSubjectRejectsMalformedOrUnsafeClaims() throws {
        XCTAssertThrowsError(
            try OAuthIdentityTokenPolicy.providerSubject(from: "not-a-jwt")
        )
        XCTAssertThrowsError(
            try OAuthIdentityTokenPolicy.providerSubject(
                from: try makeUnsignedJWT(payload: ["aud": "merian"])
            )
        )
        XCTAssertThrowsError(
            try OAuthIdentityTokenPolicy.providerSubject(
                from: try makeUnsignedJWT(
                    payload: ["sub": "subject\ninjection"]
                )
            )
        )
        XCTAssertThrowsError(
            try OAuthIdentityTokenPolicy.providerSubject(
                from: try makeUnsignedJWT(
                    payload: [
                        "sub": String(repeating: "a", count: 256)
                    ]
                )
            )
        )
    }

    private func makeUnsignedJWT(
        payload: [String: String]
    ) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: payload)
        let payloadSegment = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(payloadSegment).signature"
    }
}
