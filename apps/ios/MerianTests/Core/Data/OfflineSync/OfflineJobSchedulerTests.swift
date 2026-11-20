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

    @Test func detailsAcknowledgmentSaveFailureRetriesAutomatically() async throws {
        let manager = OfflineQueueManager.shared
        let originalOnline = manager.isOnline
        let originalContext = manager.modelContext
        let schema = Schema(CurrentSchema.models)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let owner = UUID()
        let record = LocalScanRecord(speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture", fieldNotes: "Note")
        context.insert(record)
        try LibraryDetailsSyncService.stage(record, ownerID: owner, context: context)
        try context.save()
        manager.modelContext = context
        manager.isOnline = true
        defer {
            manager.isOnline = originalOnline
            manager.modelContext = originalContext
        }
        try #require(!manager.isCurrentNetworkConstrained)
        var scheduler: OfflineJobScheduler?
        var sent: [UUID] = []
        var saves = 0
        let finished = AsyncStream<Void>.makeStream()
        defer {
            scheduler?.cancelScheduledWake(using: manager)
            scheduler = nil
            finished.continuation.finish()
        }
        scheduler = OfflineJobScheduler(drainOperations: .init(
            syncLibraryDetails: { received in
                scheduler?.libraryDetailsDrainDidStart(using: received)
                await LibraryDetailsSyncService.drainPending(
                    context: context, ownerID: owner, isCurrent: { true },
                    requestRetry: { scheduler?.scheduleLibraryDetailsRetry(using: received) },
                    send: { sent.append($0.operationID) },
                    save: { context in
                        saves += 1
                        if saves == 1 { throw CocoaError(.fileWriteUnknown) }
                        try context.save()
                    }
                )
                if saves == 2 { finished.continuation.yield(()) }
            },
            reconcileFunding: { _ in }, syncPendingScans: { _ in }, replayInference: { _ in },
            replayFieldTripProgress: { _ in }, syncPendingDeletions: { _ in }, syncCollections: { _ in }
        ))
        await scheduler?.drainRunnableJobs(using: manager)
        #expect(saves == 1)
        #expect(scheduler?.scheduledWakeDate != nil)
        var iterator = finished.stream.makeAsyncIterator()
        _ = await iterator.next()
        #expect(sent.count == 2)
        #expect(sent.first == sent.last)
        #expect(try context.fetch(FetchDescriptor<OfflineJobRecord>()).first?.status == .complete)
    }

    @Test func detailsRetryPreservesEarlierQueueDeadlineAndSurvivesFencedDrain() async throws {
        let manager = OfflineQueueManager.shared
        let originalOnline = manager.isOnline
        let originalContext = manager.modelContext
        let (context, _) = try makeRetryContext()
        manager.modelContext = context
        manager.isOnline = true
        defer {
            manager.isOnline = originalOnline
            manager.modelContext = originalContext
        }
        let scheduler = OfflineJobScheduler(drainOperations: .init(
            reconcileFunding: { _ in }, syncPendingScans: { _ in }, replayInference: { _ in },
            replayFieldTripProgress: { _ in }, syncPendingDeletions: { _ in }, syncCollections: { _ in }
        ))
        defer { scheduler.cancelScheduledWake(using: manager) }
        let earlier = Date().addingTimeInterval(2)
        let job = OfflineJobRecord(id: "library-details:earlier-fixture", kind: .future, nextRunAt: earlier)
        context.insert(job)
        try context.save()
        scheduler.scheduleLibraryDetailsRetry(using: manager)
        #expect(scheduler.scheduledWakeDate == earlier)
        context.delete(job)
        try context.save()
        // The injected details operation represents an admission-fenced pass;
        // it deliberately never calls libraryDetailsDrainDidStart.
        await scheduler.drainRunnableJobs(using: manager)
        let retained = try #require(scheduler.scheduledWakeDate)
        #expect(retained > earlier)
        #expect(retained < Date().addingTimeInterval(6))
    }

    @Test func unknownAndPreparedJobsDoNotCreateUnserviceableWakeLoops() throws {
        let manager = OfflineQueueManager.shared, previous = manager.modelContext
        let schema = Schema(CurrentSchema.models)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container); manager.modelContext = context
        defer { manager.modelContext = previous }
        let scheduler = OfflineJobScheduler(drainOperations: .init(
            reconcileFunding: { _ in }, syncPendingScans: { _ in }, replayInference: { _ in },
            replayFieldTripProgress: { _ in }, syncPendingDeletions: { _ in }, syncCollections: { _ in }))
        let date = Date().addingTimeInterval(30)
        let unknown = OfflineJobRecord(id: "unknown", kind: .future, nextRunAt: date)
        unknown.kindRaw = "newer-client-kind"
        context.insert(unknown)
        context.insert(OfflineJobRecord(id: "unknown-future", kind: .future, nextRunAt: date))
        context.insert(OfflineJobRecord(id: "observation-publication:prepared", kind: .observationPublicationSync, nextRunAt: date))
        context.insert(OfflineJobRecord(id: "observation-analysis-review:prepared", kind: .observationAnalysisReviewSync, nextRunAt: date))
        context.insert(OfflineJobRecord(id: "observation-insight-chat:prepared", kind: .protectedInsightChatSync, nextRunAt: date))
        context.insert(OfflineJobRecord(id: "reanalysis-erasure:local", kind: .observationReanalysisErasure, nextRunAt: date))
        try context.save()
        #expect(scheduler.nextPersistedWakeDate(using: manager) == nil)
        #expect(try context.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 6)
        context.insert(OfflineJobRecord(id: "library-details:known", kind: .future, nextRunAt: date))
        try context.save()
        #expect(scheduler.nextPersistedWakeDate(using: manager) == date)
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
