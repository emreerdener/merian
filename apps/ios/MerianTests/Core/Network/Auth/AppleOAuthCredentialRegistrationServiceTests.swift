import Foundation
@testable import Merian
import XCTest

@MainActor
final class AppleOAuthRegistrationServiceTests: XCTestCase {
    func testRegistrationForwardsExactValuesAndAcceptsRegisteredReceipt()
        async throws {
        let registrationID = UUID(
            uuidString: "11111111-1111-4111-8111-111111111111"
        )!
        var receivedRegistrationID: UUID?
        var receivedAuthorizationCode: String?
        var receivedIdentityToken: String?
        let service = AppleOAuthCredentialRegistrationService {
            receivedRegistrationID = $0
            receivedAuthorizationCode = $1
            receivedIdentityToken = $2
            return AppleOAuthCredentialRegistrationReceipt(
                success: true,
                status: "registered"
            )
        }

        try await service.register(
            registrationID: registrationID,
            authorizationCode: "one-use-code",
            identityToken: "identity-token"
        )

        XCTAssertEqual(receivedRegistrationID, registrationID)
        XCTAssertEqual(receivedAuthorizationCode, "one-use-code")
        XCTAssertEqual(receivedIdentityToken, "identity-token")
    }

    func testRegistrationRejectsEveryNonRegisteredReceipt() async {
        let invalidReceipts = [
            AppleOAuthCredentialRegistrationReceipt(
                success: false,
                status: "registered"
            ),
            AppleOAuthCredentialRegistrationReceipt(
                success: true,
                status: "pending"
            ),
            AppleOAuthCredentialRegistrationReceipt(
                success: false,
                status: "pending"
            )
        ]

        for receipt in invalidReceipts {
            let service = AppleOAuthCredentialRegistrationService { _, _, _ in
                receipt
            }
            do {
                try await service.register(
                    registrationID: UUID(),
                    authorizationCode: "one-use-code",
                    identityToken: "identity-token"
                )
                XCTFail("Expected an invalid registration receipt")
            } catch OAuthSignInWorkflowError
                .invalidAppleCredentialRegistrationReceipt {
                continue
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testRegistrationPreservesTransportFailure() async {
        let service = AppleOAuthCredentialRegistrationService { _, _, _ in
            throw AppleOAuthRegistrationTestError.expected
        }

        do {
            try await service.register(
                registrationID: UUID(),
                authorizationCode: "one-use-code",
                identityToken: "identity-token"
            )
            XCTFail("Expected the transport failure")
        } catch AppleOAuthRegistrationTestError.expected {
            return
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private enum AppleOAuthRegistrationTestError: Error {
    case expected
}
