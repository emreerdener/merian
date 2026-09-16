import AuthenticationServices
import Foundation
@testable import Merian
import UIKit
import XCTest

@MainActor
private final class AppleOAuthLiveProviderHarness {
    enum HarnessError: Error {
        case nonce
        case provider
    }

    let anchor = UIWindow(frame: .zero)
    let registrationID = UUID()
    var nonceResult: Result<String, Error> = .success("nonce")
    var shouldProvideAnchor = true
    private(set) var controller: ASAuthorizationController?
    private(set) var request: ASAuthorizationAppleIDRequest?
    private(set) var performCount = 0
    private(set) var result: Result<OAuthProviderAuthorization, Error>?

    func dependencies() -> AppleOAuthAuthorizationLiveDependencies {
        AppleOAuthAuthorizationLiveDependencies(
            randomNonce: {
                try self.nonceResult.get()
            },
            hashNonce: { "hashed-\($0)" },
            presentationAnchor: {
                self.shouldProvideAnchor ? self.anchor : nil
            },
            makeRequest: {
                let request = ASAuthorizationAppleIDProvider()
                    .createRequest()
                self.request = request
                return request
            },
            makeController: { request in
                let controller = ASAuthorizationController(
                    authorizationRequests: [request]
                )
                self.controller = controller
                return controller
            },
            performRequests: { controller in
                XCTAssertTrue(controller === self.controller)
                self.performCount += 1
            },
            registrationID: {
                self.registrationID
            }
        )
    }

    func record(_ result: Result<OAuthProviderAuthorization, Error>) {
        self.result = result
    }
}

@MainActor
final class AppleOAuthAuthorizationLiveProviderTests: XCTestCase {
    func testStartConfiguresAndRetainsTheExactAuthorizationController()
        throws {
        let harness = AppleOAuthLiveProviderHarness()
        let provider = AppleOAuthAuthorizationLiveProvider(
            dependencies: harness.dependencies()
        )

        try provider.start { harness.record($0) }

        let request = try XCTUnwrap(harness.request)
        let controller = try XCTUnwrap(harness.controller)
        XCTAssertEqual(request.nonce, "hashed-nonce")
        XCTAssertEqual(
            Set(request.requestedScopes ?? []),
            Set([.fullName, .email])
        )
        XCTAssertEqual(harness.performCount, 1)
        XCTAssertTrue(controller.delegate as AnyObject? === provider)
        XCTAssertTrue(
            controller.presentationContextProvider as AnyObject? === provider
        )
        XCTAssertTrue(
            provider.presentationAnchor(for: controller) === harness.anchor
        )
    }

    func testNonceFailureStopsBeforeRequestConstruction() {
        let harness = AppleOAuthLiveProviderHarness()
        harness.nonceResult = .failure(
            AppleOAuthLiveProviderHarness.HarnessError.nonce
        )
        let provider = AppleOAuthAuthorizationLiveProvider(
            dependencies: harness.dependencies()
        )

        XCTAssertThrowsError(try provider.start { harness.record($0) }) {
            XCTAssertTrue(
                $0 is AppleOAuthLiveProviderHarness.HarnessError
            )
        }
        XCTAssertNil(harness.request)
        XCTAssertEqual(harness.performCount, 0)
    }

    func testMissingAnchorStopsBeforeRequestConstruction() {
        let harness = AppleOAuthLiveProviderHarness()
        harness.shouldProvideAnchor = false
        let provider = AppleOAuthAuthorizationLiveProvider(
            dependencies: harness.dependencies()
        )

        XCTAssertThrowsError(try provider.start { harness.record($0) }) {
            XCTAssertEqual(
                $0 as? AppleOAuthAuthorizationError,
                .presentationUnavailable
            )
        }
        XCTAssertNil(harness.request)
        XCTAssertEqual(harness.performCount, 0)
    }

    func testOverlappingStartCannotReplaceTheRetainedAttempt() throws {
        let harness = AppleOAuthLiveProviderHarness()
        let provider = AppleOAuthAuthorizationLiveProvider(
            dependencies: harness.dependencies()
        )
        try provider.start { harness.record($0) }
        let retainedController = try XCTUnwrap(harness.controller)

        XCTAssertThrowsError(try provider.start { harness.record($0) }) {
            XCTAssertEqual(
                $0 as? AppleOAuthAuthorizationError,
                .authorizationAlreadyInProgress
            )
        }
        XCTAssertEqual(harness.performCount, 1)
        XCTAssertTrue(
            provider.presentationAnchor(for: retainedController)
                === harness.anchor
        )
    }

