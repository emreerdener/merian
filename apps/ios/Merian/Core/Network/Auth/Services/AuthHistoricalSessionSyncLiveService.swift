import Foundation

struct AuthHistoricalSessionSyncWork {
    let markStarted: @MainActor () -> Void
    let syncPreferredNames: @MainActor () async -> Void
    let syncHistoricalScans: @MainActor () async -> Void
}

struct HistoricalSessionSyncLiveDependencies {
    let makeWork: @MainActor () -> AuthHistoricalSessionSyncWork?
}

struct AuthHistoricalSessionSyncKey: Equatable {
    let session: AuthTransitionSession
    let authGeneration: UInt64
}

/// Coalesces foreground and listener work for the same published session.
/// Retains displaced tasks until completion so teardown can still cancel them.
@MainActor
final class AuthHistoricalSessionSyncLiveService {
    private let dependencies: HistoricalSessionSyncLiveDependencies
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var activeKey: AuthHistoricalSessionSyncKey?
    private var activeTaskID: UUID?

    init(dependencies: HistoricalSessionSyncLiveDependencies) {
        self.dependencies = dependencies
    }

    deinit {
        for task in tasks.values {
            task.cancel()
        }
    }

    @discardableResult
    func schedule(
        key: AuthHistoricalSessionSyncKey,
        isCurrentSession: @escaping @MainActor () -> Bool
    ) -> Task<Void, Never>? {
        guard !Task.isCancelled, isCurrentSession() else { return nil }
        if activeKey == key, let activeTaskID,
           let task = tasks[activeTaskID], !task.isCancelled {
            return task
        }
        for task in tasks.values { task.cancel() }
        activeKey = nil
        activeTaskID = nil
        guard let work = dependencies.makeWork() else { return nil }
        let taskID = UUID()
        activeKey = key
        activeTaskID = taskID
        tasks[taskID] = Task { @MainActor [weak self] in
            defer { self?.clearTask(taskID) }
            guard !Task.isCancelled, isCurrentSession() else { return }
            work.markStarted()
            await work.syncPreferredNames()
            guard !Task.isCancelled, isCurrentSession() else { return }
            await work.syncHistoricalScans()
        }
        return tasks[taskID]
    }

    func cancel() {
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll()
        activeKey = nil
        activeTaskID = nil
    }

    private func clearTask(_ taskID: UUID) {
        tasks[taskID] = nil
        if activeTaskID == taskID {
            activeKey = nil
            activeTaskID = nil
        }
    }
}
