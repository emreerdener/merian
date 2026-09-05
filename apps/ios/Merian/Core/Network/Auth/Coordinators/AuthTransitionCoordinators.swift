import Foundation

struct AccountBoundWorkCoordinator {
    private(set) var activeSessionsByLeaseID:
        [UUID: AuthTransitionSession] = [:]

    var isEmpty: Bool { activeSessionsByLeaseID.isEmpty }

    mutating func begin(
        session: AuthTransitionSession,
        id: UUID = UUID()
    ) -> AccountBoundWorkLease {
        activeSessionsByLeaseID[id] = session
        return AccountBoundWorkLease(id: id, session: session)
    }

    func owns(_ lease: AccountBoundWorkLease) -> Bool {
        activeSessionsByLeaseID[lease.id] == lease.session
    }

    @discardableResult
    mutating func finish(_ lease: AccountBoundWorkLease) -> Bool {
        guard owns(lease) else { return false }
        activeSessionsByLeaseID[lease.id] = nil
        return true
    }
}

struct AuthTransitionCoordinator {
    private(set) var active: AuthTransitionState?

    mutating func begin(
        kind: AuthTransitionKind,
        sourceSession: AuthTransitionSession?,
        authGeneration: UInt64,
        id: UUID = UUID()
    ) -> AuthTransitionToken? {
        guard active == nil else { return nil }
        let token = AuthTransitionToken(id: id, kind: kind)
        active = AuthTransitionState(
            token: token,
            phase: .preparing,
            sourceSession: sourceSession,
            expectedSession: sourceSession,
            authGeneration: authGeneration
        )
        return token
    }

    func owns(_ token: AuthTransitionToken) -> Bool {
        active?.token == token
    }

    @discardableResult
    mutating func updatePhase(
        _ phase: AuthTransitionPhase,
        for token: AuthTransitionToken
    ) -> Bool {
        guard active?.token == token else { return false }
        active?.phase = phase
        return true
    }

    @discardableResult
    mutating func adoptExpectedSession(
        _ session: AuthTransitionSession?,
        authGeneration: UInt64,
        for token: AuthTransitionToken
    ) -> Bool {
        guard active?.token == token else { return false }
        active?.expectedSession = session
        active?.authGeneration = authGeneration
        return true
    }

    mutating func observeAuthEvent(
        session: AuthTransitionSession?,
        authGeneration: UInt64
    ) {
        guard let expected = active?.expectedSession,
              expected == session else {
            if active?.expectedSession == nil, session == nil {
                active?.authGeneration = authGeneration
            }
            return
        }
        active?.authGeneration = authGeneration
    }

    func validatesExpectedSession(
        _ session: AuthTransitionSession?,
        authGeneration: UInt64,
        for token: AuthTransitionToken
    ) -> Bool {
        guard let active, active.token == token else { return false }
        return active.expectedSession == session
            && active.authGeneration == authGeneration
    }

    @discardableResult
    mutating func finish(_ token: AuthTransitionToken) -> Bool {
        guard active?.token == token else { return false }
        active = nil
        return true
    }
}

@MainActor
final class AuthTransitionSingleFlight {
    private var task: Task<Bool, Never>?

    var isRunning: Bool { task != nil }

    func run(
        operation: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        if let task {
            return await task.value
        }

        let task = Task { @MainActor in
            await operation()
        }
        self.task = task
        let result = await task.value
        self.task = nil
        return result
    }
}
