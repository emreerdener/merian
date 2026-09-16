@testable import Merian
import UIKit
import XCTest

private actor GoogleOAuthResponseGate {
    private var continuation: CheckedContinuation<
        GoogleOAuthAuthorizationResponse,
        Never
    >?
    private var didStart = false

    func waitForResponse() async -> GoogleOAuthAuthorizationResponse {
        didStart = true
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        while !didStart {
            await Task.yield()
        }
    }

    func resume(with response: GoogleOAuthAuthorizationResponse) {
        continuation?.resume(returning: response)
        continuation = nil
    }
}

@MainActor
final class GoogleOAuthLiveProviderTests: XCTestCase {
    func testMissingPresentationContextStopsBeforeGoogleSDK() async throws {
        var didCallSDK = false
        let provider = GoogleOAuthAuthorizationLiveProvider(
            dependencies: GoogleOAuthAuthorizationLiveDependencies(
                presentingViewController: { nil },
                signIn: { _ in
                    didCallSDK = true
                    return Self.response()
                }
            )
        )

        let outcome = try await provider.authorize()

        XCTAssertEqual(outcome, .presentationUnavailable)
        XCTAssertFalse(didCallSDK)
    }

    func testGoogleResponseMapsToProviderNeutralAuthorization() async throws {
        let viewController = UIViewController()
        let provider = GoogleOAuthAuthorizationLiveProvider(
            dependencies: GoogleOAuthAuthorizationLiveDependencies(
                presentingViewController: { viewController },
                signIn: { presentedViewController in
                    XCTAssertTrue(presentedViewController === viewController)
                    return Self.response()
                }
            )
        )

        let outcome = try await provider.authorize()

        guard case .authorized(let authorization) = outcome else {
            return XCTFail("Expected a provider-neutral authorization")
        }
        XCTAssertEqual(authorization.credentials.provider, .google)
        XCTAssertEqual(authorization.credentials.idToken, "identity-token")
        XCTAssertEqual(authorization.credentials.accessToken, "access-token")
        XCTAssertNil(authorization.credentials.nonce)
        XCTAssertEqual(authorization.profileMetadata.displayName, "Ada Lovelace")
        XCTAssertEqual(authorization.profileMetadata.givenName, "Ada")
        XCTAssertEqual(authorization.profileMetadata.familyName, "Lovelace")
        XCTAssertEqual(
            authorization.profileMetadata.avatarURL,
            "https://example.test/avatar"
        )
        XCTAssertNil(authorization.appleCredentialRegistration)
    }

    func testMissingGoogleIdentityTokenRemainsAProviderOutcome() async throws {
        let provider = GoogleOAuthAuthorizationLiveProvider(
            dependencies: GoogleOAuthAuthorizationLiveDependencies(
                presentingViewController: { UIViewController() },
                signIn: { _ in
                    Self.response(idToken: nil)
                }
            )
        )

        let outcome = try await provider.authorize()

        XCTAssertEqual(outcome, .missingIdentityToken)
    }

    func testPreflightCancellationStopsBeforeGoogleSDK() async {
        var didCallSDK = false
        let provider = GoogleOAuthAuthorizationLiveProvider(
            dependencies: GoogleOAuthAuthorizationLiveDependencies(
                presentingViewController: { UIViewController() },
                signIn: { _ in
                    didCallSDK = true
                    return Self.response()
                }
            )
        )
        let task = Task { @MainActor in
            try await provider.authorize()
        }

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected provider cancellation")
        } catch is CancellationError {
            XCTAssertFalse(didCallSDK)
        } catch {
            XCTFail("Unexpected error: \(type(of: error))")
        }
    }

    func testCancellationAfterGoogleReturnRejectsMappedAuthorization() async {
        let gate = GoogleOAuthResponseGate()
        let provider = GoogleOAuthAuthorizationLiveProvider(
            dependencies: GoogleOAuthAuthorizationLiveDependencies(
                presentingViewController: { UIViewController() },
                signIn: { _ in
                    await gate.waitForResponse()
                }
            )
        )
        let task = Task { @MainActor in
            try await provider.authorize()
        }
        await gate.waitUntilStarted()

        task.cancel()
        await gate.resume(with: Self.response())

        do {
            _ = try await task.value
            XCTFail("Expected provider cancellation")
        } catch is CancellationError {
            // Expected: the returned provider value cannot advance completion.
        } catch {
            XCTFail("Unexpected error: \(type(of: error))")
        }
    }

    private static func response(
        idToken: String? = "identity-token"
    ) -> GoogleOAuthAuthorizationResponse {
        GoogleOAuthAuthorizationResponse(
            idToken: idToken,
            accessToken: "access-token",
            displayName: " Ada Lovelace ",
            givenName: "Ada",
            familyName: "Lovelace",
            avatarURL: "https://example.test/avatar"
        )
    }
}
