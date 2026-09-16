import Foundation
import Supabase

/// One SDK Auth value captured by the live stream or current-session reader.
/// Provider-neutral lifecycle policy remains in `AuthSessionLifecycleCoordinator`.
@MainActor
struct AuthSessionLifecycleSDKState {
    let user: User?
    let isExpired: Bool
    let origin: AuthSessionLifecycleOrigin

    var session: AuthTransitionSession? {
        guard let user else { return nil }
        return AuthTransitionSession(
            userID: user.id,
            isAnonymous: user.isAnonymous
        )
    }

    func lifecycleEvent(
        authGeneration: UInt64
    ) -> AuthSessionLifecycleEvent {
        AuthSessionLifecycleEvent(
            adoption: AuthTransitionPolicy.authSessionAdoption(
                userId: user?.id,
                isExpired: isExpired
            ),
            session: session,
            authGeneration: authGeneration,
            origin: origin
        )
    }

    func hasSameSession(as other: Self) -> Bool {
        isExpired == other.isExpired && session == other.session
    }
}

/// Supplies the facade-owned effects that surround one SDK Auth event. Every
/// closure capturing `SupabaseManager` must do so weakly because the provider's
/// listener task retains this package while it waits for the next SDK value.
struct AuthSessionLifecycleLiveDependencies {
    let advanceAuthGeneration: @MainActor () -> UInt64?
    let authContextWillChange: @MainActor () -> Void
    let observeAuthSession: @MainActor (AuthTransitionSession?) -> Void
    let accountDeletionCleanupPending: @MainActor () -> Bool
    let hasActiveTransition: @MainActor () -> Bool
    let reconciliationContextIsCurrent: @MainActor (UInt64) -> Bool
    let makeLifecycleDependencies: @MainActor (
        User?
    ) -> AuthSessionLifecycleDependencies?
    let resumeDeferredCredentialRevocation: @MainActor () -> Void
}

private struct AuthSessionLifecycleLiveOperation {
    let event: AuthSessionLifecycleEvent
    let dependencies: AuthSessionLifecycleDependencies
    let resumeDeferredCredentialRevocation: @MainActor () -> Void

    @MainActor
    func run() async {
        await AuthSessionLifecycleCoordinator(
            dependencies: dependencies
        ).handle(event)
        guard !Task.isCancelled else { return }
        resumeDeferredCredentialRevocation()
    }
}

/// Owns the Supabase Auth stream task and composes deferred current-session
/// replay. It deliberately releases itself before coordinator suspension, so a
/// waiting SDK value or downstream effect cannot keep the provider alive.
@MainActor
final class AuthSessionLifecycleLiveProvider {
    typealias EventHandler = @MainActor (
        AuthSessionLifecycleSDKState
    ) async -> Void
    typealias StartListeningOperation = @MainActor (
        @escaping EventHandler
    ) -> Task<Void, Never>
    typealias CurrentStateOperation = @MainActor ()
        -> AuthSessionLifecycleSDKState

    private let startListeningOperation: StartListeningOperation
    private let currentStateOperation: CurrentStateOperation
    private let replayCoordinator = AuthLifecycleReplayCoordinator()
    private var listenerTask: Task<Void, Never>?

    init(
        startListening: @escaping StartListeningOperation,
        currentState: @escaping CurrentStateOperation
    ) {
        startListeningOperation = startListening
        currentStateOperation = currentState
    }

    deinit {
        listenerTask?.cancel()
    }

    func start(dependencies: AuthSessionLifecycleLiveDependencies) {
        listenerTask?.cancel()
        replayCoordinator.cancel()
        listenerTask = startListeningOperation { [weak self] state in
            guard let operation = self?.makeOperation(
                for: state,
                dependencies: dependencies
            ) else { return }
            await operation.run()
        }
    }

    func authTransitionWillBegin() {
        replayCoordinator.authTransitionWillBegin()
    }

    @discardableResult
    func scheduleCurrentSessionReconciliation(
        authGeneration: UInt64,
        dependencies: AuthSessionLifecycleLiveDependencies
    ) -> Bool {
        let snapshot = currentStateOperation()
        guard let lifecycleDependencies =
            dependencies.makeLifecycleDependencies(snapshot.user) else {
            return false
        }
        let currentState = currentStateOperation
        return replayCoordinator.scheduleIfNeeded {
            guard Self.snapshotIsCurrent(
                snapshot,
                authGeneration: authGeneration,
                currentState: currentState,
                dependencies: dependencies
            ) else { return }
            await AuthSessionLifecycleCoordinator(
                dependencies: lifecycleDependencies
            ).handle(
                snapshot.lifecycleEvent(
                    authGeneration: authGeneration
                )
            )
            guard Self.snapshotIsCurrent(
                snapshot,
                authGeneration: authGeneration,
                currentState: currentState,
                dependencies: dependencies
            ) else { return }
            dependencies.resumeDeferredCredentialRevocation()
        }
    }

    func cancel() {
        listenerTask?.cancel()
        listenerTask = nil
        replayCoordinator.cancel()
    }

    private func makeOperation(
        for state: AuthSessionLifecycleSDKState,
        dependencies: AuthSessionLifecycleLiveDependencies
    ) -> AuthSessionLifecycleLiveOperation? {
        guard let authGeneration =
            dependencies.advanceAuthGeneration() else {
            return nil
        }
        dependencies.authContextWillChange()
        dependencies.observeAuthSession(state.session)
        let deletionCleanupPending =
            dependencies.accountDeletionCleanupPending()
        replayCoordinator.observeLifecycleEvent(
            deferredByActiveTransition:
                dependencies.hasActiveTransition()
                && !deletionCleanupPending
        )
        guard let lifecycleDependencies =
            dependencies.makeLifecycleDependencies(state.user) else {
            return nil
        }
        return AuthSessionLifecycleLiveOperation(
            event: state.lifecycleEvent(
                authGeneration: authGeneration
            ),
            dependencies: lifecycleDependencies,
            resumeDeferredCredentialRevocation:
                dependencies.resumeDeferredCredentialRevocation
        )
    }

    private static func snapshotIsCurrent(
        _ snapshot: AuthSessionLifecycleSDKState,
        authGeneration: UInt64,
        currentState: CurrentStateOperation,
        dependencies: AuthSessionLifecycleLiveDependencies
    ) -> Bool {
        !Task.isCancelled
            && dependencies.reconciliationContextIsCurrent(authGeneration)
            && currentState().hasSameSession(as: snapshot)
    }
}
