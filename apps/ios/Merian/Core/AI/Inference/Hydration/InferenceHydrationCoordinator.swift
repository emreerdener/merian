import Foundation

enum InferenceHydrationResourceLimits {
    static let sessionDeduplicationCapacity =
        InferenceResourceLimits.sessionDeduplicationCapacity
    static let enrichedSpeciesTimeToLive: TimeInterval = 24 * 60 * 60
    static let rateLimitBackoff: TimeInterval = 60
}

/// Owns inference hydration task lifetime and session-scoped request policy.
///
/// `InferenceEngine` still decides what may mutate the active presentation and
/// what is persisted. This owner contains only hydration task handles,
/// deduplication history, the persisted species TTL cache, and the temporary
/// enrichment backoff deadline.
@MainActor
final class InferenceHydrationCoordinator {
    enum TaskSlot: Hashable, Sendable {
        case live
        case historic
        case review
    }

    struct Dependencies {
        let now: @MainActor () -> Date
        let loadEnrichedSpeciesTimestamps: @MainActor () -> [String: Double]
        let persistEnrichedSpeciesTimestamps:
            @MainActor ([String: Double]) -> Void

        static let live = Dependencies(
            now: { .now },
            loadEnrichedSpeciesTimestamps: {
                UserDefaults.standard.dictionary(
                    forKey: UserDefaultsKeys.enrichedSpeciesTimestamps
                ) as? [String: Double] ?? [:]
            },
            persistEnrichedSpeciesTimestamps: { timestamps in
                UserDefaults.standard.set(
                    timestamps,
                    forKey: UserDefaultsKeys.enrichedSpeciesTimestamps
                )
            }
        )
    }

    struct Snapshot: Equatable {
        let activeTaskCount: Int
        let currentTaskSlots: Set<TaskSlot>
        let wikipediaSuccessCount: Int
        let historicEnrichmentAttemptCount: Int
        let enrichedSpeciesCount: Int
        let rateLimitedUntil: Date?
        let isAuthTransitionFenceActive: Bool
    }

    private struct ActiveTask {
        let task: Task<Void, Never>
    }

    private let sessionCapacity: Int
    private let enrichedSpeciesTimeToLive: TimeInterval
    private let dependencies: Dependencies
    private var activeTasks = [UUID: ActiveTask]()
    private var currentTaskIds = [TaskSlot: UUID]()
    private var wikipediaHydrationSuccesses: Set<String> = []
    private var historicEnrichmentAttempts: Set<String> = []
    private var enrichedSpeciesTimestamps: [String: Double]
    private var rateLimitedUntil: Date?
    private var authTransitionFenceActive = false

    init(
        sessionCapacity: Int =
            InferenceHydrationResourceLimits.sessionDeduplicationCapacity,
        enrichedSpeciesTimeToLive: TimeInterval =
            InferenceHydrationResourceLimits.enrichedSpeciesTimeToLive,
        dependencies: Dependencies = .live
    ) {
        precondition(sessionCapacity > 0)
        precondition(enrichedSpeciesTimeToLive > 0)
        self.sessionCapacity = sessionCapacity
        self.enrichedSpeciesTimeToLive = enrichedSpeciesTimeToLive
        self.dependencies = dependencies

        let now = dependencies.now()
        let storedTimestamps = dependencies.loadEnrichedSpeciesTimestamps()
        let currentTimestamps = Self.currentTimestamps(
            from: storedTimestamps,
            at: now,
            timeToLive: enrichedSpeciesTimeToLive
        )
        enrichedSpeciesTimestamps = currentTimestamps
        if currentTimestamps.count != storedTimestamps.count {
            dependencies.persistEnrichedSpeciesTimestamps(currentTimestamps)
        }
    }

    var snapshot: Snapshot {
        Snapshot(
            activeTaskCount: activeTasks.count,
            currentTaskSlots: Set(currentTaskIds.keys),
            wikipediaSuccessCount: wikipediaHydrationSuccesses.count,
            historicEnrichmentAttemptCount: historicEnrichmentAttempts.count,
            enrichedSpeciesCount: enrichedSpeciesTimestamps.count,
            rateLimitedUntil: rateLimitedUntil,
            isAuthTransitionFenceActive: authTransitionFenceActive
        )
    }

    func replaceTask(
        in slot: TaskSlot,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) {
        _ = startReplacingTask(in: slot, operation: operation)
    }

    /// Replaces a slot and waits for that exact task, even if a later caller
    /// replaces the slot while the operation is suspended. The coordinator
    /// retains every replaced task until completion so Auth quiescence also
    /// observes cancellation-ignoring operations.
    func replaceAndAwaitTask(
        in slot: TaskSlot,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) async {
        guard let task = startReplacingTask(
            in: slot,
            operation: operation
        ) else {
            return
        }
        await task.value
    }

