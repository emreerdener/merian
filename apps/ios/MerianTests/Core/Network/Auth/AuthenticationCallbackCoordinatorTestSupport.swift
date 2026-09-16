import Foundation
@testable import Merian

enum AuthCallbackCoordinatorTestError: Error {
    case install
    case verification
}

actor AuthCallbackCoordinatorTestGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var released = false

    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitUntilWaiterCount(_ count: Int) async {
        while !released && continuations.count < count {
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
final class AuthenticationCallbackCoordinatorHarness {
    let sourceUserID = UUID(
        uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
    )!
    let targetUserID = UUID(
        uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
    )!
    let transition = AuthTransitionToken(
        id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
        kind: .authenticationCallback
    )

    var events: [String] = []
    var sourceSession: AuthTransitionSession?
    var installedSession: AuthTransitionSession
    var currentSession: AuthTransitionSession?
    var expectedSession: AuthTransitionSession?
    var publishedSession: AuthTransitionSession?
    var activeTransition: AuthTransitionToken?
    var pendingPurchaseHandoff = false
    var isSigningOut = false
    var mayBeginTransition = true
    var transitionMatches = true
    var adoptionSucceeds = true
    var purchaseIdentityIsReady = true
    var installedSessionIsExpired = false
    var mutateSessionBeforeInstallFailure = false
    var installError: Error?
    var verificationError: Error?
    var initialVerificationGate: AuthCallbackCoordinatorTestGate?
    var installGate: AuthCallbackCoordinatorTestGate?
    var purchaseGate: AuthCallbackCoordinatorTestGate?
    var entitlementGate: AuthCallbackCoordinatorTestGate?
    var finalVerificationGate: AuthCallbackCoordinatorTestGate?
    private(set) var beginCount = 0
    private(set) var finishCount = 0
    private(set) var installCount = 0
    private(set) var cleanupCount = 0
    private(set) var entitlementCount = 0
    private(set) var authenticatedOAuthMarker: Bool?
    private(set) var diagnostics: [AuthenticationCallbackDiagnostic] = []

    init(
        sourceSession: AuthTransitionSession? = nil,
        installedSession: AuthTransitionSession? = nil
    ) {
        self.sourceSession = sourceSession
        self.installedSession = installedSession ?? AuthTransitionSession(
            userID: targetUserID,
            isAnonymous: false
        )
        currentSession = sourceSession
        expectedSession = sourceSession
        publishedSession = sourceSession
    }

    func makeCoordinator() -> AuthenticationCallbackCoordinator {
        AuthenticationCallbackCoordinator(dependencies: makeDependencies())
    }

    func makeDependencies() -> AuthenticationCallbackDependencies {
        AuthenticationCallbackDependencies(
            transition: AuthenticationCallbackTransitionBoundary(
                hasPendingPurchaseIdentityHandoff: {
                    self.events.append("check-purchase-handoff")
                    return self.pendingPurchaseHandoff
                },
                isSignOutInProgress: {
                    self.isSigningOut
                },
                begin: {
                    self.events.append("begin-transition")
                    guard self.mayBeginTransition,
                          self.activeTransition == nil else {
                        return nil
                    }
                    self.beginCount += 1
                    self.activeTransition = self.transition
                    self.expectedSession = self.sourceSession
                    return self.transition
                },
                finish: { transition in
                    self.events.append("finish-transition")
                    self.finishCount += 1
                    if self.activeTransition == transition {
                        self.activeTransition = nil
                    }
                },
                owns: { transition in
                    self.activeTransition == transition
                },
                sourceSession: { transition in
                    guard self.activeTransition == transition else {
                        return nil
                    }
                    return self.sourceSession
                },
                currentSessionMatches: { transition in
                    self.events.append("validate-session")
                    return self.activeTransition == transition
                        && self.transitionMatches
                        && self.currentSession == self.expectedSession
                },
                verifyExpectedSessionIfPresent: { transition in
                    self.events.append("verify-expected-if-present")
                    if let gate = self.initialVerificationGate {
                        await gate.wait()
                    }
                    try await self.verify(transition)
                },
                verifyExpectedSession: { transition in
                    self.events.append("verify-expected")
                    if let gate = self.finalVerificationGate {
                        await gate.wait()
                    }
                    try await self.verify(transition)
                },
                updatePhase: { _, phase in
                    self.events.append("phase-\(phase.rawValue)")
                }
            ),
            session: AuthenticationCallbackSessionBoundary(
                analyticsGeneration: { _ in
                    self.events.append("analytics-generation")
                    return 7
                },
                installAndAdopt: { transition, didMutateSession in
                    self.events.append("install-session")
                    self.installCount += 1
                    if let gate = self.installGate {
                        await gate.wait()
                    }
                    if self.mutateSessionBeforeInstallFailure {
                        self.currentSession = self.installedSession
                        didMutateSession()
                        guard self.adoptInstalledSession(transition) else {
                            throw AuthCallbackCoordinatorTestError
                                .verification
                        }
                    }
                    if let installError = self.installError {
                        throw installError
                    }
                    if !self.mutateSessionBeforeInstallFailure {
                        self.currentSession = self.installedSession
                        didMutateSession()
                        guard self.adoptInstalledSession(transition) else {
                            throw AuthCallbackCoordinatorTestError
                                .verification
                        }
                    }
                    return self.session(for: self.installedSession)
                },
                current: {
                    guard let currentSession = self.currentSession else {
                        return nil
                    }
                    return self.session(for: currentSession)
                },
                clearPublishedSession: {
                    self.events.append("clear-published-session")
                    self.publishedSession = nil
                }
            ),
            completion: AuthenticationCallbackCompletionBoundary(
                clearMutatedSession: { transition in
                    self.events.append("clear-mutated-session")
                    guard self.activeTransition == transition,
                          self.currentSession == self.expectedSession else {
                        self.events.append("reject-mutated-session-clear")
                        return
                    }
                    self.cleanupCount += 1
                    self.currentSession = nil
                    self.expectedSession = nil
                    self.publishedSession = nil
                },
                markAuthenticatedOAuth: { value in
                    self.events.append("mark-authenticated-oauth")
                    self.authenticatedOAuthMarker = value
                }
            ),
            diagnostics: AuthenticationCallbackDiagnostics(
                report: { diagnostic, _ in
                    self.events.append("diagnose-\(diagnostic)")
                    self.diagnostics.append(diagnostic)
                }
            )
        )
    }

    private func verify(_ transition: AuthTransitionToken) async throws {
        if let verificationError {
            throw verificationError
        }
        guard activeTransition == transition,
              transitionMatches,
              currentSession == expectedSession else {
            throw AuthCallbackCoordinatorTestError.verification
        }
    }

    private func adoptInstalledSession(
        _ transition: AuthTransitionToken
    ) -> Bool {
        events.append("adopt-installed-session")
        guard adoptionSucceeds,
              activeTransition == transition,
              currentSession == installedSession else {
            return false
        }
        expectedSession = installedSession
        return true
    }

    private func session(
        for identity: AuthTransitionSession
    ) -> AuthenticationCallbackSession {
        AuthenticationCallbackSession(
            identity: identity,
            isExpired:
                identity == installedSession && installedSessionIsExpired,
            publish: {
                self.events.append("publish-session")
                self.publishedSession = identity
            },
            ensurePurchaseIdentityReady: { _ in
                self.events.append("ensure-purchase-identity")
                if let gate = self.purchaseGate {
                    await gate.wait()
                }
            },
            purchaseIdentityIsReady: {
                self.events.append("validate-purchase-identity")
                return self.purchaseIdentityIsReady
            },
            beginEntitlementSession: { _ in
                self.events.append("begin-entitlement-session")
                self.entitlementCount += 1
                if let gate = self.entitlementGate {
                    await gate.wait()
                }
            }
        )
    }
}
