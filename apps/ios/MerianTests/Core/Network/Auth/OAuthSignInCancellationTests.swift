import Foundation
@testable import Merian
import XCTest

@MainActor
final class OAuthSignInCancellationTests: XCTestCase {
    func testCancellationDuringReplacementAdoptsExactTargetBeforeStoppingCompletion() async {
        let source = OAuthSignInCoordinatorHarness.session(
            isAnonymous: false
        )
        let target = OAuthSignInCoordinatorHarness.session(
            isAnonymous: false
        )
        let gate = OAuthSignInCoordinatorTestGate()
        let harness = OAuthSignInCoordinatorHarness(
            source: source,
            replacement: target
        )
        harness.replacementGate = gate
        var didMutateSession = false

        let attempt = completionTask(
            harness,
            didMutateSession: {
                didMutateSession = true
            }
        )
        await gate.waitUntilWaiterCount(1)
        attempt.cancel()
        await gate.release()
        await expectCancellation(attempt)

        XCTAssertTrue(didMutateSession)
        XCTAssertEqual(harness.sdkSession, target)
        XCTAssertEqual(harness.expectedSession, target)
        XCTAssertTrue(
            harness.events.contains("adopt-replacement-boundary")
        )
        XCTAssertFalse(harness.events.contains("adopt"))
        XCTAssertFalse(harness.events.contains("publish-session"))
    }

    func testCancellationDuringAppleRegistrationStopsBeforeMetadata() async {
        let source = OAuthSignInCoordinatorHarness.session(
            isAnonymous: false
        )
        let target = OAuthSignInCoordinatorHarness.session(
            isAnonymous: false
        )
        let gate = OAuthSignInCoordinatorTestGate()
        let harness = OAuthSignInCoordinatorHarness(
            source: source,
            replacement: target,
            provider: .apple
        )
        harness.registrationGate = gate

        let attempt = completionTask(
            harness,
            provider: .apple,
            registerProviderCredential: harness.registration()
        )
        await gate.waitUntilWaiterCount(1)
        attempt.cancel()
        await gate.release()
        await expectCancellation(attempt)

        XCTAssertFalse(harness.events.contains("persist-metadata"))
        XCTAssertFalse(harness.events.contains("publish-session"))
    }

    func testCancellationDuringMetadataStopsBeforePublication() async {
        let harness = replacementHarness()
        let gate = OAuthSignInCoordinatorTestGate()
        harness.metadataGate = gate

        let attempt = completionTask(harness)
        await gate.waitUntilWaiterCount(1)
        attempt.cancel()
        await gate.release()
        await expectCancellation(attempt)

        XCTAssertFalse(harness.events.contains("publish-session"))
        XCTAssertFalse(harness.events.contains("link-telemetry"))
    }

    func testCancellationDuringTelemetryStopsBeforeEntitlement() async {
        let harness = replacementHarness()
        let gate = OAuthSignInCoordinatorTestGate()
        harness.telemetryGate = gate

        let attempt = completionTask(harness)
        await gate.waitUntilWaiterCount(1)
        attempt.cancel()
        await gate.release()
        await expectCancellation(attempt)

        XCTAssertFalse(harness.events.contains("provider-ready"))
        XCTAssertFalse(harness.events.contains("begin-entitlement"))
        XCTAssertFalse(harness.events.contains("publish-author-change"))
    }

    func testCancellationDuringEntitlementStopsBeforeFinalization() async {
        let harness = replacementHarness()
        let gate = OAuthSignInCoordinatorTestGate()
        harness.entitlementGate = gate

        let attempt = completionTask(harness)
        await gate.waitUntilWaiterCount(1)
        attempt.cancel()
        await gate.release()
        await expectCancellation(attempt)

        XCTAssertFalse(harness.events.contains("refresh-public-author"))
        XCTAssertFalse(harness.events.contains("phase-finalizing"))
        XCTAssertFalse(harness.events.contains("mark-authenticated-oauth"))
    }

    func testCancellationDuringAuthorRefreshStopsBeforeFinalCommit() async {
        let harness = replacementHarness()
        let gate = OAuthSignInCoordinatorTestGate()
        harness.publicAuthorGate = gate

        let attempt = completionTask(harness)
        await gate.waitUntilWaiterCount(1)
        attempt.cancel()
        await gate.release()
        await expectCancellation(attempt)

        XCTAssertFalse(harness.events.contains("phase-finalizing"))
        XCTAssertFalse(harness.events.contains("publish-author-change"))
        XCTAssertFalse(harness.events.contains("mark-authenticated-oauth"))
    }

    private func replacementHarness() -> OAuthSignInCoordinatorHarness {
        OAuthSignInCoordinatorHarness(
            source: OAuthSignInCoordinatorHarness.session(
                isAnonymous: false
            ),
            replacement: OAuthSignInCoordinatorHarness.session(
                isAnonymous: false
            )
        )
    }

    private func completionTask(
        _ harness: OAuthSignInCoordinatorHarness,
        provider: AuthTransitionProvider = .google,
        registerProviderCredential: OAuthProviderCredentialRegistration? = nil,
        didMutateSession: @escaping @MainActor () -> Void = {}
    ) -> Task<OAuthSignInCompletion, Error> {
        Task { @MainActor in
            try await OAuthSignInCoordinator(
                dependencies: harness.dependencies()
            ).complete(
                credentials: OAuthSignInCredentials(
                    provider: provider,
                    idToken: "header.payload.signature",
                    accessToken: provider == .google ? "access-token" : nil,
                    nonce: provider == .apple ? "nonce" : nil
                ),
                profileMetadata: OAuthProfileMetadata(
                    displayName: "Ada Lovelace"
                ),
                registerProviderCredential: registerProviderCredential,
                ownedBy: harness.transition,
                didMutateSession: didMutateSession
            )
        }
    }

    private func expectCancellation(
        _ attempt: Task<OAuthSignInCompletion, Error>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await attempt.value
            XCTFail("Expected OAuth completion cancellation", file: file, line: line)
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
