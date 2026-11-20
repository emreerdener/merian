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
#if DEBUG
    private var initialTestEpoch = UUID()
    private var initialCompletionToken = UUID()
    static weak var liveProviderForUITesting: AuthSessionLifecycleLiveProvider?
    private var initialSignedOutCompletionForTesting: (@MainActor () -> Bool)?

    private func invalidateInitialCompletionForTesting() {
        initialCompletionToken = UUID()
        initialSignedOutCompletionForTesting = nil
    }

    /// Observes the real handler exit; never cancels or replaces the Auth stream.
    func waitForInitialSignedOutForTesting(timeout: Duration = .seconds(15)) async throws -> Bool {
        let epoch = initialTestEpoch
        let deadline = ContinuousClock.now + timeout
        while true {
            try Task.checkCancellation()
            guard initialTestEpoch == epoch else { return false }
            if let current = initialSignedOutCompletionForTesting { return current() }
            guard ContinuousClock.now < deadline else { return false }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
#endif

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
#if DEBUG
        initialTestEpoch = UUID()
        invalidateInitialCompletionForTesting()
        let initialEpoch = initialTestEpoch
#endif
        listenerTask = startListeningOperation { [weak self] state in
#if DEBUG
            self?.invalidateInitialCompletionForTesting()
            let completionToken = self?.initialCompletionToken
#endif
            guard let operation = self?.makeOperation(
                for: state,
                dependencies: dependencies
            ) else { return }
#if DEBUG
            let initialSignedOut = state.origin == .initialRestoration && state.user == nil
                && !state.isExpired && !dependencies.hasActiveTransition()
                && !dependencies.accountDeletionCleanupPending()
#endif
            await operation.run()
#if DEBUG
            if initialSignedOut, !Task.isCancelled, self?.initialTestEpoch == initialEpoch,
               self?.initialCompletionToken == completionToken,
               !dependencies.accountDeletionCleanupPending(),
               operation.dependencies.state.isCurrentLifecycleSession(nil, operation.event.authGeneration) {
                self?.initialSignedOutCompletionForTesting = { [weak self] in
                    self?.initialCompletionToken == completionToken && self?.initialTestEpoch == initialEpoch
                        && !dependencies.hasActiveTransition() && !dependencies.accountDeletionCleanupPending()
                        && dependencies.reconciliationContextIsCurrent(operation.event.authGeneration)
                        && operation.dependencies.state.isCurrentLifecycleSession(nil, operation.event.authGeneration)
                }
            }
#endif
        }
    }

    func authTransitionWillBegin() {
#if DEBUG
        invalidateInitialCompletionForTesting()
#endif
        replayCoordinator.authTransitionWillBegin()
    }

    @discardableResult
    func scheduleCurrentSessionReconciliation(
        authGeneration: UInt64,
        force: Bool = false,
        dependencies: AuthSessionLifecycleLiveDependencies
    ) -> Bool {
#if DEBUG
        invalidateInitialCompletionForTesting()
#endif
        let snapshot = currentStateOperation()
        guard let lifecycleDependencies =
            dependencies.makeLifecycleDependencies(snapshot.user) else {
            return false
        }
        let currentState = currentStateOperation
        return replayCoordinator.scheduleIfNeeded(force: force) {
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
#if DEBUG
        initialTestEpoch = UUID()
        invalidateInitialCompletionForTesting()
#endif
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
