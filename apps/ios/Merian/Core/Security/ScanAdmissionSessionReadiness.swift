import Foundation

/// Resolves first-launch Auth before admission takes a lease. Bootstrap itself
/// drains account work, so waiting while holding that lease would deadlock.
@MainActor
enum ScanAdmissionSessionReadiness {
    static let preparationTimeout: Duration = .seconds(5)

    struct Snapshot {
        let publishedSession: AuthTransitionSession?
        let sdkSession: AuthTransitionSession?
        let allowsAccountWork: Bool
        let transition: AuthTransitionKind?
        let bootstrapBlocked: Bool

        var isReady: Bool {
            allowsAccountWork && transition == nil && sdkSession != nil
                && publishedSession == sdkSession
        }
    }

    struct Dependencies {
        let snapshot: @MainActor () -> Snapshot
        let initialize: @MainActor () async -> AuthTransitionSession?
        var waitForDeadline: @MainActor () async throws -> Void = {
            try await Task.sleep(for: preparationTimeout)
        }
    }

    static func prepare(using dependencies: Dependencies) async -> Bool {
        guard !Task.isCancelled else { return false }
        let initial = dependencies.snapshot()
        if initial.isReady { return true }
        guard !initial.bootstrapBlocked,
              initial.transition == nil || initial.transition == .anonymousBootstrap else {
            return false
        }

        // Joins the existing single-flight warmup, or retries a failed first
        // bootstrap. Do not cancel that shared task when this caller leaves.
        let waiter = Waiter()
        let resolved = await withTaskCancellationHandler {
            await waiter.value(using: dependencies)
        } onCancel: {
            Task { @MainActor in waiter.finish(nil) }
        }
        guard let resolved,
              !Task.isCancelled else { return false }
        let current = dependencies.snapshot()
        return current.isReady && current.sdkSession == resolved
            && (initial.sdkSession.map { $0 == resolved } ?? true)
            && (initial.publishedSession.map { $0 == resolved } ?? true)
    }

    /// Bounds only this caller's wait. Cancelling the wrapper never cancels the
    /// bootstrap coordinator's shared task, which may serve other consumers.
    private final class Waiter {
        private var continuation: CheckedContinuation<AuthTransitionSession?, Never>?
        private var operation: Task<Void, Never>?
        private var deadline: Task<Void, Never>?
        private var finished = false

        func value(using dependencies: Dependencies) async -> AuthTransitionSession? {
            guard !finished, !Task.isCancelled else { return nil }
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                operation = Task { @MainActor [weak self] in
                    let result = await dependencies.initialize()
                    self?.finish(result)
                }
                deadline = Task { @MainActor [weak self] in
                    do {
                        try await dependencies.waitForDeadline()
                        self?.finish(nil)
                    } catch is CancellationError {
                        // The result/cancellation path already owns completion.
                    } catch {
                        self?.finish(nil)
                    }
                }
            }
        }

        func finish(_ result: AuthTransitionSession?) {
            guard !finished else { return }
            finished = true
            operation?.cancel()
            deadline?.cancel()
            operation = nil
            deadline = nil
            continuation?.resume(returning: result)
            continuation = nil
        }
    }

    static func liveDependencies(
        manager: SupabaseManager
    ) -> Dependencies {
        Dependencies(
            snapshot: {
                let published = manager.currentUser.map {
                    AuthTransitionSession(userID: $0.id, isAnonymous: $0.isAnonymous)
                }
                let sdk = manager.client.auth.currentSession.map {
                    AuthTransitionSession(userID: $0.user.id, isAnonymous: $0.user.isAnonymous)
                }
                return Snapshot(
                    publishedSession: published,
                    sdkSession: sdk,
                    allowsAccountWork: manager.allowsUnownedAccountBoundWork,
                    transition: manager.activeAuthTransition?.token.kind,
                    bootstrapBlocked: AccountDeletionLocalCleanupStore.isPending()
                        || KeychainManager.shared.bool(forKey: KeychainKeys.hasAuthenticatedOAuth)
                        || manager.hasPendingPurchaseIdentityHandoffFailClosed()
                )
            },
            initialize: {
                guard let user = await manager.initializeGhostSession() else { return nil }
                return AuthTransitionSession(userID: user.id, isAnonymous: user.isAnonymous)
            }
        )
    }
}
