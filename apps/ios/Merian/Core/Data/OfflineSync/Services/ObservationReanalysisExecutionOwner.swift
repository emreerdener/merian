import Foundation

/// A single retained execution pass. Cancellation stops dispatch immediately;
/// the slot stays occupied until the task actually releases its account leases.
@MainActor
final class ObservationReanalysisExecutionOwner {
    struct Scope {
        let mayDispatch: @MainActor @Sendable () -> Bool
        let maySettleKnownReceipt: @MainActor @Sendable () -> Bool
    }
    private struct Entry {
        let token: UUID
        let task: Task<Void, Never>
        var cancelled = false
        var settlementInvalidated = false
    }
    private var entry: Entry?
    var isRunning: Bool { entry != nil }

    @discardableResult
    func start(operation: @escaping @MainActor (Scope) async -> Void,
               didFinish: @escaping @MainActor () -> Void) -> Bool {
        guard entry == nil, !Task.isCancelled else { return false }
        let token = UUID()
        let task = Task { @MainActor [self] in
            defer {
                if entry?.token == token { entry = nil; didFinish() }
            }
            await operation(Scope(mayDispatch: { [self] in entry?.token == token && entry?.cancelled == false },
                maySettleKnownReceipt: { [self] in entry?.token == token && entry?.settlementInvalidated == false }))
        }
        entry = Entry(token: token, task: task)
        return true
    }

    func cancel() {
        entry?.cancelled = true
        entry?.task.cancel()
    }

    /// Auth teardown invalidates settlement before draining account leases.
    func invalidate() {
        entry?.settlementInvalidated = true
        cancel()
    }

    func cancelAndAwait() async {
        let task = entry?.task
        invalidate()
        await task?.value
    }
}
