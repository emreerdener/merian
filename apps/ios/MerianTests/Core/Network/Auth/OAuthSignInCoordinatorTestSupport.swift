import Foundation
@testable import Merian

actor OAuthSignInCoordinatorTestGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var released = false

    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitUntilWaiterCount(_ expectedCount: Int) async {
        while !released && continuations.count < expectedCount {
            await Task.yield()
        }
    }

    func release() {
        released = true
        let pending = continuations
        continuations.removeAll(keepingCapacity: false)
        pending.forEach { $0.resume() }
    }
}

@MainActor
final class OAuthSignInCoordinatorHarness {
    let transition: AuthTransitionToken
    var events: [String] = []
    var ownsTransition = true
    var isSignOutInProgress = false
    var expectedSession: OAuthSignInSession?
    var sdkSession: OAuthSignInSession?
    var directLinkSession: OAuthSignInSession?
    var replacementSession: OAuthSignInSession?
    var linkError: Error?
    var replacementError: Error?
    var registrationError: Error?
    var purchaseHandoffCompletes = true
    var providerIdentityReady = true
    var metadataPersists = true
    var shouldUseGhostMergeFallback = false
    var completedGhostMerge = true
    var preparedProviderSubject: String?
    var metadata: OAuthProfileMetadata?
    var metadataProvider: AuthTransitionProvider?
    var registeredUserID: UUID?
    var replacementGate: OAuthSignInCoordinatorTestGate?
    var registrationGate: OAuthSignInCoordinatorTestGate?
    var metadataGate: OAuthSignInCoordinatorTestGate?
    var telemetryGate: OAuthSignInCoordinatorTestGate?
    var entitlementGate: OAuthSignInCoordinatorTestGate?
    var publicAuthorGate: OAuthSignInCoordinatorTestGate?

    init(
        source: OAuthSignInSession?,
        directLink: OAuthSignInSession? = nil,
        replacement: OAuthSignInSession? = nil,
        provider: AuthTransitionProvider = .google
    ) {
        transition = AuthTransitionToken(
            id: UUID(),
            kind: .oauth(provider)
        )
        expectedSession = source
        sdkSession = source
        directLinkSession = directLink
        replacementSession = replacement
    }