    func testProviderFailureCompletesAndReleasesTheMatchingAttempt()
        throws {
        let harness = AppleOAuthLiveProviderHarness()
        let provider = AppleOAuthAuthorizationLiveProvider(
            dependencies: harness.dependencies()
        )
        try provider.start { harness.record($0) }
        let controller = try XCTUnwrap(harness.controller)

        provider.authorizationController(
            controller: controller,
            didCompleteWithError:
                AppleOAuthLiveProviderHarness.HarnessError
                    .provider
        )

        guard case .failure(let error) = harness.result else {
            return XCTFail("Expected the provider failure")
        }
        XCTAssertTrue(
            error is AppleOAuthLiveProviderHarness.HarnessError
        )
        XCTAssertNoThrow(try provider.start { harness.record($0) })
        XCTAssertEqual(harness.performCount, 2)
    }

    func testStaleControllerCannotConsumeTheActiveAttempt() throws {
        let harness = AppleOAuthLiveProviderHarness()
        let provider = AppleOAuthAuthorizationLiveProvider(
            dependencies: harness.dependencies()
        )
        try provider.start { harness.record($0) }
        let controller = try XCTUnwrap(harness.controller)
        let staleController = ASAuthorizationController(
            authorizationRequests: [
                ASAuthorizationAppleIDProvider().createRequest()
            ]
        )

        provider.authorizationController(
            controller: staleController,
            didCompleteWithError:
                AppleOAuthLiveProviderHarness.HarnessError
                    .provider
        )
        XCTAssertNil(harness.result)

        provider.authorizationController(
            controller: controller,
            didCompleteWithError:
                AppleOAuthLiveProviderHarness.HarnessError
                    .provider
        )
        guard case .failure = harness.result else {
            return XCTFail("Expected the matching callback")
        }
    }

    func testCancellationRejectsALateDelegateCallback() throws {
        let harness = AppleOAuthLiveProviderHarness()
        let provider = AppleOAuthAuthorizationLiveProvider(
            dependencies: harness.dependencies()
        )
        try provider.start { harness.record($0) }
        let controller = try XCTUnwrap(harness.controller)

        provider.cancel()
        provider.authorizationController(
            controller: controller,
            didCompleteWithError:
                AppleOAuthLiveProviderHarness.HarnessError
                    .provider
        )

        XCTAssertNil(harness.result)
    }

    func testAuthorizationMapsAppleCredentialAndRegistrationValues() throws {
        var name = PersonNameComponents()
        name.givenName = "Ada"
        name.familyName = "Lovelace"
        let registrationID = UUID()

        let authorization = try AppleOAuthAuthorizationLiveProvider
            .authorization(
                identityToken: Data("identity-token".utf8),
                authorizationCode: Data("authorization-code".utf8),
                fullName: name,
                nonce: "nonce",
                registrationID: registrationID
            )

        XCTAssertEqual(authorization.credentials.provider, .apple)
        XCTAssertEqual(authorization.credentials.idToken, "identity-token")
        XCTAssertNil(authorization.credentials.accessToken)
        XCTAssertEqual(authorization.credentials.nonce, "nonce")
        XCTAssertEqual(authorization.profileMetadata.givenName, "Ada")
        XCTAssertEqual(authorization.profileMetadata.familyName, "Lovelace")
        XCTAssertEqual(
            authorization.appleCredentialRegistration,
            AppleOAuthCredentialRegistration(
                registrationID: registrationID,
                authorizationCode: "authorization-code"
            )
        )
    }

    func testAuthorizationRejectsMissingAndMalformedCredentialData() {
        assertAuthorizationFailure(
            identityToken: nil,
            authorizationCode: Data("code".utf8),
            expected: .missingIdentityToken
        )
        assertAuthorizationFailure(
            identityToken: Data("token".utf8),
            authorizationCode: nil,
            expected: .missingAuthorizationCode
        )
        assertAuthorizationFailure(
            identityToken: Data([0xFF]),
            authorizationCode: Data("code".utf8),
            expected: .invalidIdentityTokenEncoding
        )
        assertAuthorizationFailure(
            identityToken: Data("token".utf8),
            authorizationCode: Data(),
            expected: .invalidAuthorizationCodeEncoding
        )
    }

    func testNonceAndHashUtilitiesPreserveTheAppleContract() throws {
        let nonce = try AppleOAuthAuthorizationLiveProvider
            .randomNonceString()

        XCTAssertEqual(nonce.count, 32)
        XCTAssertTrue(
            nonce.allSatisfy {
                "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._"
                    .contains($0)
            }
        )
        XCTAssertEqual(
            AppleOAuthAuthorizationLiveProvider.sha256("nonce"),
            "78377b525757b494427f89014f97d79928f3938d14eb51e20fb5dec9834eb304"
        )
    }

    private func assertAuthorizationFailure(
        identityToken: Data?,
        authorizationCode: Data?,
        expected: AppleOAuthAuthorizationError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try AppleOAuthAuthorizationLiveProvider.authorization(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                fullName: nil,
                nonce: "nonce",
                registrationID: UUID()
            ),
            file: file,
            line: line
        ) {
            XCTAssertEqual(
                $0 as? AppleOAuthAuthorizationError,
                expected,
                file: file,
                line: line
            )
        }
    }
}