    private func startReplacingTask(
        in slot: TaskSlot,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) -> Task<Void, Never>? {
        guard !authTransitionFenceActive else { return nil }
        cancelCurrentTask(in: slot)

        let id = UUID()
        currentTaskIds[slot] = id
        let task = Task { @MainActor [weak self] in
            defer { self?.finishTask(id: id, slot: slot) }
            guard !Task.isCancelled else { return }
            await operation()
        }
        activeTasks[id] = ActiveTask(task: task)
        return task
    }

    func hasCurrentTask(in slot: TaskSlot) -> Bool {
        currentTaskIds[slot] != nil
    }

    func awaitCurrentTask(in slot: TaskSlot) async {
        guard let id = currentTaskIds[slot],
              let task = activeTasks[id]?.task else {
            return
        }
        await task.value
    }

    func cancelCurrentTask(in slot: TaskSlot) {
        guard let id = currentTaskIds[slot] else { return }
        activeTasks[id]?.task.cancel()
    }

    func cancelAllTasks() {
        currentTaskIds.removeAll(keepingCapacity: true)
        for entry in activeTasks.values {
            entry.task.cancel()
        }
    }

    @discardableResult
    func beginAuthTransitionFence() -> Bool {
        guard !authTransitionFenceActive else { return false }
        authTransitionFenceActive = true
        cancelAllTasks()
        return true
    }

    func awaitQuiescence() async {
        guard authTransitionFenceActive else { return }

        while !activeTasks.isEmpty {
            let tasks = activeTasks.values.map(\.task)
            for task in tasks {
                await task.value
            }
            await Task.yield()
        }
    }

    func finishAuthTransitionFence() {
        authTransitionFenceActive = false
    }

    func canHydrateWikipedia(for scientificName: String) -> Bool {
        !wikipediaHydrationSuccesses.contains(scientificName)
    }

    func recordWikipediaHydrationSuccess(for scientificName: String) {
        insertBounded(
            scientificName,
            into: &wikipediaHydrationSuccesses
        )
    }

    func beginHistoricEnrichmentAttempt(scanId: String) -> Bool {
        guard !historicEnrichmentAttempts.contains(scanId) else { return false }
        insertBounded(scanId, into: &historicEnrichmentAttempts)
        return true
    }

    func isSpeciesEnriched(_ scientificName: String) -> Bool {
        guard let timestamp = enrichedSpeciesTimestamps[scientificName] else {
            return false
        }

        let cutoff = dependencies.now().addingTimeInterval(
            -enrichedSpeciesTimeToLive
        ).timeIntervalSinceReferenceDate
        guard timestamp > cutoff else {
            enrichedSpeciesTimestamps.removeValue(forKey: scientificName)
            dependencies.persistEnrichedSpeciesTimestamps(
                enrichedSpeciesTimestamps
            )
            return false
        }
        return true
    }

    func markSpeciesEnriched(_ scientificName: String) {
        let now = dependencies.now()
        pruneExpiredEnrichedSpecies(at: now)
        enrichedSpeciesTimestamps[scientificName] =
            now.timeIntervalSinceReferenceDate
        dependencies.persistEnrichedSpeciesTimestamps(
            enrichedSpeciesTimestamps
        )
    }

    func canAttemptEnrichment() -> Bool {
        guard let rateLimitedUntil else { return true }
        guard rateLimitedUntil <= dependencies.now() else { return false }
        self.rateLimitedUntil = nil
        return true
    }

    func recordEnrichmentRateLimit(
        for duration: TimeInterval =
            InferenceHydrationResourceLimits.rateLimitBackoff
    ) {
        precondition(duration >= 0)
        rateLimitedUntil = dependencies.now().addingTimeInterval(duration)
    }

    func resetEnrichmentRateLimit() {
        rateLimitedUntil = nil
    }

    private func finishTask(id: UUID, slot: TaskSlot) {
        activeTasks.removeValue(forKey: id)
        if currentTaskIds[slot] == id {
            currentTaskIds.removeValue(forKey: slot)
        }
    }

    private func insertBounded(
        _ value: String,
        into values: inout Set<String>
    ) {
        guard !values.contains(value) else { return }
        if values.count >= sessionCapacity {
            let evictionCount = max(1, sessionCapacity / 10)
            let evictedValues = Array(values.prefix(evictionCount))
            values.subtract(evictedValues)
        }
        values.insert(value)
    }

    private func pruneExpiredEnrichedSpecies(at now: Date) {
        let current = Self.currentTimestamps(
            from: enrichedSpeciesTimestamps,
            at: now,
            timeToLive: enrichedSpeciesTimeToLive
        )
        enrichedSpeciesTimestamps = current
    }

    private static func currentTimestamps(
        from timestamps: [String: Double],
        at now: Date,
        timeToLive: TimeInterval
    ) -> [String: Double] {
        let cutoff = now.addingTimeInterval(-timeToLive)
            .timeIntervalSinceReferenceDate
        return timestamps.filter { $0.value > cutoff }
    }
}
