import Foundation

/// Owns the replacement-safe replay of the current SDK Auth state after a
/// provider transition stops deferring listener side effects. SDK snapshots,
/// lifecycle effects, and postflight validation remain injected by the facade.
@MainActor
final class AuthLifecycleReplayCoordinator {
    private var task: Task<Void, Never>?
    private var taskID: UUID?
    private var needsReconciliation = false

    deinit {
        task?.cancel()
    }

    /// Replaces any synthetic replay with the newer SDK event. Stable events
    /// are processed directly by the listener; transition-deferred events are
    /// retained for the transition-finish boundary.
    func observeLifecycleEvent(deferredByActiveTransition: Bool) {
        cancelTask()
        needsReconciliation = deferredByActiveTransition
    }

    /// A newly admitted transition invalidates a scheduled replay but retains
    /// its obligation for the next stable transition-finish boundary.
    func authTransitionWillBegin() {
        if task != nil {
            needsReconciliation = true
        }
        cancelTask()
    }

    @discardableResult
    func scheduleIfNeeded(
        operation: @escaping @MainActor () async -> Void
    ) -> Bool {
        guard needsReconciliation else { return false }
        needsReconciliation = false
        cancelTask()
        let taskID = UUID()
        self.taskID = taskID
        task = Task { @MainActor [weak self] in
            guard !Task.isCancelled,
                  self?.taskID == taskID else {
                return
            }
            await operation()
            self?.clearTaskIfCurrent(taskID)
        }
        return true
    }

    func cancel() {
        needsReconciliation = false
        cancelTask()
    }

    private func cancelTask() {
        task?.cancel()
        task = nil
        taskID = nil
    }

    private func clearTaskIfCurrent(_ completedTaskID: UUID) {
        guard taskID == completedTaskID else { return }
        task = nil
        taskID = nil
    }
}
