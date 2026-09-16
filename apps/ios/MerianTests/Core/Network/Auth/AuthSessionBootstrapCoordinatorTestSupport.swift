import Foundation
@testable import Merian

enum AuthSessionBootstrapCoordinatorTestError: Error, Equatable {
    case missingSession
    case network
    case anonymousCreation
}

actor AuthSessionBootstrapCoordinatorTestGate {
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
final class AuthSessionBootstrapCoordinatorHarness {
    let existing = AuthTransitionSession(
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
    let firstTransition = AuthTransitionToken(
        id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
        kind: .anonymousBootstrap
    )
    let secondTransition = AuthTransitionToken(
        id: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
        kind: .anonymousBootstrap
    )

    var events: [String] = []
    var isTestExecution = false
    var accountDeletionCleanupPending = false
    var isAuthenticated = false
    var currentPublishedSession: AuthTransitionSession?
    var currentSDKSession: AuthTransitionSession?
    var currentSDKSessionIsExpired = false
    var loadedSession: AuthTransitionSession?
    var loadedSessionIsExpired = false
    var activeTransition: AuthTransitionToken?
    var mayBeginTransition = true
    var adoptionSucceeds = true
    var accountWorkQuiescenceSucceeds = true
    var mayBeginAccountWork = true
    var accountWorkIsCurrent = true
    var loadError: Error?
    var createError: Error?
    var signOutGate: AuthSessionBootstrapCoordinatorTestGate?
    var quiescenceGate: AuthSessionBootstrapCoordinatorTestGate?
    var loadGate: AuthSessionBootstrapCoordinatorTestGate?
    var createGate: AuthSessionBootstrapCoordinatorTestGate?
    var readinessGate: AuthSessionBootstrapCoordinatorTestGate?
    var readinessReplacement: AuthTransitionSession?
    private(set) var transitionBeginCount = 0
    private(set) var transitionFinishCount = 0
    private(set) var adoptionCount = 0
    private(set) var accountWorkBeginCount = 0
    private(set) var accountWorkFinishCount = 0
    private(set) var loadCount = 0
    private(set) var createCount = 0
    private(set) var publishCount = 0
    private(set) var readinessCount = 0
    private(set) var publicAuthorRefreshCount = 0

    func makeDependencies() -> AuthSessionBootstrapDependencies {
        AuthSessionBootstrapDependencies(
            state: .init(
                isTestExecution: {
                    self.isTestExecution
                },
                isAccountDeletionCleanupPending: {
                    self.accountDeletionCleanupPending
                },
                isAuthenticated: {
                    self.isAuthenticated
                },
                currentPublishedSession: {
                    self.currentPublishedSession
                },
                awaitSignOutCompletion: {
                    self.events.append("await-sign-out")
                    if let gate = self.signOutGate {
                        await gate.wait()
                    }
                }
            ),
            transition: .init(
                activeTransition: {
                    self.activeTransition
                },
                beginAnonymousBootstrap: {
                    self.events.append("begin-transition")
                    guard self.mayBeginTransition,
                          self.activeTransition == nil else {
                        return nil
                    }
                    self.transitionBeginCount += 1
                    self.activeTransition = self.firstTransition
                    return self.firstTransition
                },
                allows: { transition in
                    if let activeTransition = self.activeTransition {
                        return transition == activeTransition
                    }
                    return transition == nil
                },
                adopt: { session, transition in
                    self.events.append("adopt-\(session.userID)")
                    self.adoptionCount += 1
                    return self.adoptionSucceeds
                        && self.activeTransition == transition
                        && self.currentSDKSession == session
                },
                finish: { transition in
                    self.events.append("finish-transition")
                    self.transitionFinishCount += 1
                    if self.activeTransition == transition {
                        self.activeTransition = nil
                    }
                },
                awaitAccountWorkQuiescence: {
                    self.events.append("await-quiescence")
                    if let gate = self.quiescenceGate {
                        await gate.wait()
                    }
                    return self.accountWorkQuiescenceSucceeds
                }
            ),
            work: .init(
                beginUnownedAccountWork: { userID in
                    self.events.append("begin-account-work")
                    self.accountWorkBeginCount += 1
                    guard self.mayBeginAccountWork,
                          self.currentSDKSession?.userID == userID else {
                        return nil
                    }
                    return AccountBoundWorkLease(
                        id: UUID(),
                        session: self.currentSDKSession!
                    )
                },
                isAccountWorkCurrent: { lease in
                    self.events.append("validate-account-work")
                    return self.accountWorkIsCurrent
                        && self.currentSDKSession == lease.session
                        && self.currentPublishedSession == lease.session
                },
                finishAccountWork: { _ in
                    self.events.append("finish-account-work")
                    self.accountWorkFinishCount += 1
                }
            ),
            operations: .init(
                currentSDKSession: {
                    self.events.append("current-sdk-session")
                    guard let session = self.currentSDKSession else {
                        return nil
                    }
                    return self.snapshot(
                        session,
                        isExpired: self.currentSDKSessionIsExpired
                    )
                },
                loadSDKSession: {
                    self.events.append("load-sdk-session")
                    self.loadCount += 1
                    let gate = self.loadGate
                    self.loadGate = nil
                    if let gate {
                        await gate.wait()
                    }
                    if let loadError = self.loadError {
                        throw loadError
                    }
                    guard let loadedSession = self.loadedSession else {
                        throw AuthSessionBootstrapCoordinatorTestError.network
                    }
                    self.currentSDKSession = loadedSession
                    self.currentSDKSessionIsExpired =
                        self.loadedSessionIsExpired
                    return self.snapshot(
                        loadedSession,
                        isExpired: self.loadedSessionIsExpired
                    )
                },
                createAnonymousSession: {
                    self.events.append("create-anonymous-session")
                    self.createCount += 1
                    let gate = self.createGate
                    self.createGate = nil
                    if let gate {
                        await gate.wait()
                    }
                    if let createError = self.createError {
                        throw createError
                    }
                    self.currentSDKSession = self.anonymous
                    self.currentSDKSessionIsExpired = false
                    return self.snapshot(self.anonymous, isExpired: false)
                },
                isSessionMissingError: { error in
                    guard let error = error as?
                        AuthSessionBootstrapCoordinatorTestError else {
                        return false
                    }
                    return error == .missingSession
                }
            ),
            diagnose: { diagnostic, _ in
                self.events.append("diagnose-\(diagnostic)")
            }
        )
    }

    private func snapshot(
        _ session: AuthTransitionSession,
        isExpired: Bool
    ) -> AuthSessionBootstrapSnapshot {
        AuthSessionBootstrapSnapshot(
            identity: session,
            isExpired: isExpired,
            publish: {
                self.events.append("publish-\(session.userID)")
                self.publishCount += 1
                self.currentPublishedSession = session
                self.isAuthenticated = true
            },
            schedulePublicAuthorIdentityRefresh: {
                self.events.append("schedule-public-author-refresh")
                self.publicAuthorRefreshCount += 1
            },
            ensurePurchaseIdentityReady: { _ in
                self.events.append("ensure-purchase-identity")
                self.readinessCount += 1
                let gate = self.readinessGate
                self.readinessGate = nil
                if let gate {
                    await gate.wait()
                }
                if let replacement = self.readinessReplacement {
                    self.currentSDKSession = replacement
                    self.currentPublishedSession = replacement
                }
            },
            isCurrentPublishedSession: { transition in
                self.events.append("validate-published-session")
                guard self.currentSDKSession == session,
                      self.currentPublishedSession == session,
                      self.isAuthenticated,
                      !self.currentSDKSessionIsExpired else {
                    return false
                }
                if let transition {
                    return self.activeTransition == transition
                }
                return self.activeTransition == nil
            }
        )
    }
}
