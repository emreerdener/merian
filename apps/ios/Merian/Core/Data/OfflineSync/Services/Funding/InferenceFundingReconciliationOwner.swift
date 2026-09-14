import Foundation

/// Retains accepted-result account leases until all requested funding
/// reconciliation passes finish or Auth cancellation drains the task.
@MainActor
final class InferenceFundingReconciliationOwner {
    struct Dependencies {
        let reconcile: @MainActor (AccountBoundWorkLease) async -> Void
        let isLeaseCurrent: @MainActor (AccountBoundWorkLease) -> Bool
        let resumeQueueWork: @MainActor () -> Void
        let finishLease: @MainActor (AccountBoundWorkLease) -> Void
    }

    private let dependencies: Dependencies
    private var task: Task<Void, Never>?
    private var generation: UUID?
    private var leases: [AccountBoundWorkLease] = []
    private var reconciliationRequested = false

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func enqueue(lease: AccountBoundWorkLease) {
        leases.append(lease)
        reconciliationRequested = true
        guard task == nil else { return }

        let generation = UUID()
        self.generation = generation
        task = Task { @MainActor [self] in
            defer { finish(generation: generation) }

            while !Task.isCancelled,
                  self.generation == generation,
                  let lease = leases.first {
                reconciliationRequested = false
                await dependencies.reconcile(lease)
                guard workIsCurrent(generation: generation) else { return }

                dependencies.resumeQueueWork()
                guard reconciliationRequested else { return }
            }
        }
    }

    func awaitCompletion() async {
        await task?.value
    }

    func cancelAndAwait() async {
        let task = task
        task?.cancel()
        await task?.value
    }

    private func workIsCurrent(generation: UUID) -> Bool {
        guard !Task.isCancelled,
              self.generation == generation,
              !leases.isEmpty else {
            return false
        }
        return leases.allSatisfy(dependencies.isLeaseCurrent)
    }

    private func finish(generation: UUID) {
        guard self.generation == generation else { return }
        let leases = leases
        task = nil
        self.generation = nil
        self.leases = []
        reconciliationRequested = false
        for lease in leases {
            dependencies.finishLease(lease)
        }
    }
}
