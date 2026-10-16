import Foundation

/// Shared by Capture preparation and local recovery. Reserve before touching durable metadata;
/// file locks then protect the bytes. Cancellation retains the slot until its task actually exits.
@MainActor
final class ObservationReanalysisPreparationOwner {
    enum Failure: Error { case busy, draining }
    typealias Validator = @MainActor @Sendable () -> Bool
    private struct Entry {
        let token: UUID
        let cancel: () -> Void
        let wait: () async -> Void
        var cancelled = false
    }
    private var entries: [UUID: Entry] = [:]
    private var drains = 0

    func contains(_ child: UUID) -> Bool { entries[child] != nil }

    func perform<Value: Sendable>(_ identity: OfflineQueueWork.Reanalysis,
                                  operation: @escaping @MainActor @Sendable (@escaping Validator) async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        guard drains == 0 else { throw Failure.draining }
        let child = identity.analysisID, token = UUID()
        guard entries[child] == nil else { throw Failure.busy }
        let task = Task { @MainActor [self] in
            defer { if entries[child]?.token == token { entries[child] = nil } }
            try Task.checkCancellation()
            let result = try await operation { [self] in entries[child]?.token == token && entries[child]?.cancelled == false }
            try Task.checkCancellation()
            guard entries[child]?.token == token, entries[child]?.cancelled == false else { throw CancellationError() }
            return result
        }
        entries[child] = Entry(token: token, cancel: { task.cancel() }, wait: { _ = await task.result })
        return try await withTaskCancellationHandler {
            let result = try await task.value
            // A durable commit may survive cancellation; its former caller cannot receive a stale private result.
            try Task.checkCancellation()
            return result
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(child, token: token) }
        }
    }

    func cancelAll() {
        for (child, entry) in entries { cancel(child, token: entry.token) }
    }

    /// Coalesced callers all retain a start barrier until their captured tasks have drained.
    func cancelAndAwaitAll() async {
        drains += 1
        defer { drains -= 1 }
        let active = Array(entries.values)
        cancelAll()
        for entry in active { await entry.wait() }
    }

    private func cancel(_ child: UUID, token: UUID) {
        guard entries[child]?.token == token else { return }
        entries[child]?.cancelled = true
        entries[child]?.cancel()
    }
}
