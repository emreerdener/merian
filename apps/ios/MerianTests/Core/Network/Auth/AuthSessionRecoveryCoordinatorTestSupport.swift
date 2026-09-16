import Foundation
@testable import Merian

enum AuthSessionRecoveryCoordinatorTestError: Error {
    case refresh
    case session
    case localSignOut
}

actor AuthSessionRecoveryCoordinatorTestGate {
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
final class AuthSessionRecoveryCoordinatorHarness {
    let source = AuthTransitionSession(
        userID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
        isAnonymous: false
    )
    let anonymous = AuthTransitionSession(
        userID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
        isAnonymous: true
    )
    let replacement = AuthTransitionSession(
        userID: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
        isAnonymous: true
    )
    let recovery = AuthTransitionToken(
        id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
        kind: .recovery
    )

    var events: [String] = []
    var mayBeginTransition = true
    var activeTransition: AuthTransitionToken?
    var expectedSession: AuthTransitionSession?
    var sdkSession: AuthTransitionSession?
    var publishedSession: AuthTransitionSession?
    var authGeneration: UInt64 = 7
    var signingOut = false
    var purchaseHandoffPending = false
    var quiescenceSucceeds = true
    var transitionMatches = true
    var adoptionSucceeds = true
    var refreshResult: AuthTransitionSession?
    var refreshError: Error?
    var loadedSessions: [AuthTransitionSession] = []
    var loadError: Error?
    var resetAnonymousSucceeds = true
    var purchaseIdentityReady = true
    var entitlementReady = true
    var localSignOutError: Error?
    var quiescenceGate: AuthSessionRecoveryCoordinatorTestGate?
    var refreshGate: AuthSessionRecoveryCoordinatorTestGate?
    var purchaseReadinessGate: AuthSessionRecoveryCoordinatorTestGate?
    var localSignOutGate: AuthSessionRecoveryCoordinatorTestGate?
    private(set) var beginCount = 0
    private(set) var finishCount = 0
    private(set) var refreshCount = 0
    private(set) var loadCount = 0
    private(set) var publishCount = 0
    private(set) var scheduleCount = 0
    private(set) var purchaseReadinessCount = 0
    private(set) var entitlementCount = 0
    private(set) var localStateClearCount = 0
    private(set) var purchaseSignOutCount = 0

    func makeCoordinator() -> AuthSessionRecoveryCoordinator {
        AuthSessionRecoveryCoordinator(dependencies: makeDependencies())
    }

    func makeDependencies() -> AuthSessionRecoveryDependencies {
        AuthSessionRecoveryDependencies(
            state: .init(
                isSigningOut: {
                    self.signingOut
                },
                hasPendingPurchaseIdentityHandoff: {
                    self.purchaseHandoffPending
                },
                clearLocalRecoveryState: {
                    self.events.append("clear-local-state")
                    self.localStateClearCount += 1
                    self.publishedSession = nil
                }
            ),
            transition: .init(
                beginRecovery: {
                    self.events.append("begin-recovery")
                    guard self.mayBeginTransition,
                          self.activeTransition == nil else {
                        return nil
                    }
                    self.beginCount += 1
                    self.activeTransition = self.recovery
                    return self.recovery
                },
                finish: { transition in
                    self.events.append("finish-recovery")
                    self.finishCount += 1
                    if self.activeTransition == transition {
                        self.activeTransition = nil
                    }
                },
                owns: { transition in
                    self.activeTransition == transition
                },
                expectedSession: { transition in
                    guard self.activeTransition == transition else {
                        return nil
                    }
                    return self.expectedSession
                },
                awaitAccountWorkQuiescence: {
                    self.events.append("await-quiescence")
                    if let gate = self.quiescenceGate {
                        await gate.wait()
                    }
                    return self.quiescenceSucceeds
                },
                currentSessionMatches: { transition in
                    self.events.append("validate-transition-session")
                    return self.activeTransition == transition
                        && self.transitionMatches
                        && self.sdkSession == self.expectedSession
                },
                updatePhase: { _, phase in
                    self.events.append("phase-\(phase.rawValue)")
                },
                adoptSignedOutSession: { transition in
                    self.events.append("adopt-signed-out")
                    if self.activeTransition == transition {
                        self.expectedSession = nil
                    }
                }
            ),
            operations: .init(
                refreshSDKSession: {
                    self.events.append("refresh-sdk-session")
                    self.refreshCount += 1
                    if let gate = self.refreshGate {
                        await gate.wait()
                    }
                    if let refreshError = self.refreshError {
                        throw refreshError
                    }
                    guard let refreshResult = self.refreshResult else {
                        throw AuthSessionRecoveryCoordinatorTestError.refresh
                    }
                    self.sdkSession = refreshResult
                    return self.session(for: refreshResult)
                },
                loadSDKSession: {
                    self.events.append("load-sdk-session")
                    self.loadCount += 1
                    if let loadError = self.loadError {
                        throw loadError
                    }
                    guard !self.loadedSessions.isEmpty else {
                        throw AuthSessionRecoveryCoordinatorTestError.session
                    }
                    let identity = self.loadedSessions.removeFirst()
                    self.sdkSession = identity
                    return self.session(for: identity)
                },
                resetAnonymousSession: { transition in
                    self.events.append("reset-anonymous-session")
                    guard self.resetAnonymousSucceeds,
                          self.activeTransition == transition else {
                        return false
                    }
                    self.expectedSession = self.anonymous
                    self.sdkSession = self.anonymous
                    self.publishedSession = self.anonymous
                    return true
                },
                performLocalSDKSignOut: {
                    self.events.append("local-sdk-sign-out")
                    if let gate = self.localSignOutGate {
                        await gate.wait()
                        try Task.checkCancellation()
                    }
                    if let localSignOutError = self.localSignOutError {
                        throw localSignOutError
                    }
                    self.sdkSession = nil
                },
                finishPurchaseIdentitySignOut: {
                    self.events.append("finish-purchase-sign-out")
                    self.purchaseSignOutCount += 1
                }
            ),
            diagnose: { diagnostic, _ in
                self.events.append("diagnose-\(diagnostic)")
            }
        )
    }

    private func session(
        for identity: AuthTransitionSession
    ) -> AuthSessionRecoverySession {
        let generation = authGeneration
        return AuthSessionRecoverySession(
            identity: identity,
            adopt: { transition in
                self.events.append("adopt-session")
                guard self.adoptionSucceeds,
                      self.activeTransition == transition else {
                    return false
                }
                self.expectedSession = identity
                return true
            },
            publish: {
                self.events.append("publish-session")
                self.publishCount += 1
                self.publishedSession = identity
            },
            schedulePublicAuthorIdentityRefresh: {
                self.events.append("schedule-public-author-refresh")
                self.scheduleCount += 1
            },
            ensurePurchaseIdentityReady: { _ in
                self.events.append("ensure-purchase-identity")
                self.purchaseReadinessCount += 1
                if let gate = self.purchaseReadinessGate {
                    await gate.wait()
                }
            },
            purchaseIdentityIsReady: {
                self.events.append("validate-purchase-identity")
                return self.purchaseIdentityReady
                    && self.publishedSession == identity
                    && self.authGeneration == generation
            },
            beginEntitlementSession: { _ in
                self.events.append("begin-entitlement-session")
                self.entitlementCount += 1
                return self.entitlementReady
            },
            isPublishedAtCapturedGeneration: {
                self.events.append("validate-published-generation")
                return self.publishedSession == identity
                    && self.authGeneration == generation
            }
        )
    }
}
