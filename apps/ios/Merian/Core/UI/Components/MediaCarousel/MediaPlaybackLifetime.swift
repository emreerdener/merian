import Foundation
import Observation

/// Optional owner for a disposable preview. File retirement waits for both
/// player shutdown and the actual exit of decoding/boost work, even when that
/// work ignores cancellation. A closed preview can never start reading again.
@Observable @MainActor
final class MediaPlaybackLifetime {
    private(set) var isClosed = false
    @ObservationIgnored private var operations: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var stop: (@MainActor () -> Void)?
    @ObservationIgnored private var finish: (@MainActor () async -> Void)?
    @ObservationIgnored private var closing: Task<Void, Never>?

    func configure(stop: @escaping @MainActor () -> Void,
                   finish: @escaping @MainActor () async -> Void = {}) throws {
        guard !isClosed, self.stop == nil else { throw CancellationError() }
        self.stop = stop; self.finish = finish
    }

    func run(_ operation: @escaping @MainActor () async -> Void) async {
        guard !isClosed, stop != nil, !Task.isCancelled else { return }
        let id = UUID(), task = Task { @MainActor in await operation() }
        operations[id] = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        operations[id] = nil
    }

    /// Synchronous sealing prevents a queued UI action from starting another
    /// reader while the owner schedules the asynchronous join.
    func seal() {
        guard !isClosed else { return }
        isClosed = true
        operations.values.forEach { $0.cancel() }
        stop?()
    }

    func close() async {
        if let closing { await closing.value; return }
        seal()
        let active = Array(operations.values), stop = stop, finish = finish
        let task = Task { @MainActor in
            for operation in active { await operation.value }
            // Work that ignores cancellation can deliver a late player. Stop
            // it, then release leases/copies only after every reader exits.
            stop?()
            await finish?()
        }
        closing = task
        await task.value
        operations.removeAll(); self.stop = nil; self.finish = nil
    }
}
