import Foundation
@testable import Merian
import XCTest

@MainActor
final class OAuthSignInCoordinatorTests: XCTestCase {
    func testExistingAccountUsesReplacementAndSharedCompletionOrder()
        async throws {
        let source = OAuthSignInCoordinatorHarness.session(
            isAnonymous: false
        )
        let target = OAuthSignInCoordinatorHarness.session(
            isAnonymous: false
        )
        let harness = OAuthSignInCoordinatorHarness(
            source: source,
            replacement: target
        )
        var didMutateSession = false

        let completion = try await coordinator(harness).complete(
            credentials: credentials(),
            profileMetadata: metadata(),
            registerProviderCredential: nil,
            ownedBy: harness.transition,
            didMutateSession: {
                didMutateSession = true
            }
        )

        XCTAssertTrue(didMutateSession)
        XCTAssertEqual(completion.previousUserID, source.userID.uuidString)
        XCTAssertEqual(completion.session, target)
        XCTAssertEqual(harness.metadataProvider, .google)
        XCTAssertEqual(harness.metadata, metadata())
        XCTAssertEqual(harness.events, [
            "verify-optional",
            "phase-installingSession",
            "replace",
            "adopt-replacement-boundary",
            "matches",
            "read-sdk",
            "matches",
            "persist-metadata",
            "publish-session",
            "phase-bindingPurchases",
            "link-telemetry",
            "matches",
            "provider-ready",
            "begin-entitlement",
            "verify",
            "refresh-public-author",
            "phase-finalizing",
            "verify",
            "publish-author-change",
            "mark-authenticated-oauth"
        ])
    }

    func testAnonymousDirectLinkRetiresGhostProofAfterSameUUIDAdoption()
        async throws {
        let userID = UUID()
        let source = OAuthSignInCoordinatorHarness.session(
            userID: userID,
            isAnonymous: true
        )
        let linked = OAuthSignInCoordinatorHarness.session(
            userID: userID,
            isAnonymous: false
        )
        let harness = OAuthSignInCoordinatorHarness(
            source: source,
            directLink: linked
        )

        let completion = try await coordinator(harness).complete(
            credentials: credentials(),
            profileMetadata: OAuthProfileMetadata(),
            registerProviderCredential: nil,
            ownedBy: harness.transition,
            didMutateSession: {}
        )

        XCTAssertEqual(completion.session, linked)
        XCTAssertTrue(harness.events.contains("clear-ghost-merges"))
        XCTAssertFalse(harness.events.contains("replace"))
        XCTAssertFalse(harness.events.contains("persist-metadata"))
        XCTAssertFalse(harness.events.contains("refresh-public-author"))
        XCTAssertLessThan(
            try XCTUnwrap(harness.events.firstIndex(of: "adopt")),
            try XCTUnwrap(
                harness.events.firstIndex(of: "clear-ghost-merges")
            )
        )
    }

    func testIdentityConflictPersistsGhostProofBeforeReplacement()
        async throws {
        let source = OAuthSignInCoordinatorHarness.session(
            isAnonymous: true
        )
        let target = OAuthSignInCoordinatorHarness.session(
            isAnonymous: false
        )
        let harness = OAuthSignInCoordinatorHarness(
            source: source,
            replacement: target
        )
        harness.linkError = OAuthSignInCoordinatorTestError.identityConflict
        harness.shouldUseGhostMergeFallback = true

        _ = try await coordinator(harness).complete(
            credentials: credentials(idToken: try identityToken()),
            profileMetadata: OAuthProfileMetadata(),
            registerProviderCredential: nil,
            ownedBy: harness.transition,
            didMutateSession: {}
        )

        XCTAssertEqual(harness.preparedProviderSubject, "provider-subject")
        XCTAssertLessThan(
            try XCTUnwrap(
                harness.events.firstIndex(of: "prepare-ghost-merge")
            ),
            try XCTUnwrap(harness.events.firstIndex(of: "replace"))
        )
        XCTAssertLessThan(
            try XCTUnwrap(harness.events.firstIndex(of: "replace")),
            try XCTUnwrap(
                harness.events.firstIndex(of: "complete-ghost-merge")
            )
        )
    }

