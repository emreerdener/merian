import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager), .timeLimit(.minutes(1)))
struct ObservationAnalysisReviewSchedulingTests {
    let fixture = ObservationAnalysisReviewPersistenceTests()

    @Test func deadlineAndFallbackRequireSameOwnerAndContainer() throws {
        let container = try fixture.container(), intent = try fixture.stage(container)
        let manager = OfflineQueueManager.shared, previous = manager.modelContext
        manager.modelContext = ModelContext(container)
        defer { manager.modelContext = previous }
        var owner: UUID? = fixture.owner
        let scheduler = scheduler(owner: { owner })
        defer { scheduler.cancelScheduledWake(using: manager) }
        let due = try #require(scheduler.nextPersistedWakeDate(using: manager))
        owner = UUID(); #expect(scheduler.nextPersistedWakeDate(using: manager) == nil)
        owner = fixture.owner
        let clock = due.addingTimeInterval(10), floor = clock.addingTimeInterval(5)
        scheduler.scheduleAnalysisReviewRetry(using: manager, ownerID: fixture.owner, container: container, now: clock)
        #expect(scheduler.nextPersistedWakeDate(using: manager) == floor)
        let replacement = try fixture.container()
        manager.modelContext = ModelContext(replacement)
        #expect(scheduler.nextPersistedWakeDate(using: manager) == nil)
        scheduler.analysisReviewDrainDidStart(using: manager, ownerID: fixture.owner, container: replacement)
        manager.modelContext = ModelContext(container)
        #expect(scheduler.nextPersistedWakeDate(using: manager) == floor)
        scheduler.analysisReviewDrainDidStart(using: manager, ownerID: fixture.owner, container: container)
        #expect(scheduler.nextPersistedWakeDate(using: manager) == due)
        let claim = try fixture.claim(intent, in: container)
        #expect(scheduler.nextPersistedWakeDate(using: manager) == claim.expiresAt)
        try ObservationAnalysisReviewPersistence.retry(claim, at: fixture.now, needsAttention: true, container: container, isCurrent: { true })
        #expect(scheduler.nextPersistedWakeDate(using: manager) == nil)
    }

    @Test func runningOwnerSuppressesTimerUntilActualExit() async throws {
        let container = try fixture.container(); _ = try fixture.stage(container)
        let manager = OfflineQueueManager.shared, previous = manager.modelContext
        manager.modelContext = ModelContext(container)
        defer { manager.modelContext = previous }
        let scheduler = scheduler(owner: { fixture.owner })
        defer { scheduler.cancelScheduledWake(using: manager) }
        let due = try #require(scheduler.nextPersistedWakeDate(using: manager))
        var release: CheckedContinuation<Void, Never>?
        let entered = AsyncStream<Void>.makeStream()
        defer { entered.continuation.finish() }
        #expect(manager.analysisReviewDeliveryOwner.start(operation: { _ in
            await withCheckedContinuation { release = $0; entered.continuation.yield(()) }
        }, didFinish: {}))
        var iterator = entered.stream.makeAsyncIterator(); _ = await iterator.next()
        #expect(scheduler.nextPersistedWakeDate(using: manager) == nil)
        manager.analysisReviewDeliveryOwner.cancel()
        #expect(scheduler.nextPersistedWakeDate(using: manager) == nil)
        try #require(release).resume(); await manager.analysisReviewDeliveryOwner.cancelAndAwait()
        #expect(scheduler.nextPersistedWakeDate(using: manager) == due)
    }

    @Test func dedicatedDrainStartsBeforeAwaitedLegacyWork() async {
        let manager = OfflineQueueManager.shared, online = manager.isOnline
        manager.isOnline = true
        defer { manager.isOnline = online }
        var order: [String] = []
        let scheduler = OfflineJobScheduler(drainOperations: .init(
            syncLibraryDetails: { _ in order.append("details") }, syncAnalysisReviews: { _ in order.append("review") },
            reconcileFunding: { _ in }, syncPendingScans: { _ in }, replayInference: { _ in },
            replayFieldTripProgress: { _ in }, syncPendingDeletions: { _ in }, syncCollections: { _ in }))
        defer { scheduler.cancelScheduledWake(using: manager) }
        await scheduler.drainRunnableJobs(using: manager)
        #expect(order == ["review", "details"])
    }

    private func scheduler(owner: @escaping @MainActor () -> UUID?) -> OfflineJobScheduler {
        .init(drainOperations: .init(reconcileFunding: { _ in }, syncPendingScans: { _ in }, replayInference: { _ in },
            replayFieldTripProgress: { _ in }, syncPendingDeletions: { _ in }, syncCollections: { _ in }), deletionAccountID: owner)
    }
}
