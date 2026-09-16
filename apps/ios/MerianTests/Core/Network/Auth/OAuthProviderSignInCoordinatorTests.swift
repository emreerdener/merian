import Foundation
@testable import Merian
import XCTest

private actor OAuthProviderCompletionGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var didStart = false

    func wait() async {
        didStart = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        while !didStart {
            await Task.yield()
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class OAuthProviderSignInCoordinatorHarness {
    enum HarnessError: Error {
        case authorization
        case completion
        case verification
    }

    let sourceSession = AuthTransitionSession(
        userID: UUID(),
        isAnonymous: true
    )
    var googleOutcome: GoogleOAuthAuthorizationOutcome = .authorized(
        OAuthProviderSignInCoordinatorHarness.authorization(.google)
    )
    var authorizationError: Error?
    var appleStartError: Error?
    var completionError: Error?
    var completionGate: OAuthProviderCompletionGate?
    var verificationError: Error?
    var shouldRecordMutation = false

    private(set) var activeTransition: AuthTransitionToken?
    private(set) var appleCompletion: OAuthProviderAuthorizationCompletion?
    private(set) var completedAuthorization: OAuthProviderAuthorization?
    private(set) var diagnostics: [OAuthProviderSignInDiagnostic] = []
    private(set) var events: [String] = []
    private(set) var recoveredMutation = false
    private(set) var recoveredSource: AuthTransitionSession?

    func dependencies() -> OAuthProviderSignInDependencies {
        OAuthProviderSignInDependencies(
            transition: OAuthProviderSignInTransitionBoundary(
                begin: { provider in
                    guard self.activeTransition == nil else { return nil }
                    let transition = AuthTransitionToken(
                        id: UUID(),
                        kind: .oauth(provider)
                    )
                    self.activeTransition = transition
                    self.events.append("begin-\(provider.rawValue)")
                    return transition
                },
                updateAwaitingProvider: { transition in
                    XCTAssertEqual(self.activeTransition, transition)
                    self.events.append("awaiting-provider")
                },
                activeTransitionID: {
                    self.activeTransition?.id
                },
                sourceSession: { transition in
                    XCTAssertEqual(self.activeTransition, transition)
                    return self.sourceSession
                },
                verifyExpectedSessionIfPresent: { transition in
                    XCTAssertEqual(self.activeTransition, transition)
                    self.events.append("verify-session")
                    if let verificationError = self.verificationError {
                        throw verificationError
                    }
                },
                finish: { transition in
                    self.events.append("finish")
                    if self.activeTransition == transition {
                        self.activeTransition = nil
                    }
                }
            ),
            authorization: OAuthProviderAuthorizationBoundary(
                authorizeWithGoogle: {
                    self.events.append("authorize-google")
                    if let authorizationError = self.authorizationError {
                        throw authorizationError
                    }
                    return self.googleOutcome
                },
                startAppleAuthorization: { completion in
                    self.events.append("start-apple")
                    if let appleStartError = self.appleStartError {
                        throw appleStartError
                    }
                    self.appleCompletion = completion
                },
                cancelAppleAuthorization: {
                    self.events.append("cancel-apple")
                    self.appleCompletion = nil
                }
            ),
            completion: OAuthProviderSignInCompletionBoundary(
                complete: { authorization, transition, didMutateSession in
                    XCTAssertEqual(self.activeTransition, transition)
                    self.events.append("complete")
                    self.completedAuthorization = authorization
                    if self.shouldRecordMutation {
                        didMutateSession()
                    }
                    if let completionGate = self.completionGate {
                        await completionGate.wait()
                        try Task.checkCancellation()
                    }
                    if let completionError = self.completionError {
                        throw completionError
                    }
                },
                recoverAfterFailure: { didMutateSession, source, transition in
                    XCTAssertEqual(self.activeTransition, transition)
                    self.events.append("recover")
                    self.recoveredMutation = didMutateSession
                    self.recoveredSource = source
                }
            ),
            diagnostics: OAuthProviderSignInDiagnostics(
                report: { diagnostic, _ in
                    self.diagnostics.append(diagnostic)
                    self.events.append("diagnostic")
                }
            )
        )
    }

    func replaceActiveTransition() {
        activeTransition = AuthTransitionToken(
            id: UUID(),
            kind: .oauth(.google)
        )
    }

    static func authorization(
        _ provider: AuthTransitionProvider
    ) -> OAuthProviderAuthorization {
        OAuthProviderAuthorization(
            credentials: OAuthSignInCredentials(
                provider: provider,
                idToken: "identity-token",
                accessToken: provider == .google ? "access-token" : nil,
                nonce: provider == .apple ? "nonce" : nil
            ),
            profileMetadata: OAuthProfileMetadata(
                displayName: "Ada Lovelace"
            ),
            appleCredentialRegistration: provider == .apple
                ? AppleOAuthCredentialRegistration(
                    registrationID: UUID(),
                    authorizationCode: "authorization-code"
                )
                : nil
        )
    }
}

@MainActor
final class OAuthProviderSignInCoordinatorTests: XCTestCase {
    func testRejectedGoogleTransitionDoesNotPresentProvider() async {
        let harness = OAuthProviderSignInCoordinatorHarness()
        harness.replaceActiveTransition()

        await OAuthProviderSignInCoordinator().signInWithGoogle(
            dependencies: harness.dependencies()
        )

        XCTAssertEqual(harness.diagnostics, [.transitionRejected(.google)])
        XCTAssertFalse(harness.events.contains("authorize-google"))
        XCTAssertNotNil(harness.activeTransition)
    }

    func testRejectedAppleTransitionDoesNotStartAuthorization() {
        let harness = OAuthProviderSignInCoordinatorHarness()
        harness.replaceActiveTransition()

        OAuthProviderSignInCoordinator().startAppleSignIn(
            dependencies: harness.dependencies()
        )

        XCTAssertEqual(harness.diagnostics, [.transitionRejected(.apple)])
        XCTAssertFalse(harness.events.contains("start-apple"))
        XCTAssertNotNil(harness.activeTransition)
    }

    func testGoogleSuccessPreservesAdmissionVerificationAndCompletionOrder()
        async {
        let harness = OAuthProviderSignInCoordinatorHarness()
        let coordinator = OAuthProviderSignInCoordinator()

        await coordinator.signInWithGoogle(
            dependencies: harness.dependencies()
        )

        XCTAssertEqual(
            harness.completedAuthorization?.credentials.provider,
            .google
        )
        XCTAssertEqual(harness.diagnostics, [.completed(.google)])
        XCTAssertEqual(harness.events, [
            "begin-google",
            "awaiting-provider",
            "authorize-google",
            "verify-session",
            "complete",
            "diagnostic",
            "finish"
        ])
        XCTAssertNil(harness.activeTransition)
    }

    func testGooglePresentationFailureStopsBeforeSessionVerification() async {
        let harness = OAuthProviderSignInCoordinatorHarness()
        harness.googleOutcome = .presentationUnavailable

        await OAuthProviderSignInCoordinator().signInWithGoogle(
            dependencies: harness.dependencies()
        )

        XCTAssertEqual(
            harness.diagnostics,
            [.googlePresentationUnavailable]
        )
        XCTAssertFalse(harness.events.contains("verify-session"))
        XCTAssertFalse(harness.events.contains("complete"))
        XCTAssertNil(harness.activeTransition)
    }

    func testGoogleMissingTokenRevalidatesSessionBeforeStopping() async {
        let harness = OAuthProviderSignInCoordinatorHarness()
        harness.googleOutcome = .missingIdentityToken

        await OAuthProviderSignInCoordinator().signInWithGoogle(
            dependencies: harness.dependencies()
        )

        XCTAssertEqual(
            harness.diagnostics,
            [.googleMissingIdentityToken]
        )
        XCTAssertTrue(harness.events.contains("verify-session"))
        XCTAssertFalse(harness.events.contains("complete"))
    }

    func testGoogleProviderFailureRunsRecoveryAndFinishesTransition() async {
        let harness = OAuthProviderSignInCoordinatorHarness()
        harness.authorizationError = OAuthProviderSignInCoordinatorHarness
            .HarnessError.authorization

        await OAuthProviderSignInCoordinator().signInWithGoogle(
            dependencies: harness.dependencies()
        )

        XCTAssertEqual(
            harness.diagnostics,
            [.completionFailed(.google)]
        )
        XCTAssertEqual(harness.recoveredSource, harness.sourceSession)
        XCTAssertFalse(harness.recoveredMutation)
        XCTAssertNil(harness.activeTransition)
    }

    func testGoogleCompletionFailureReportsObservedSessionMutation() async {
        let harness = OAuthProviderSignInCoordinatorHarness()
        harness.shouldRecordMutation = true
        harness.completionError = OAuthProviderSignInCoordinatorHarness
            .HarnessError.completion

        await OAuthProviderSignInCoordinator().signInWithGoogle(
            dependencies: harness.dependencies()
        )

        XCTAssertTrue(harness.recoveredMutation)
        XCTAssertEqual(
            harness.diagnostics,
            [.completionFailed(.google)]
        )
    }

    func testAppleStartOwnsTransitionSynchronouslyAndCompletesInTask()
        async {
        let harness = OAuthProviderSignInCoordinatorHarness()
        let coordinator = OAuthProviderSignInCoordinator()
        coordinator.startAppleSignIn(dependencies: harness.dependencies())

        XCTAssertNotNil(harness.activeTransition)
        XCTAssertEqual(
            harness.events,
            ["begin-apple", "awaiting-provider", "start-apple"]
        )

        harness.appleCompletion?(
            .success(
                OAuthProviderSignInCoordinatorHarness.authorization(.apple)
            )
        )
        await waitUntil { harness.activeTransition == nil }

        XCTAssertEqual(
            harness.completedAuthorization?.credentials.provider,
            .apple
        )
        XCTAssertEqual(harness.diagnostics, [.completed(.apple)])
    }

    func testAppleBootstrapFailureFinishesSynchronously() {
        let harness = OAuthProviderSignInCoordinatorHarness()
        harness.appleStartError = AppleOAuthAuthorizationError
            .nonceGenerationFailed(-1)

        OAuthProviderSignInCoordinator().startAppleSignIn(
            dependencies: harness.dependencies()
        )

        XCTAssertNil(harness.activeTransition)
        XCTAssertEqual(harness.diagnostics, [.appleBootstrapFailed])
        XCTAssertFalse(harness.events.contains("complete"))
    }

    func testAppleProviderFailureDoesNotRunSessionRecovery() {
        let harness = OAuthProviderSignInCoordinatorHarness()
        let coordinator = OAuthProviderSignInCoordinator()
        coordinator.startAppleSignIn(dependencies: harness.dependencies())

        harness.appleCompletion?(
            .failure(OAuthProviderSignInCoordinatorHarness.HarnessError.authorization)
        )

        XCTAssertNil(harness.activeTransition)
        XCTAssertEqual(harness.diagnostics, [.appleProviderFailed])
        XCTAssertFalse(harness.events.contains("recover"))
    }

    func testAppleStaleCallbackCannotCompleteReplacementTransition() {
        let harness = OAuthProviderSignInCoordinatorHarness()
        let coordinator = OAuthProviderSignInCoordinator()
        coordinator.startAppleSignIn(dependencies: harness.dependencies())
        harness.replaceActiveTransition()

        harness.appleCompletion?(
            .success(
                OAuthProviderSignInCoordinatorHarness.authorization(.apple)
            )
        )

        XCTAssertEqual(harness.diagnostics, [.appleStaleCallback])
        XCTAssertFalse(harness.events.contains("complete"))
        XCTAssertTrue(harness.events.contains("finish"))
        XCTAssertNotNil(harness.activeTransition)
    }

    func testCancellingPendingAppleAuthorizationReleasesAndFinishesIt() {
        let harness = OAuthProviderSignInCoordinatorHarness()
        let coordinator = OAuthProviderSignInCoordinator()
        coordinator.startAppleSignIn(dependencies: harness.dependencies())

        coordinator.cancel()

        XCTAssertTrue(harness.events.contains("cancel-apple"))
        XCTAssertNil(harness.appleCompletion)
        XCTAssertNil(harness.activeTransition)
    }

    func testAppleCompletionFailureRunsRecoveryWithMutationEvidence() async {
        let harness = OAuthProviderSignInCoordinatorHarness()
        harness.shouldRecordMutation = true
        harness.completionError = OAuthProviderSignInCoordinatorHarness
            .HarnessError.completion
        let coordinator = OAuthProviderSignInCoordinator()
        coordinator.startAppleSignIn(dependencies: harness.dependencies())

        harness.appleCompletion?(
            .success(
                OAuthProviderSignInCoordinatorHarness.authorization(.apple)
            )
        )
        await waitUntil { harness.activeTransition == nil }

        XCTAssertTrue(harness.recoveredMutation)
        XCTAssertEqual(harness.recoveredSource, harness.sourceSession)
        XCTAssertEqual(
            harness.diagnostics,
            [.completionFailed(.apple)]
        )
    }

    func testCancellingAppleCompletionTaskRunsFailureRecovery() async {
        let harness = OAuthProviderSignInCoordinatorHarness()
        let gate = OAuthProviderCompletionGate()
        harness.completionGate = gate
        let coordinator = OAuthProviderSignInCoordinator()
        coordinator.startAppleSignIn(dependencies: harness.dependencies())
        harness.appleCompletion?(
            .success(
                OAuthProviderSignInCoordinatorHarness.authorization(.apple)
            )
        )
        await gate.waitUntilStarted()

        coordinator.cancel()
        await gate.resume()
        await waitUntil { harness.activeTransition == nil }

        XCTAssertTrue(harness.events.contains("recover"))
        XCTAssertEqual(harness.recoveredSource, harness.sourceSession)
        XCTAssertEqual(harness.diagnostics, [.completionFailed(.apple)])
    }

    private func waitUntil(
        _ predicate: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<2_000 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for OAuth provider work.", file: file, line: line)
    }
}
