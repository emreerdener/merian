import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
@Suite("Offline Job Scheduler", .timeLimit(.minutes(1)), .sharedProcessState(.offlineQueueManager))
struct OfflineJobSchedulerTests {
    enum Step: String, CaseIterable {
        case funding, uploads, inference, progress, deletions, collections

        var isAsync: Bool { self == .funding || self == .progress || self == .deletions }

        var events: [String] {
            isAsync ? ["\(rawValue).started", "\(rawValue).finished"] : [rawValue]
        }
    }

    @Test(arguments: [Step.funding, .progress, .deletions])
    func eligibleDrainArmsWakeAndAwaitsEffectsInOrder(suspendedStep: Step) async throws {
        let manager = OfflineQueueManager.shared
        let originalOnline = manager.isOnline
        let (context, retryDate) = try makeRetryContext()
        manager.modelContext = context
        manager.isOnline = true
        defer { manager.isOnline = originalOnline }
        try #require(!manager.isCurrentNetworkConstrained)

        var events: [String] = []
        let entered = AsyncStream<Void>.makeStream()
        let resume = AsyncStream<Void>.makeStream()
        defer {
            entered.continuation.finish()
            resume.continuation.finish()
        }
        let record: @MainActor (Step, OfflineQueueManager) -> Void = { step, received in
            #expect(received === manager)
            events.append(step.rawValue)
        }
        let recordAsync: @MainActor (Step, OfflineQueueManager) async -> Void = { step, received in
            #expect(received === manager)
            events.append("\(step.rawValue).started")
            if step == suspendedStep {
                entered.continuation.yield(())
                var iterator = resume.stream.makeAsyncIterator()
                _ = await iterator.next()
            }
            events.append("\(step.rawValue).finished")
        }
        let scheduler = OfflineJobScheduler(drainOperations: .init(
            reconcileFunding: { await recordAsync(.funding, $0) },
            syncPendingScans: { record(.uploads, $0) },
            replayInference: { record(.inference, $0) },
            replayFieldTripProgress: { await recordAsync(.progress, $0) },
            syncPendingDeletions: { await recordAsync(.deletions, $0) },
            syncCollections: { record(.collections, $0) }
        ))
        // This scheduler owns only this fixture's timer, never the app host's.
        defer { scheduler.cancelScheduledWake(using: manager) }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                defer { entered.continuation.finish() }
                await scheduler.drainRunnableJobs(using: manager)
            }
            var iterator = entered.stream.makeAsyncIterator()
            guard await iterator.next() != nil else {
                Issue.record("The scheduler never reached the expected asynchronous drain")
                group.cancelAll()
                return
            }
            let precedingEvents = Step.allCases.prefix { $0 != suspendedStep }.flatMap(\.events)
            #expect(events == precedingEvents + ["\(suspendedStep.rawValue).started"])
            #expect(scheduler.scheduledWakeDate == retryDate)
            resume.continuation.finish()
            await group.waitForAll()
        }

        #expect(events == Step.allCases.flatMap(\.events))
        #expect(scheduler.scheduledWakeDate == retryDate)
    }

    @Test func offlineDrainCancelsItsWakeWithoutDispatchingAnyEffect() async throws {
        let manager = OfflineQueueManager.shared
        let originalOnline = manager.isOnline
        let (context, _) = try makeRetryContext()
        manager.modelContext = context
        manager.isOnline = true
        defer { manager.isOnline = originalOnline }
        try #require(!manager.isCurrentNetworkConstrained)

        var effectCount = 0
        let unexpected: @MainActor (OfflineQueueManager) -> Void = { _ in effectCount += 1 }
        let scheduler = OfflineJobScheduler(drainOperations: .init(
            reconcileFunding: { unexpected($0) },
            syncPendingScans: unexpected,
            replayInference: unexpected,
            replayFieldTripProgress: { unexpected($0) },
            syncPendingDeletions: { unexpected($0) },
            syncCollections: unexpected
        ))
        defer { scheduler.cancelScheduledWake(using: manager) }
        scheduler.scheduleNextPersistedWake(using: manager)
        try #require(scheduler.scheduledWakeDate != nil)

        manager.isOnline = false
        await scheduler.drainRunnableJobs(using: manager)

        #expect(effectCount == 0)
        #expect(scheduler.scheduledWakeDate == nil)
    }

    private func makeRetryContext() throws -> (ModelContext, Date) {
        let schema = Schema(CurrentSchema.models)
        let container = try ModelContainer(
            for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let retryDate = Date().addingTimeInterval(3_600)
        context.insert(OfflineQueuedScan(
            id: UUID().uuidString.lowercased(), scanState: .staged, queueNextRetryAt: retryDate
        ))
        try context.save()
        return (context, retryDate)
    }
}
