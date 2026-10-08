import Foundation

/// Explicit audio work only. The single slot remains occupied through actual account-lease exit.
@MainActor
final class ObservationAudioExecutionOwner {
    enum Admission { case started, coalesced, unavailable }
    struct Key: Equatable {
        let snapshot: ObservationAudioExecutionStore.Snapshot
        let session: AuthTransitionSession
        let generation: UInt64
        let container: ObjectIdentifier
    }
    struct Scope {
        let mayDispatch: @MainActor @Sendable () -> Bool
        let maySettleKnownReceipt: @MainActor @Sendable () -> Bool
    }
    private struct Entry {
        let key: Key
        let token: UUID
        let task: Task<Void, Never>
        var cancelled = false
        var invalidated = false
    }
    private var entry: Entry?
    private var drains = 0
    private var authInvalidationPending = false
    var isRunning: Bool { entry != nil }

    /// The common predicate fences account/session/generation/container, never presentation or connectivity.
    /// The operation owns durable claims; these process-local predicates cannot grant provider execution.
    @discardableResult
    func start(_ key: Key, account: ObservationHistoryCloudClient,
               isCurrent: @escaping @MainActor @Sendable () -> Bool,
               operation: @escaping @MainActor (Scope) async -> Void,
               didFinish: @escaping @MainActor () -> Void) -> Admission {
        guard drains == 0, !authInvalidationPending, !Task.isCancelled, isCurrent(),
              key.session.userID == key.snapshot.work.intent.ownerID else { return .unavailable }
        if let entry {
            return entry.key == key && !entry.cancelled && !entry.invalidated ? .coalesced : .unavailable
        }
        let token = UUID()
        let task = Task { @MainActor [self] in
            defer { if entry?.token == token { entry = nil; didFinish() } }
            guard !Task.isCancelled, isCurrent(), entry?.token == token,
                  entry?.cancelled == false, entry?.invalidated == false,
                  let lease = try? account.begin(key.session.userID) else { return }
            // Finish the lease before clearing the slot or publishing actual-exit notification.
            defer { account.finish(lease) }
            let settlement: @MainActor @Sendable () -> Bool = { [self] in
                entry?.token == token && entry?.invalidated == false && isCurrent() &&
                    lease.session == key.session && account.isCurrent(lease)
            }
            guard settlement(), !Task.isCancelled, entry?.cancelled == false else { return }
            await operation(Scope(mayDispatch: { [self] in
                settlement() && entry?.cancelled == false && !Task.isCancelled
            }, maySettleKnownReceipt: settlement))
        }
        entry = Entry(key: key, token: token, task: task)
        return .started
    }

    /// Connectivity cancellation stops new dispatch, but does not discard a known same-scope answer.
    func cancel() { entry?.cancelled = true; entry?.task.cancel() }

    func invalidate() {
        authInvalidationPending = true
        entry?.invalidated = true
        cancel()
    }

    /// Overlapping drains keep admission closed until every captured retained task has exited.
    func invalidateAndAwait() async {
        drains += 1
        defer { drains -= 1; if drains == 0 { authInvalidationPending = false } }
        let task = entry?.task
        invalidate()
        await task?.value
    }
}