    func testRequiredProviderCredentialPrecedesMetadataAndPurchaseBinding()
        async throws {
        let source = OAuthSignInCoordinatorHarness.session(
            isAnonymous: false
        )
        let target = OAuthSignInCoordinatorHarness.session(
            isAnonymous: false
        )
        let harness = OAuthSignInCoordinatorHarness(
            source: source,
            replacement: target,
            provider: .apple
        )

        _ = try await coordinator(harness).complete(
            credentials: credentials(provider: .apple),
            profileMetadata: metadata(),
            registerProviderCredential: harness.registration(),
            ownedBy: harness.transition,
            didMutateSession: {}
        )

        XCTAssertEqual(harness.registeredUserID, target.userID)
        XCTAssertLessThan(
            try XCTUnwrap(
                harness.events.firstIndex(
                    of: "register-provider-credential"
                )
            ),
            try XCTUnwrap(
                harness.events.firstIndex(of: "persist-metadata")
            )
        )
        XCTAssertLessThan(
            try XCTUnwrap(
                harness.events.firstIndex(of: "persist-metadata")
            ),
            try XCTUnwrap(
                harness.events.firstIndex(of: "phase-bindingPurchases")
            )
        )
    }

    func testProviderCredentialFailureStopsBeforeMetadataAndPurchaseBinding()
        async {
        let source = OAuthSignInCoordinatorHarness.session(
            isAnonymous: false
        )
        let target = OAuthSignInCoordinatorHarness.session(
            isAnonymous: false
        )
        let harness = OAuthSignInCoordinatorHarness(
            source: source,
            replacement: target,
            provider: .apple
        )
        harness.registrationError = OAuthSignInCoordinatorTestError
            .credentialRegistration

        do {
            _ = try await coordinator(harness).complete(
                credentials: credentials(provider: .apple),
                profileMetadata: metadata(),
                registerProviderCredential: harness.registration(),
                ownedBy: harness.transition,
                didMutateSession: {}
            )
            XCTFail("Credential registration must gate shared completion")
        } catch OAuthSignInCoordinatorTestError.credentialRegistration {
            XCTAssertFalse(harness.events.contains("persist-metadata"))
            XCTAssertFalse(harness.events.contains("publish-session"))
            XCTAssertFalse(harness.events.contains("begin-entitlement"))
            XCTAssertFalse(
                harness.events.contains("mark-authenticated-oauth")
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAppleRequiresCredentialRegistrationBeforeSessionMutation() async {
        let source = OAuthSignInCoordinatorHarness.session(
            isAnonymous: false
        )
        let target = OAuthSignInCoordinatorHarness.session(
            isAnonymous: false
        )
        let harness = OAuthSignInCoordinatorHarness(
            source: source,
            replacement: target,
            provider: .apple
        )

        do {
            _ = try await coordinator(harness).complete(
                credentials: credentials(provider: .apple),
                profileMetadata: metadata(),
                registerProviderCredential: nil,
                ownedBy: harness.transition,
                didMutateSession: {}
            )
            XCTFail("Apple sign-in must require credential registration")
        } catch OAuthSignInWorkflowError
            .invalidProviderCredentialRegistrationConfiguration {
            XCTAssertTrue(harness.events.isEmpty)
            XCTAssertEqual(harness.sdkSession, source)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGoogleRejectsCredentialRegistrationBeforeSessionMutation() async {
        let source = OAuthSignInCoordinatorHarness.session(
            isAnonymous: false
        )
        let target = OAuthSignInCoordinatorHarness.session(
            isAnonymous: false
        )
        let harness = OAuthSignInCoordinatorHarness(
            source: source,
            replacement: target
        )

        do {
            _ = try await coordinator(harness).complete(
                credentials: credentials(),
                profileMetadata: metadata(),
                registerProviderCredential: harness.registration(),
                ownedBy: harness.transition,
                didMutateSession: {}
            )
            XCTFail("Google sign-in must not invoke Apple registration")
        } catch OAuthSignInWorkflowError
            .invalidProviderCredentialRegistrationConfiguration {
            XCTAssertTrue(harness.events.isEmpty)
            XCTAssertEqual(harness.sdkSession, source)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProviderMustMatchOwnedTransitionBeforeSessionMutation() async {
        let source = OAuthSignInCoordinatorHarness.session(
            isAnonymous: false
        )
        let target = OAuthSignInCoordinatorHarness.session(
            isAnonymous: false
        )
        let harness = OAuthSignInCoordinatorHarness(
            source: source,
            replacement: target
        )

        do {
            _ = try await coordinator(harness).complete(
                credentials: credentials(provider: .apple),
                profileMetadata: metadata(),
                registerProviderCredential: harness.registration(),
                ownedBy: harness.transition,
                didMutateSession: {}
            )
            XCTFail("OAuth credentials must match the transition provider")
        } catch OAuthSignInWorkflowError.providerTransitionMismatch {
            XCTAssertTrue(harness.events.isEmpty)
            XCTAssertEqual(harness.sdkSession, source)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMetadataFailureContinuesWithoutPublicAuthorRefresh()
        async throws {
        let source = OAuthSignInCoordinatorHarness.session(
            isAnonymous: false
        )
        let target = OAuthSignInCoordinatorHarness.session(
            isAnonymous: false
        )
        let harness = OAuthSignInCoordinatorHarness(
            source: source,
            replacement: target
        )
        harness.metadataPersists = false

        let completion = try await coordinator(harness).complete(
            credentials: credentials(),
            profileMetadata: metadata(),
            registerProviderCredential: nil,
            ownedBy: harness.transition,
            didMutateSession: {}
        )

        XCTAssertEqual(completion.session, target)
        XCTAssertTrue(harness.events.contains("persist-metadata"))
        XCTAssertFalse(harness.events.contains("refresh-public-author"))
        XCTAssertTrue(harness.events.contains("begin-entitlement"))
        XCTAssertTrue(harness.events.contains("publish-author-change"))
        XCTAssertTrue(harness.events.contains("mark-authenticated-oauth"))
    }

    func testPendingPurchaseHandoffStopsBeforeProviderMutation() async {
        let source = OAuthSignInCoordinatorHarness.session(
            isAnonymous: true
        )
        let harness = OAuthSignInCoordinatorHarness(source: source)
        harness.purchaseHandoffCompletes = false

        do {
            _ = try await coordinator(harness).complete(
                credentials: credentials(),
                profileMetadata: OAuthProfileMetadata(),
                registerProviderCredential: nil,
                ownedBy: harness.transition,
                didMutateSession: {}
            )
            XCTFail("A pending purchase handoff must stop OAuth mutation")
        } catch SupabaseAuthTransitionError
            .signOutPurchaseContinuityPending {
            XCTAssertFalse(harness.events.contains("link"))
            XCTAssertFalse(harness.events.contains("replace"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProviderReadinessFailureStopsBeforeEntitlementAndFinalCommit()
        async {
        let source = OAuthSignInCoordinatorHarness.session(
            isAnonymous: false
        )
        let target = OAuthSignInCoordinatorHarness.session(
            isAnonymous: false
        )
        let harness = OAuthSignInCoordinatorHarness(
            source: source,
            replacement: target
        )
        harness.providerIdentityReady = false

        do {
            _ = try await coordinator(harness).complete(
                credentials: credentials(),
                profileMetadata: OAuthProfileMetadata(),
                registerProviderCredential: nil,
                ownedBy: harness.transition,
                didMutateSession: {}
            )
            XCTFail("Provider readiness must precede entitlement")
        } catch SupabaseAuthTransitionError.signOutSessionChanged {
            XCTAssertFalse(harness.events.contains("begin-entitlement"))
            XCTAssertFalse(
                harness.events.contains("publish-author-change")
            )
            XCTAssertFalse(
                harness.events.contains("mark-authenticated-oauth")
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCancelledAnonymousUpgradeDoesNotReachProviderMutation() async {
        let source = OAuthSignInCoordinatorHarness.session(
            isAnonymous: true
        )
        let linked = OAuthSignInCoordinatorHarness.session(
            userID: source.userID,
            isAnonymous: false
        )
        let harness = OAuthSignInCoordinatorHarness(
            source: source,
            directLink: linked
        )
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await self.coordinator(harness).complete(
                credentials: self.credentials(),
                profileMetadata: OAuthProfileMetadata(),
                registerProviderCredential: nil,
                ownedBy: harness.transition,
                didMutateSession: {}
            )
        }

        do {
            _ = try await task.value
            XCTFail("Cancellation must stop before direct provider linking")
        } catch is CancellationError {
            XCTAssertFalse(harness.events.contains("link"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func coordinator(
        _ harness: OAuthSignInCoordinatorHarness
    ) -> OAuthSignInCoordinator {
        OAuthSignInCoordinator(dependencies: harness.dependencies())
    }

    private func credentials(
        provider: AuthTransitionProvider = .google,
        idToken: String = "header.payload.signature"
    ) -> OAuthSignInCredentials {
        OAuthSignInCredentials(
            provider: provider,
            idToken: idToken,
            accessToken: provider == .google ? "access-token" : nil,
            nonce: provider == .apple ? "nonce" : nil
        )
    }

    private func metadata() -> OAuthProfileMetadata {
        OAuthProfileMetadata(
            displayName: "Ada Lovelace",
            givenName: "Ada",
            familyName: "Lovelace",
            avatarURL: "https://example.test/avatar.jpg"
        )
    }

    private func identityToken() throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: ["sub": "provider-subject"]
        )
        let payload = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(payload).signature"
    }
}
