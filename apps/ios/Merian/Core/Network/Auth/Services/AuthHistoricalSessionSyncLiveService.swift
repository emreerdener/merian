import Foundation

struct AuthHistoricalSessionSyncWork {
    let markStarted: @MainActor () -> Void
    let syncPreferredNames: @MainActor () async -> Void
    let syncHistoricalScans: @MainActor () async -> Void
}

struct HistoricalSessionSyncLiveDependencies {
    let makeWork: @MainActor () -> AuthHistoricalSessionSyncWork?
}

/// Retains every listener-admitted historical synchronization task so facade
/// teardown can cancel work that has not crossed its final session fence.
@MainActor
final class AuthHistoricalSessionSyncLiveService {
    private let dependencies: HistoricalSessionSyncLiveDependencies
    private var tasks: [UUID: Task<Void, Never>] = [:]

    init(dependencies: HistoricalSessionSyncLiveDependencies) {
        self.dependencies = dependencies
    }

    deinit {
        for task in tasks.values {
            task.cancel()
        }
    }

    func schedule(
        isCurrentSession: @escaping @MainActor () -> Bool
    ) {
        guard let work = dependencies.makeWork() else { return }
        let taskID = UUID()
        tasks[taskID] = Task { @MainActor [weak self] in
            defer { self?.clearTask(taskID) }
            guard !Task.isCancelled, isCurrentSession() else { return }
            work.markStarted()
            await work.syncPreferredNames()
            guard !Task.isCancelled, isCurrentSession() else { return }
            await work.syncHistoricalScans()
        }
    }

    func cancel() {
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll()
    }

    private func clearTask(_ taskID: UUID) {
        tasks[taskID] = nil
    }
}
