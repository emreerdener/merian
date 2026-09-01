import Foundation

enum InferenceResourceLimits {
    static let sessionDeduplicationCapacity = 500
    static let activeBackgroundWriteCapacity = 8
    static let pendingBackgroundWriteCapacity = 8
}

/// Owns the bounded, presentation-generation-fenced write queue used by
/// `InferenceEngine`.
///
/// Mutable task storage stays private to this owner. The engine coordinates
/// presentation lifecycle, while this type enforces capacity, cancellation,
/// Auth-transition quiescence, and newest-identification final-writer ordering.
@MainActor
final class InferenceWriteCoordinator {
    enum IdentificationChannel: Sendable {
        case review
        case confirmation
        case legacyFlag
    }

    struct Snapshot: Sendable, Equatable {
        let active: Int
        let pending: Int
        let generation: UInt64
    }

    private struct PendingWrite {
        let generation: UInt64
        let operation: @Sendable () async -> Void
    }

    let activeTaskCapacity: Int
    let pendingTaskCapacity: Int

    private let identificationActionCapacity: Int
    private var activeTasks = [UUID: Task<Void, Never>]()
    private var pendingTasks: [PendingWrite] = []
    private var presentationGeneration: UInt64 = 0
    private var authTransitionFenceActive = false
    private var reviewActionClock: UInt64 = 0
    private var reviewActionGenerations: [String: UInt64] = [:]
    private var confirmationActionClock: UInt64 = 0
    private var confirmationActionGenerations: [String: UInt64] = [:]
    private var flagActionClock: UInt64 = 0
    private var flagActionGenerations: [String: UInt64] = [:]
    private var reviewWriteTail: Task<Void, Never>?

    init(
        activeTaskCapacity: Int = InferenceResourceLimits.activeBackgroundWriteCapacity,
        pendingTaskCapacity: Int = InferenceResourceLimits.pendingBackgroundWriteCapacity,
        identificationActionCapacity: Int = InferenceResourceLimits.sessionDeduplicationCapacity
    ) {
        precondition(activeTaskCapacity > 0)
        precondition(pendingTaskCapacity >= 0)
        precondition(identificationActionCapacity > 0)
        self.activeTaskCapacity = activeTaskCapacity
        self.pendingTaskCapacity = pendingTaskCapacity
        self.identificationActionCapacity = identificationActionCapacity
    }

    var generation: UInt64 {
        presentationGeneration
    }

    var isAuthTransitionFenceActive: Bool {
        authTransitionFenceActive
    }

    var snapshot: Snapshot {
        Snapshot(
            active: activeTasks.count,
            pending: pendingTasks.count,
            generation: presentationGeneration
        )
    }

    func enqueueBackgroundWrite(
        _ operation: @escaping @Sendable () async -> Void
    ) {
        guard !authTransitionFenceActive else { return }
        let generation = presentationGeneration
        guard activeTasks.count < activeTaskCapacity else {
            guard pendingTasks.count < pendingTaskCapacity else { return }
            pendingTasks.append(
                PendingWrite(
                    generation: generation,
                    operation: operation
                )
            )
            return
        }
        startBackgroundWrite(operation, generation: generation)
    }

    func resetPresentationWrites() {
        presentationGeneration &+= 1
        pendingTasks.removeAll(keepingCapacity: false)
        for task in activeTasks.values {
            task.cancel()
        }

        // Retain active handles until their completion callbacks remove them.
        // A task may ignore cancellation while suspended, and Auth transitions
        // must still wait for that work to quiesce. Retain the cancelled review
        // tail as the next action's predecessor for the same final-writer rule.
        reviewWriteTail?.cancel()
    }

    func beginIdentificationAction(
        scanId: String,
        channel: IdentificationChannel
    ) -> UInt64 {
        switch channel {
        case .review:
            return beginAction(
                scanId: scanId,
                clock: &reviewActionClock,
                generations: &reviewActionGenerations
            )
        case .confirmation:
            return beginAction(
                scanId: scanId,
                clock: &confirmationActionClock,
                generations: &confirmationActionGenerations
            )
        case .legacyFlag:
            return beginAction(
                scanId: scanId,
                clock: &flagActionClock,
                generations: &flagActionGenerations
            )
        }
    }

    func isIdentificationActionCurrent(
        scanId: String,
        generation: UInt64,
        channel: IdentificationChannel
    ) -> Bool {
        let key = scanId.lowercased()
        switch channel {
        case .review:
            return reviewActionGenerations[key] == generation
        case .confirmation:
            return confirmationActionGenerations[key] == generation
        case .legacyFlag:
            return flagActionGenerations[key] == generation
        }
    }

    @discardableResult
    func enqueueIdentificationWrite(
        scanId: String,
        actionGeneration: UInt64,
        channel: IdentificationChannel,
        operation: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never>? {
        guard !authTransitionFenceActive else { return nil }
        let predecessor = reviewWriteTail
        let generation = presentationGeneration
        let task = Task { @MainActor [weak self] in
            _ = await predecessor?.value
            guard !Task.isCancelled,
                  let self,
                  self.presentationGeneration == generation,
                  self.isIdentificationActionCurrent(
                      scanId: scanId,
                      generation: actionGeneration,
                      channel: channel
                  ) else {
                return
            }
            await operation()
        }
        reviewWriteTail = task
        return task
    }

    @discardableResult
    func beginAuthTransitionFence() -> Bool {
        guard !authTransitionFenceActive else { return false }
        authTransitionFenceActive = true
        return true
    }

    func awaitQuiescence() async {
        guard authTransitionFenceActive else { return }

        _ = await reviewWriteTail?.result
        while !activeTasks.isEmpty {
            let tasks = Array(activeTasks.values)
            for task in tasks {
                await task.value
            }
            await Task.yield()
        }
        reviewWriteTail = nil
    }

    func finishAuthTransitionFence() {
        authTransitionFenceActive = false
    }

    private func startBackgroundWrite(
        _ operation: @escaping @Sendable () async -> Void,
        generation: UInt64
    ) {
        guard !authTransitionFenceActive,
              generation == presentationGeneration else {
            return
        }

        let id = UUID()
        let task = Task { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.finishBackgroundWrite(id: id)
                }
            }
            guard !Task.isCancelled else { return }
            await operation()
        }
        activeTasks[id] = task
    }

    private func finishBackgroundWrite(id: UUID) {
        activeTasks.removeValue(forKey: id)
        drainPendingWrites()
    }

    private func drainPendingWrites() {
        while activeTasks.count < activeTaskCapacity, !pendingTasks.isEmpty {
            let next = pendingTasks.removeFirst()
            guard next.generation == presentationGeneration else { continue }
            startBackgroundWrite(next.operation, generation: next.generation)
        }
    }

    private func beginAction(
        scanId: String,
        clock: inout UInt64,
        generations: inout [String: UInt64]
    ) -> UInt64 {
        let key = scanId.lowercased()
        if generations[key] == nil,
           generations.count >= identificationActionCapacity,
           let oldestKey = generations.min(by: { $0.value < $1.value })?.key {
            generations.removeValue(forKey: oldestKey)
        }
        clock &+= 1
        generations[key] = clock
        return clock
    }
}
