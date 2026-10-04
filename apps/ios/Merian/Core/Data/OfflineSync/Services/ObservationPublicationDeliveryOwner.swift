import Foundation

/// One retained, cancellable drain per queue manager; Auth awaits actual lease release.
@MainActor
final class ObservationPublicationDeliveryOwner {
    private var task: Task<Void, Never>?
    private var generation: UUID?
    private let didJoin: @MainActor () -> Void
    var isRunning: Bool { task != nil }

    init(didJoin: @escaping @MainActor () -> Void = {}) { self.didJoin = didJoin }

    func run(_ operation: @escaping @MainActor () async -> Void) async {
        guard !Task.isCancelled else { return }
        if let task { didJoin(); await task.value; return }
        let generation = UUID()
        self.generation = generation
        let task = Task { @MainActor [self] in
            defer { finish(generation: generation) }
            await operation()
        }
        self.task = task
        await task.value
    }

    private func finish(generation: UUID) {
        guard self.generation == generation else { return }
        self.task = nil; self.generation = nil
    }

    func cancel() { task?.cancel() }
    func cancelAndAwait() async {
        let task = task
        task?.cancel()
        await task?.value
    }
}
