import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager), .timeLimit(.minutes(1)))
struct HistoryEnrollmentOwnerTests {
    let fixture = ObservationHistoryEnrollmentTests()
    var observation: UUID { UUID(uuidString: fixture.support.support.observation)! }
    var account: UUID { fixture.support.support.owner }

    @Test func changedTapCannotJoinAnOlderCorrectionEvenWhenItLaterReturnsToOriginal() async throws {
        let owner = ObservationHistoryEnrollmentOwner(), container = try fixture.container(), gate = Pause()
        defer { gate.release(); owner.cancelAll() }
        let baseline = try ObservationHistoryEnrollmentService.baseline(observation: observation, container: container)
        var cloud = fixture.service().cloud, calls = 0
        cloud.enroll = { _ in calls += 1; await gate.wait(); return try fixture.receipt() }
        let first = Task { try await owner.enroll(observation: observation, owner: account, generation: 1,
            container: container, cloud: cloud, expectedBaseline: baseline, isCurrent: { true }) }
        await gate.entered()
        let context = ModelContext(container)
        let scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let original = scan.commonName
        scan.commonName = "Changed synthetic correction"; try context.save()
        let changed = try ObservationHistoryEnrollmentService.baseline(observation: observation, container: container)
        #expect(changed != baseline)
        scan.commonName = original; try context.save()
        await #expect(throws: ObservationHistoryEnrollmentService.AdmissionError.localStateChanged) {
            try await owner.enroll(observation: observation, owner: account, generation: 1,
                container: container, cloud: cloud, expectedBaseline: changed, isCurrent: { true })
        }
        #expect(calls == 1)
        gate.release()
        let result = try await first.value
        #expect(result.uuidString.lowercased() == fixture.support.analysisID)
    }

    @Test func staleTapTicketFailsBeforeCreatingIntentOrSendingEnrollment() async throws {
        let container = try fixture.container()
        let baseline = try ObservationHistoryEnrollmentService.baseline(observation: observation, container: container)
        let context = ModelContext(container)
        #expect(try context.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
        let scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        scan.commonName = "Changed synthetic correction"; try context.save()
        var cloud = fixture.service().cloud
        cloud.enroll = { _ in Issue.record("Stale tap reached the server"); throw MerianError.invalidResponse }
        await #expect(throws: ObservationHistoryEnrollmentService.AdmissionError.localStateChanged) {
            try await ObservationHistoryEnrollmentOwner().enroll(observation: observation, owner: account, generation: 1,
                container: container, cloud: cloud, expectedBaseline: baseline, isCurrent: { true })
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }

    @Test func duplicateRequestsJoinExactScopeAndCannotCrossOwnerGenerationOrContainer() async throws {
        let owner = ObservationHistoryEnrollmentOwner(), container = try fixture.container(), gate = Pause()
        defer { gate.release(); owner.cancelAll() }
        var cloud = fixture.service().cloud, calls = 0
        cloud.enroll = { _ in calls += 1; await gate.wait(); return try fixture.receipt() }
        let first = Task { try await owner.enroll(observation: observation, owner: account, generation: 1,
            container: container, cloud: cloud, isCurrent: { true }) }
        await gate.entered()
        let joined = AsyncStream<Void>.makeStream(); defer { joined.continuation.finish() }
        let second = Task { try await owner.enroll(observation: observation, owner: account, generation: 1,
            container: container, cloud: cloud, isCurrent: { joined.continuation.yield(); return true }) }
        for await _ in joined.stream { break }
        for mismatch in 0..<3 {
            let other = try mismatch == 2 ? fixture.container() : container
            await #expect(throws: ObservationHistoryEnrollmentOwner.Failure.busy) {
                try await owner.enroll(observation: observation, owner: mismatch == 0 ? UUID() : account,
                    generation: mismatch == 1 ? 3 : 1, container: other, cloud: cloud, isCurrent: { true })
            }
        }
        owner.cancel(observation, in: try fixture.container()) // A different container cannot cancel this admission.
        #expect(calls == 1 && owner.contains(observation))
        first.cancel() // Closing one waiter must not cancel the shared admission for the other.
        gate.release()
        await #expect(throws: CancellationError.self) { try await first.value }
        let result = try await second.value
        #expect(result.uuidString.lowercased() == fixture.support.analysisID)
        #expect(calls == 1 && !owner.contains(observation))
    }

    @Test func lostResponseRetainsExactIntentForSameOwnerExplicitRetry() async throws {
        let owner = ObservationHistoryEnrollmentOwner(), container = try fixture.container()
        var cloud = fixture.service().cloud, calls = 0, savedIntent: String?
        cloud.begin = { .init(id: UUID(), session: .init(userID: $0, isAnonymous: false)) }
        cloud.enroll = { _ in
            calls += 1
            let job = try #require(try ModelContext(container).fetchOfflineJob(id: ObservationHistoryEnrollmentIntent.jobID(observation.uuidString)))
            if calls == 1 { savedIntent = job.metadataJSON; throw URLError(.networkConnectionLost) }
            #expect(job.metadataJSON == savedIntent)
            return try fixture.receipt()
        }
        await #expect(throws: URLError.self) {
            try await owner.enroll(observation: observation, owner: account, generation: 1, container: container, cloud: cloud, isCurrent: { true })
        }
        #expect(!owner.contains(observation) && calls == 1 && savedIntent != nil)
        await #expect(throws: ObservationHistoryEnrollmentIntent.IntegrityError.self) {
            try await owner.enroll(observation: observation, owner: UUID(), generation: 3, container: container, cloud: cloud, isCurrent: { true })
        }
        #expect(calls == 1)
        _ = try await owner.enroll(observation: observation, owner: account, generation: 3, container: container, cloud: cloud, isCurrent: { true })
        #expect(calls == 2 && !owner.contains(observation))
        #expect(!(try ObservationHistoryEnrollmentIntent.holds(observation.uuidString, context: ModelContext(container))))
    }

    @Test(arguments: ["owner", "generation", "container"], ["enroll", "state"])
    func staleEnvironmentCannotAcknowledgeOrReturnResult(_ field: String, _ boundary: String) async throws {
        let owner = ObservationHistoryEnrollmentOwner(), container = try fixture.container()
        var activeOwner = account, generation: UInt64 = 1, activeContainer = container
        let change = {
            switch field {
            case "owner": activeOwner = UUID()
            case "generation": generation += 2
            default: activeContainer = try fixture.container()
            }
        }
        let cloud = fixture.service(duringEnroll: { if boundary == "enroll" { try change() } },
                                    duringRead: { if boundary == "state" { try change() } }).cloud
        await #expect(throws: ObservationHistoryError.accountChanged) {
            try await owner.enroll(observation: observation, owner: account, generation: 1, container: container, cloud: cloud,
                isCurrent: { activeOwner == account && generation == 1 && activeContainer === container })
        }
        try fixture.expectUnenrolled(container)
        #expect(try ObservationHistoryEnrollmentIntent.holds(observation.uuidString, context: ModelContext(container)))
        #expect(!owner.contains(observation))
    }

    @Test func authDrainRetainsCancelledSlotUntilTransportActuallyExits() async throws {
        let manager = OfflineQueueManager.shared, owner = manager.historyEnrollmentOwner
        let container = try fixture.container(), gate = Pause()
        defer { gate.release(); owner.cancelAll() }
        var cloud = fixture.service().cloud, finishedLeases = 0
        cloud.finish = { _ in finishedLeases += 1 }
        cloud.enroll = { _ in await gate.wait(); return try fixture.receipt() }
        let first = Task { try await owner.enroll(observation: observation, owner: account, generation: 1,
            container: container, cloud: cloud, isCurrent: { true }) }
        await gate.entered()
        let started = AsyncStream<Void>.makeStream(); defer { started.continuation.finish() }
        var drained = 0
        let drain = Task { started.continuation.yield(); await manager.awaitRetainedSyncQuiescenceForAuthTransition(); drained += 1 }
        for await _ in started.stream { break }
        let secondDrain = Task { started.continuation.yield(); await owner.cancelAndAwaitAll(); drained += 1 }
        for await _ in started.stream { break }
        #expect(drained == 0 && finishedLeases == 0 && owner.contains(observation))
        await #expect(throws: ObservationHistoryEnrollmentOwner.Failure.draining) {
            try await owner.enroll(observation: UUID(), owner: account, generation: 1, container: container, cloud: cloud, isCurrent: { true })
        }
        gate.release()
        await drain.value; await secondDrain.value
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(drained == 2 && finishedLeases == 1 && !owner.contains(observation))
        try fixture.expectUnenrolled(container)
        #expect(try ObservationHistoryEnrollmentIntent.holds(observation.uuidString, context: ModelContext(container)))
        _ = try await owner.enroll(observation: observation, owner: account, generation: 3,
            container: container, cloud: fixture.service().cloud, isCurrent: { true })
    }

    @Test func capacityAndForceCancellationRetainSlotsUntilTransportExits() async throws {
        let owner = ObservationHistoryEnrollmentOwner(), gate = Pause()
        defer { gate.release(); owner.cancelAll() }
        let cancelled = AsyncStream<Void>.makeStream(); defer { cancelled.continuation.finish() }
        var tasks: [Task<UUID, Error>] = []
        var observations: [UUID] = []
        for _ in 0..<ObservationHistoryEnrollmentOwner.maximumActiveObservations {
            let container = try fixture.container(), id = UUID()
            observations.append(id)
            try fixture.support.update(container) { scan, _ in scan.id = id.uuidString.lowercased() }
            var cloud = fixture.service().cloud
            cloud.enroll = { _ in
                await withTaskCancellationHandler { await gate.wait(); return Data() }
                    onCancel: { cancelled.continuation.yield() }
            }
            tasks.append(Task { try await owner.enroll(observation: id, owner: account, generation: 1,
                container: container, cloud: cloud, isCurrent: { true }) })
            await gate.entered()
        }
        await #expect(throws: ObservationHistoryEnrollmentOwner.Failure.capacity) {
            try await owner.enroll(observation: observation, owner: account, generation: 1,
                container: fixture.container(), cloud: fixture.service().cloud, isCurrent: { true })
        }
        tasks.forEach { $0.cancel() }
        owner.cancelAll()
        var cancellations = cancelled.stream.makeAsyncIterator()
        for _ in tasks { _ = await cancellations.next() }
        #expect(observations.allSatisfy { owner.contains($0) })
        gate.release()
        for task in tasks { await #expect(throws: CancellationError.self) { try await task.value } }
    }

    @Test(arguments: [false, true])
    func onlyCommittedDeletionCancelsMatchingEnrollment(_ deleting: Bool) async throws {
        let manager = OfflineQueueManager.shared, owner = manager.historyEnrollmentOwner
        let container = try fixture.container(), gate = Pause(), online = manager.isOnline
        manager.modelContext = ModelContext(container); manager.isOnline = false
        defer { gate.release(); owner.cancelAll(); manager.isOnline = online }
        var cloud = fixture.service().cloud
        cloud.enroll = { _ in await gate.wait(); return try fixture.receipt() }
        let task = Task { try await owner.enroll(observation: observation, owner: account, generation: 1,
            container: container, cloud: cloud, isCurrent: { true }) }
        await gate.entered()
        let context = ModelContext(container), scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let cleanup = ScanRepository.shared.eradicateScan(record: scan, modelContext: context, allowsMutation: { deleting })
        #expect(owner.contains(observation)) // Cancellation never frees the slot before transport exits.
        gate.release()
        if deleting {
            await #expect(throws: CancellationError.self) { try await task.value }
            let fence = try #require(try ModelContext(container).fetchOfflineJob(id: ObservationHistoryEnrollmentIntent.jobID(observation.uuidString)))
            #expect(fence.status == .cancelled && fence.metadataJSON == nil)
            #expect(try ModelContext(container).fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 0)
        } else { _ = try await task.value }
        await cleanup?.value
        #expect(!owner.contains(observation))
    }

    private final class Pause {
        private let stream = AsyncStream<Void>.makeStream()
        private var pending: [CheckedContinuation<Void, Never>] = []
        deinit { stream.continuation.finish() }
        func wait() async { await withCheckedContinuation { pending.append($0); stream.continuation.yield() } }
        func entered() async { for await _ in stream.stream { break } }
        func release() { let saved = pending; pending.removeAll(); saved.forEach { $0.resume() } }
    }
}
