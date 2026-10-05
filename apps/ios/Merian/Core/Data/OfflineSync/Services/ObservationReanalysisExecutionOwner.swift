import Foundation

/// A single retained execution pass. Cancellation invalidates authority immediately;
/// the slot stays occupied until the task actually releases its account leases.
@MainActor
final class ObservationReanalysisExecutionOwner {
    private struct Entry {
        let token: UUID
        let task: Task<Void, Never>
        var cancelled = false
    }
    private var entry: Entry?
    var isRunning: Bool { entry != nil }

    @discardableResult
    func start(operation: @escaping @MainActor (@escaping @MainActor @Sendable () -> Bool) async -> Void,
               didFinish: @escaping @MainActor () -> Void) -> Bool {
        guard entry == nil, !Task.isCancelled else { return false }
        let token = UUID()
        let task = Task { @MainActor [self] in
            defer {
                if entry?.token == token { entry = nil; didFinish() }
            }
            await operation { [self] in entry?.token == token && entry?.cancelled == false }
        }
        entry = Entry(token: token, task: task)
        return true
    }

    func cancel() {
        entry?.cancelled = true
        entry?.task.cancel()
    }

    func cancelAndAwait() async {
        let task = entry?.task
        cancel()
        await task?.value
    }
}