    func dependencies() -> OAuthSignInCoordinationDependencies {
        OAuthSignInCoordinationDependencies(
            session: OAuthSignInSessionBoundary(
                ownsTransition: { token in
                    self.ownsTransition && token == self.transition
                },
                isSignOutInProgress: {
                    self.isSignOutInProgress
                },
                expectedSession: { token in
                    guard token == self.transition else { return nil }
                    return self.expectedSession?.identity
                },
                verifyExpectedSessionIfPresent: { token in
                    self.events.append("verify-optional")
                    guard self.ownsTransition, token == self.transition else {
                        throw SupabaseAuthTransitionError
                            .signOutSessionChanged
                    }
                    guard let expected = self.expectedSession else {
                        guard self.sdkSession == nil else {
                            throw SupabaseAuthTransitionError
                                .signOutSessionChanged
                        }
                        return nil
                    }
                    guard self.sdkSession == expected else {
                        throw SupabaseAuthTransitionError
                            .signOutSessionChanged
                    }
                    return expected
                },
                verifyExpectedSession: { token in
                    self.events.append("verify")
                    guard self.ownsTransition,
                          token == self.transition,
                          let expected = self.expectedSession,
                          self.sdkSession == expected else {
                        throw SupabaseAuthTransitionError
                            .signOutSessionChanged
                    }
                    return expected
                },
                readSDKSession: {
                    self.events.append("read-sdk")
                    guard let sdkSession = self.sdkSession else {
                        throw SupabaseAuthTransitionError
                            .signOutSessionChanged
                    }
                    return sdkSession
                },
                linkIdentity: { _ in
                    self.events.append("link")
                    if let linkError = self.linkError {
                        throw linkError
                    }
                    guard let directLinkSession = self.directLinkSession else {
                        throw SupabaseAuthTransitionError
                            .signOutSessionChanged
                    }
                    self.sdkSession = directLinkSession
                },
                replaceAndAdoptSession: { _, token, didMutateSession in
                    self.events.append("replace")
                    if let replacementError = self.replacementError {
                        throw replacementError
                    }
                    if let gate = self.replacementGate {
                        await gate.wait()
                    }
                    guard let replacementSession = self.replacementSession
                    else {
                        throw SupabaseAuthTransitionError
                            .signOutSessionChanged
                    }
                    self.sdkSession = replacementSession
                    didMutateSession()
                    guard self.ownsTransition,
                          token == self.transition,
                          self.sdkSession == replacementSession else {
                        throw SupabaseAuthTransitionError
                            .signOutSessionChanged
                    }
                    self.expectedSession = replacementSession
                    self.events.append("adopt-replacement-boundary")
                    try Task.checkCancellation()
                    return replacementSession
                },
                adoptSession: { session, token in
                    self.events.append("adopt")
                    guard self.ownsTransition,
                          token == self.transition,
                          self.sdkSession == session else {
                        return false
                    }
                    self.expectedSession = session
                    return true
                },
                currentSessionMatchesTransition: { token in
                    self.events.append("matches")
                    return self.ownsTransition
                        && token == self.transition
                        && self.sdkSession == self.expectedSession
                },
                updateTransition: { token, phase in
                    guard token == self.transition else { return }
                    self.events.append("phase-\(phase.rawValue)")
                },
                publishAuthenticatedSession: { token in
                    self.events.append("publish-session")
                    guard self.ownsTransition,
                          token == self.transition,
                          let expected = self.expectedSession,
                          self.sdkSession == expected else {
                        throw SupabaseAuthTransitionError
                            .signOutSessionChanged
                    }
                    return expected
                }
            ),
            merge: OAuthSignInMergeBoundary(
                completePendingPurchaseHandoff: { _, _ in
                    self.events.append("complete-purchase-handoff")
                    return self.purchaseHandoffCompletes
                },
                requiresProviderBoundGhostMerge: { _ in
                    self.events.append("classify-link-error")
                    return self.shouldUseGhostMergeFallback
                },
                prepareGhostMerge: { _, _, providerSubject, _ in
                    self.events.append("prepare-ghost-merge")
                    self.preparedProviderSubject = providerSubject
                },
                clearGhostMerges: { _ in
                    self.events.append("clear-ghost-merges")
                },
                completePendingGhostMerge: { _, _ in
                    self.events.append("complete-ghost-merge")
                    return self.completedGhostMerge
                }
            ),
            completion: OAuthSignInCompletionBoundary(
                persistProfileMetadata: { metadata, provider, _, _ in
                    self.events.append("persist-metadata")
                    if let gate = self.metadataGate {
                        await gate.wait()
                    }
                    self.metadata = metadata
                    self.metadataProvider = provider
                    return self.metadataPersists
                },
                ensureTelemetryLinked: { _, _ in
                    self.events.append("link-telemetry")
                    if let gate = self.telemetryGate {
                        await gate.wait()
                    }
                },
                providerIdentityIsReady: { _ in
                    self.events.append("provider-ready")
                    return self.providerIdentityReady
                },
                beginEntitlementSession: { _, _ in
                    self.events.append("begin-entitlement")
                    if let gate = self.entitlementGate {
                        await gate.wait()
                    }
                },
                refreshPublicAuthorIdentity: { _, _ in
                    self.events.append("refresh-public-author")
                    if let gate = self.publicAuthorGate {
                        await gate.wait()
                    }
                    return true
                },
                publishPublicAuthorIdentityChange: { _, _ in
                    self.events.append("publish-author-change")
                },
                markAuthenticatedOAuth: {
                    self.events.append("mark-authenticated-oauth")
                }
            )
        )
    }

    func registration() -> OAuthProviderCredentialRegistration {
        { userID, _ in
            self.events.append("register-provider-credential")
            if let gate = self.registrationGate {
                await gate.wait()
            }
            if let registrationError = self.registrationError {
                throw registrationError
            }
            self.registeredUserID = userID
        }
    }

    static func session(
        userID: UUID = UUID(),
        isAnonymous: Bool
    ) -> OAuthSignInSession {
        OAuthSignInSession(
            identity: AuthTransitionSession(
                userID: userID,
                isAnonymous: isAnonymous
            )
        )
    }
}

enum OAuthSignInCoordinatorTestError: Error {
    case identityConflict
    case credentialRegistration
}
