import Foundation
import Testing

@testable import Merian

private actor HydrationTaskGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var hasStarted = false
    private var isReleased = false

    func wait() async {
        hasStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitUntilStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        isReleased = true
        let waiting = continuations
        continuations.removeAll()
        for continuation in waiting {
            continuation.resume()
        }
    }
}

private actor HydrationTaskRecorder {
    private var values: [Int] = []
    private var waiters: [(
        count: Int,
        continuation: CheckedContinuation<Void, Never>
    )] = []

    func append(_ value: Int) {
        values.append(value)
        var remaining: [(
            count: Int,
            continuation: CheckedContinuation<Void, Never>
        )] = []
        for waiter in waiters {
            if values.count >= waiter.count {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        waiters = remaining
    }

    func waitForCount(_ count: Int) async {
        guard values.count < count else { return }
        await withCheckedContinuation { continuation in
            waiters.append((count, continuation))
        }
    }

    func snapshot() -> [Int] {
        values
    }
}

@MainActor
private final class HydrationPolicyStore {
    var now: Date
    var storedTimestamps: [String: Double]
    var persistedValues: [[String: Double]] = []

    init(now: Date, storedTimestamps: [String: Double] = [:]) {
        self.now = now
        self.storedTimestamps = storedTimestamps
    }

    var dependencies: InferenceHydrationCoordinator.Dependencies {
        .init(
            now: { [weak self] in self?.now ?? .distantPast },
            loadEnrichedSpeciesTimestamps: { [weak self] in
                self?.storedTimestamps ?? [:]
            },
            persistEnrichedSpeciesTimestamps: { [weak self] values in
                self?.storedTimestamps = values
                self?.persistedValues.append(values)
            }
        )
    }
}

@MainActor
@Suite("Inference Hydration Coordinator")
struct InferenceHydrationCoordinatorTests {
    @Test func replacementRetainsCancellationIgnoringTaskForAuthDrain() async {
        let coordinator = makeCoordinator()
        let firstGate = HydrationTaskGate()
        let replacementGate = HydrationTaskGate()
        let recorder = HydrationTaskRecorder()

        coordinator.replaceTask(in: .live) {
            await firstGate.wait()
            await recorder.append(1)
        }
        await firstGate.waitUntilStarted()

        coordinator.replaceTask(in: .live) {
            await replacementGate.wait()
            await recorder.append(2)
        }
        await replacementGate.waitUntilStarted()

        #expect(coordinator.snapshot.activeTaskCount == 2)
        #expect(coordinator.snapshot.currentTaskSlots == [.live])
        #expect(coordinator.beginAuthTransitionFence())

        let drain = Task { @MainActor in
            await coordinator.awaitQuiescence()
            await recorder.append(3)
        }

        await replacementGate.release()
        await recorder.waitForCount(1)
        await Task.yield()
        #expect(await recorder.snapshot() == [2])

        await firstGate.release()
        await drain.value
        #expect(await recorder.snapshot() == [2, 1, 3])
        #expect(coordinator.snapshot.activeTaskCount == 0)
    }

    @Test func authFenceRejectsNewHydrationUntilReleased() async {
        let coordinator = makeCoordinator()
        let recorder = HydrationTaskRecorder()

        #expect(coordinator.beginAuthTransitionFence())
        await coordinator.replaceAndAwaitTask(in: .review) {
            await recorder.append(1)
        }
        await coordinator.awaitQuiescence()
        #expect(await recorder.snapshot().isEmpty)

        coordinator.finishAuthTransitionFence()
        coordinator.replaceTask(in: .review) {
            await recorder.append(2)
        }
        await recorder.waitForCount(1)
        #expect(await recorder.snapshot() == [2])
    }

    @Test func awaitedReplacementWaitsForItsExactTask() async {
        let coordinator = makeCoordinator()
        let firstGate = HydrationTaskGate()
        let replacementGate = HydrationTaskGate()
        let recorder = HydrationTaskRecorder()

        let firstAwaiter = Task { @MainActor in
            await coordinator.replaceAndAwaitTask(in: .review) {
                await firstGate.wait()
                await recorder.append(1)
            }
            await recorder.append(10)
        }
        await firstGate.waitUntilStarted()

        let replacementAwaiter = Task { @MainActor in
            await coordinator.replaceAndAwaitTask(in: .review) {
                await replacementGate.wait()
                await recorder.append(2)
            }
            await recorder.append(20)
        }
        await replacementGate.waitUntilStarted()

        await replacementGate.release()
        await replacementAwaiter.value
        #expect(await recorder.snapshot() == [2, 20])
        #expect(coordinator.snapshot.activeTaskCount == 1)

        await firstGate.release()
        await firstAwaiter.value
        #expect(await recorder.snapshot() == [2, 20, 1, 10])
        #expect(coordinator.snapshot.activeTaskCount == 0)
    }

    @Test func completionOfReplacedTaskCannotClearCurrentSlot() async {
        let coordinator = makeCoordinator()
        let firstGate = HydrationTaskGate()
        let replacementGate = HydrationTaskGate()

        coordinator.replaceTask(in: .historic) {
            await firstGate.wait()
        }
        await firstGate.waitUntilStarted()
        coordinator.replaceTask(in: .historic) {
            await replacementGate.wait()
        }
        await replacementGate.waitUntilStarted()

        await firstGate.release()
        await Task.yield()
        #expect(coordinator.hasCurrentTask(in: .historic))
        #expect(coordinator.snapshot.currentTaskSlots == [.historic])

        await replacementGate.release()
        await coordinator.awaitCurrentTask(in: .historic)
        #expect(!coordinator.hasCurrentTask(in: .historic))
    }

    @Test func sessionRequestHistoriesRemainBounded() {
        let coordinator = makeCoordinator(sessionCapacity: 2)

        coordinator.recordWikipediaHydrationSuccess(for: "species-a")
        coordinator.recordWikipediaHydrationSuccess(for: "species-b")
        coordinator.recordWikipediaHydrationSuccess(for: "species-c")
        #expect(coordinator.snapshot.wikipediaSuccessCount == 2)
        #expect(!coordinator.canHydrateWikipedia(for: "species-c"))

        #expect(coordinator.beginHistoricEnrichmentAttempt(scanId: "scan-a"))
        #expect(coordinator.beginHistoricEnrichmentAttempt(scanId: "scan-b"))
        #expect(coordinator.beginHistoricEnrichmentAttempt(scanId: "scan-c"))
        #expect(!coordinator.beginHistoricEnrichmentAttempt(scanId: "scan-c"))
        #expect(coordinator.snapshot.historicEnrichmentAttemptCount == 2)
    }

    @Test func enrichedSpeciesCachePrunesExpiredValuesAndPersistsUpdates() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let store = HydrationPolicyStore(
            now: now,
            storedTimestamps: [
                "current": now.addingTimeInterval(-30)
                    .timeIntervalSinceReferenceDate,
                "expired": now.addingTimeInterval(-120)
                    .timeIntervalSinceReferenceDate
            ]
        )
        let coordinator = InferenceHydrationCoordinator(
            enrichedSpeciesTimeToLive: 60,
            dependencies: store.dependencies
        )

        #expect(coordinator.isSpeciesEnriched("current"))
        #expect(!coordinator.isSpeciesEnriched("expired"))
        #expect(coordinator.snapshot.enrichedSpeciesCount == 1)
        #expect(store.persistedValues.first?.keys.sorted() == ["current"])

        store.now = now.addingTimeInterval(31)
        #expect(!coordinator.isSpeciesEnriched("current"))
        #expect(store.storedTimestamps.isEmpty)

        coordinator.markSpeciesEnriched("replacement")
        #expect(coordinator.isSpeciesEnriched("replacement"))
        #expect(store.storedTimestamps.keys.sorted() == ["replacement"])
    }

    @Test func enrichmentBackoffExpiresAndCanResetForANewPresentation() {
        let store = HydrationPolicyStore(
            now: Date(timeIntervalSinceReferenceDate: 2_000_000)
        )
        let coordinator = InferenceHydrationCoordinator(
            dependencies: store.dependencies
        )

        coordinator.recordEnrichmentRateLimit(for: 60)
        #expect(!coordinator.canAttemptEnrichment())

        store.now = store.now.addingTimeInterval(61)
        #expect(coordinator.canAttemptEnrichment())
        #expect(coordinator.snapshot.rateLimitedUntil == nil)

        coordinator.recordEnrichmentRateLimit(for: 60)
        #expect(!coordinator.canAttemptEnrichment())
        coordinator.resetEnrichmentRateLimit()
        #expect(coordinator.canAttemptEnrichment())
    }

    private func makeCoordinator(
        sessionCapacity: Int =
            InferenceHydrationResourceLimits.sessionDeduplicationCapacity
    ) -> InferenceHydrationCoordinator {
        InferenceHydrationCoordinator(
            sessionCapacity: sessionCapacity,
            dependencies: .init(
                now: { Date(timeIntervalSinceReferenceDate: 1_000_000) },
                loadEnrichedSpeciesTimestamps: { [:] },
                persistEnrichedSpeciesTimestamps: { _ in }
            )
        )
    }
}
