import Foundation

/// Joins the entire capture/preparation operation, including work between
/// original-store reads. Cancellation alone never acknowledges runtime exit.
@MainActor
final class CaptureInitialDraftWorkHost {
    @MainActor struct Retained<Value: Sendable> {
        private let value: Value
        private let requireCurrent: () throws -> Void
        private let dispose: () async -> Bool

        fileprivate init(value: Value, requireCurrent: @escaping () throws -> Void,
                         dispose: @escaping () async -> Bool) {
            self.value = value; self.requireCurrent = requireCurrent; self.dispose = dispose
        }

        func currentValue() throws -> Value { try requireCurrent(); return value }
        @discardableResult func release() async -> Bool { await dispose() }
    }

    @MainActor private final class Resource {
        let cleanup: () async -> Bool
        var released = false
        private(set) var invalidated = false
        private var cleaning = false
        private var waiters: [CheckedContinuation<Bool, Never>] = []
        init(cleanup: @escaping () async -> Bool) { self.cleanup = cleanup }

        func release() async -> Bool {
            if released { return true }
            if cleaning { return await withCheckedContinuation { waiters.append($0) } }
            invalidated = true
            cleaning = true
            let result = await cleanup()
            released = result; cleaning = false
            let pending = waiters; waiters.removeAll()
            for waiter in pending { waiter.resume(returning: result) }
            return result
        }
    }

    @MainActor private final class Work {
        let cancel: () -> Void
        var exited = false
        var waiters: [CheckedContinuation<Void, Never>] = []
        init(cancel: @escaping () -> Void) { self.cancel = cancel }
        func finish() {
            exited = true
            let pending = waiters; waiters.removeAll()
            for waiter in pending { waiter.resume() }
        }
        func join() async {
            if exited { return }
            await withCheckedContinuation { waiters.append($0) }
        }
    }
    private var active: Work?
    private var retained: [UUID: Resource] = [:]
    private(set) var isClosed = false
    var isQuiescent: Bool { active == nil && retained.isEmpty }

    /// Registers cleanup before preparation begins, so a failed operation's
    /// partial files have the same lifetime as a delivered idle presentation.
    /// The caller releases the previous presentation before requesting another.
    func runRetained<Value: Sendable>(
        requireCurrent: @escaping @MainActor () throws -> Void,
        operation: @escaping @MainActor () async throws -> Value,
        cleanup: @escaping @MainActor () async -> Bool
    ) async throws -> Retained<Value> {
        guard !isClosed, active == nil, retained.isEmpty else { throw SharedMediaStorageFailure.closed }
        try requireCurrent(); try Task.checkCancellation()
        let id = UUID(), resource = Resource(cleanup: cleanup)
        retained[id] = resource
        do {
            let value = try await run(requireCurrent: requireCurrent, operation: operation)
            let current: @MainActor () throws -> Void = { [self] in
                guard !isClosed, retained[id] === resource, !resource.invalidated else {
                    throw SharedMediaStorageFailure.closed
                }
                try requireCurrent()
            }
            // run() returns across an actor suspension. Requalify the retained
            // resource before delivery; close may already have disposed it.
            try current(); try Task.checkCancellation()
            return Retained(value: value, requireCurrent: current,
                dispose: { [self] in await release(id, resource: resource) })
        } catch {
            _ = await release(id, resource: resource)
            throw error
        }
    }

    private func release(_ id: UUID, resource: Resource) async -> Bool {
        if resource.released { return true }
        guard retained[id] === resource else { return false }
        let result = await resource.release()
        if result, retained[id] === resource { retained[id] = nil }
        return result
    }

    func run<Value: Sendable>(
        requireCurrent: @escaping @MainActor () throws -> Void,
        operation: @escaping @MainActor () async throws -> Value,
        discard: @escaping @MainActor (Value) async -> Void = { _ in }
    ) async throws -> Value {
        guard !isClosed, active == nil else { throw SharedMediaStorageFailure.closed }
        try requireCurrent(); try Task.checkCancellation()
        let task = Task { @MainActor in try await operation() }
        let work = Work(cancel: { task.cancel() })
        active = work
        defer { active = nil; work.finish() }
        return try await withTaskCancellationHandler {
            let value = try await task.value
            do {
                guard !isClosed else { throw SharedMediaStorageFailure.closed }
                try requireCurrent(); try Task.checkCancellation()
                return value
            } catch {
                // A worker may return successfully after cancellation. Its
                // disposable result must be retired before this work exits.
                await discard(value)
                throw error
            }
        } onCancel: { task.cancel() }
    }

    func close() async -> Bool {
        isClosed = true
        let work = active
        work?.cancel()
        await work?.join()
        for (id, resource) in Array(retained) { _ = await release(id, resource: resource) }
        return isQuiescent
    }
}
