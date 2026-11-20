import Foundation

/// Retains one actual send until its leases exit. UI cancellation never removes durable intent.
@MainActor
final class ProtectedInsightChatDeliveryOwner {
    typealias Predicate = @MainActor @Sendable () -> Bool
    private struct Entry {
        let token: UUID
        let task: Task<Void, Never>
        var cancelled = false
        var invalidated = false
    }
    private var entry: Entry?
    private var drains = 0
    private var authInvalidationPending = false
    var isRunning: Bool { entry != nil }

    @discardableResult
    func start(operation: @escaping @MainActor (@escaping Predicate, @escaping Predicate) async -> Void,
               didFinish: @escaping @MainActor () -> Void) -> Bool {
        guard entry == nil, drains == 0, !authInvalidationPending, !Task.isCancelled else { return false }
        let token = UUID()
        let task = Task { @MainActor [self] in
            defer { if entry?.token == token { entry = nil; didFinish() } }
            await operation(
                { [self] in entry?.token == token && entry?.invalidated == false },
                { [self] in entry?.token == token && entry?.invalidated == false && entry?.cancelled == false })
        }
        entry = Entry(token: token, task: task)
        return true
    }

    /// Connectivity cancellation stops I/O; a known answer may still settle in the same account.
    func cancel() { entry?.cancelled = true; entry?.task.cancel() }

    /// Auth teardown closes both dispatch and receipt authority before waiting for actual exit.
    func invalidate() { authInvalidationPending = true; entry?.invalidated = true; cancel() }

    func invalidateAndAwait() async {
        drains += 1
        defer { drains -= 1; if drains == 0 { authInvalidationPending = false } }
        let task = entry?.task
        invalidate()
        await task?.value
    }
}
