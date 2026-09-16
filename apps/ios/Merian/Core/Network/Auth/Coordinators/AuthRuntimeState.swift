import Foundation
import Observation

struct AuthRuntimeTransitionCompletion {
    let analyticsGeneration: UInt?
}

/// Owns the mutable, process-local state that serializes Auth transitions and
/// drains exact-session account work. It acquires no SDK, singleton, store,
/// endpoint, logger, or asynchronous task.
@MainActor
@Observable
final class AuthRuntimeState {
    private var transitionCoordinator = AuthTransitionCoordinator()
    @ObservationIgnored private var analyticsGenerations: [UUID: UInt] = [:]
    @ObservationIgnored private var accountWorkCoordinator =
        AccountBoundWorkCoordinator()
    @ObservationIgnored private var accountWorkDrainWaiters:
        [CheckedContinuation<Void, Never>] = []

    private(set) var sessionGeneration: UInt64 = 0
    private(set) var isSigningOut = false

    var activeTransition: AuthTransitionState? {
        transitionCoordinator.active
    }

    var activeSourceUserID: UUID? {
        activeTransition?.sourceSession?.userID
    }

    var activeExpectedSession: AuthTransitionSession? {
        activeTransition?.expectedSession
    }

    func beginTransition(
        kind: AuthTransitionKind,
        sourceSession: AuthTransitionSession?
    ) -> AuthTransitionToken? {
        transitionCoordinator.begin(
            kind: kind,
            sourceSession: sourceSession,
            authGeneration: sessionGeneration
        )
    }

    func ownsTransition(_ token: AuthTransitionToken) -> Bool {
        transitionCoordinator.owns(token)
    }

    func transitionAllows(_ token: AuthTransitionToken?) -> Bool {
        if let active = activeTransition?.token {
            return token == active
        }
        return token == nil
    }

    @discardableResult
    func updateTransition(
        _ token: AuthTransitionToken,
        phase: AuthTransitionPhase
    ) -> Bool {
        transitionCoordinator.updatePhase(phase, for: token)
    }

    @discardableResult
    func adoptTransitionSession(
        _ session: AuthTransitionSession?,
        for token: AuthTransitionToken
    ) -> Bool {
        transitionCoordinator.adoptExpectedSession(
            session,
            authGeneration: sessionGeneration,
            for: token
        )
    }

    func transitionMatchesCurrentSession(
        _ session: AuthTransitionSession?,
        token: AuthTransitionToken
    ) -> Bool {
        transitionCoordinator.validatesExpectedSession(
            session,
            authGeneration: sessionGeneration,
            for: token
        )
    }

    @discardableResult
    func advanceSessionGeneration() -> UInt64 {
        sessionGeneration &+= 1
        return sessionGeneration
    }

    func observeAuthEvent(session: AuthTransitionSession?) {
        transitionCoordinator.observeAuthEvent(
            session: session,
            authGeneration: sessionGeneration
        )
    }

    @discardableResult
    func recordAnalyticsGeneration(
        _ generation: UInt,
        for token: AuthTransitionToken
    ) -> Bool {
        guard ownsTransition(token) else { return false }
        analyticsGenerations[token.id] = generation
        return true
    }

    func analyticsGeneration(
        for token: AuthTransitionToken
    ) -> UInt? {
        guard ownsTransition(token) else { return nil }
        return analyticsGenerations[token.id]
    }

    func finishTransition(
        _ token: AuthTransitionToken
    ) -> AuthRuntimeTransitionCompletion? {
        guard ownsTransition(token) else { return nil }
        let analyticsGeneration = analyticsGenerations.removeValue(
            forKey: token.id
        )
        guard transitionCoordinator.finish(token) else { return nil }
        return AuthRuntimeTransitionCompletion(
            analyticsGeneration: analyticsGeneration
        )
    }

    func beginAccountWork(
        session: AuthTransitionSession,
        id: UUID = UUID()
    ) -> AccountBoundWorkLease {
        accountWorkCoordinator.begin(session: session, id: id)
    }

    func accountWorkLeaseIsCurrent(
        _ lease: AccountBoundWorkLease,
        publishedSession: AuthTransitionSession?,
        sdkSession: AuthTransitionSession?
    ) -> Bool {
        accountWorkCoordinator.owns(lease)
            && publishedSession == lease.session
            && sdkSession == lease.session
    }

    @discardableResult
    func finishAccountWork(_ lease: AccountBoundWorkLease) -> Bool {
        guard accountWorkCoordinator.finish(lease) else { return false }
        guard accountWorkCoordinator.isEmpty else { return true }

        let waiters = accountWorkDrainWaiters
        accountWorkDrainWaiters.removeAll(keepingCapacity: true)
        for waiter in waiters {
            waiter.resume()
        }
        return true
    }

    func awaitAccountWorkDrain() async {
        guard !accountWorkCoordinator.isEmpty else { return }
        await withCheckedContinuation { continuation in
            if accountWorkCoordinator.isEmpty {
                continuation.resume()
            } else {
                accountWorkDrainWaiters.append(continuation)
            }
        }
    }

    func beginSignOut() {
        isSigningOut = true
        advanceSessionGeneration()
    }

    func finishSignOut() {
        isSigningOut = false
    }
}
