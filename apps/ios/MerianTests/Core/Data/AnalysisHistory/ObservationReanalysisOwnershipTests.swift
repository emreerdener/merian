import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager), .timeLimit(.minutes(1)))
struct ObservationReanalysisOwnershipTests {
    func identity() -> OfflineQueueWork.Reanalysis {
        .init(observationID: UUID(), sourceAnalysisID: UUID(), analysisID: UUID(), ownerID: UUID())
    }

    @Test func cancellationRetainsSlotAndDrainRejectsNewWorkUntilUncooperativeTaskExits() async throws {
        let owner = ObservationReanalysisPreparationOwner(), child = identity(), started = AsyncStream<Void>.makeStream()
        defer { started.continuation.finish() }
        var release: CheckedContinuation<Void, Never>?, validator: ObservationReanalysisPreparationOwner.Validator?
        let work = Task {
            try await owner.perform(child) { current in
                validator = current
                await withCheckedContinuation { release = $0; started.continuation.yield() }
                return 1 // Deliberately ignores cancellation; the owner must withhold its result.
            }
        }
        for await _ in started.stream { break }
        #expect(owner.contains(child.analysisID) && validator?() == true)
        await #expect(throws: ObservationReanalysisPreparationOwner.Failure.busy) { try await owner.perform(child) { _ in 2 } }
        owner.cancelAll()
        #expect(owner.contains(child.analysisID) && validator?() == false)
        var drained = 0
        let drainStarted = AsyncStream<Void>.makeStream(); defer { drainStarted.continuation.finish() }
        let first = Task { drainStarted.continuation.yield(); await owner.cancelAndAwaitAll(); drained += 1 }
        let second = Task { drainStarted.continuation.yield(); await owner.cancelAndAwaitAll(); drained += 1 }
        var iterator = drainStarted.stream.makeAsyncIterator(); _ = await iterator.next(); _ = await iterator.next()
        #expect(drained == 0)
        await #expect(throws: ObservationReanalysisPreparationOwner.Failure.draining) { try await owner.perform(identity()) { _ in 3 } }
        try #require(release).resume()
        await first.value; await second.value
        await #expect(throws: CancellationError.self) { try await work.value }
        #expect(drained == 2 && !owner.contains(child.analysisID))
        let successor = try await owner.perform(child) { current in #expect(current()); return 4 }
        #expect(successor == 4 && validator?() == false)
    }

    @Test func callerCancellationDrainsRetainedWorkBeforeReturning() async throws {
        let owner = ObservationReanalysisPreparationOwner(), child = identity(), entered = AsyncStream<Void>.makeStream()
        defer { entered.continuation.finish() }
        var release: CheckedContinuation<Void, Never>?, returned = false
        let caller = Task {
            defer { returned = true }
            return try await owner.perform(child) { _ in
                await withCheckedContinuation { release = $0; entered.continuation.yield() }
                return 1
            }
        }
        for await _ in entered.stream { break }
        caller.cancel()
        await Task.yield()
        #expect(owner.contains(child.analysisID) && !returned)
        try #require(release).resume()
        await #expect(throws: CancellationError.self) { try await caller.value }
        #expect(returned && !owner.contains(child.analysisID))
    }

    @Test(arguments: [false, true])
    func producerReservationProtectsSavedPreparationBeforeFilesAndAuthCancellation(cancel: Bool) async throws {
        let fixture = CaptureReanalysisSessionTests(), seed = try fixture.seed(count: 1)
        let sourcePhoto = try #require(seed.source.photos.first)
        let plan = try ObservationReanalysisPreparationPlan(source: seed.source, choices: [.photo(.original(sourcePhoto))])
        guard case let .photo(mediaID, _) = plan.items[0] else { Issue.record("Missing planned photo"); return }
        let identity = OfflineQueueWork.Reanalysis(observationID: seed.source.observationID, sourceAnalysisID: seed.source.analysisID,
            analysisID: plan.analysisID, ownerID: seed.source.ownerID)
        let draft = try ObservationReanalysisDraft(identity: identity, evidence: [.image(.init(mediaID: mediaID,
            contentType: sourcePhoto.contentType, byteCount: sourcePhoto.byteCount, sha256: sourcePhoto.sha256))])
        let pending = try ObservationReanalysisPreparationIntent(draft: draft, source: seed.source, action: .submit)
        _ = try ObservationReanalysisPersistence.beginPreparation(pending.verified(source: seed.source), container: seed.container, isCurrent: { true })
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let owner = ObservationReanalysisPreparationOwner(), entered = AsyncStream<Void>.makeStream()
        defer { entered.continuation.finish() }
        var release: CheckedContinuation<Void, Never>?, finished = 0
        let account = fixture.fixture.account(finish: { finished += 1 })
        let producer = ObservationReanalysisProducer(files: .init(documents: root), ownership: owner, account: account,
            loadOriginal: { _, _, _ in
                await withCheckedContinuation { release = $0; entered.continuation.yield() }
                return seed.bytes
            })
        let writing = Task { try await producer.stage(plan, container: seed.container, action: .submit, isCurrent: { true }) }
        for await _ in entered.stream { break }
        #expect(owner.contains(identity.analysisID))
        // Separate file-store instances cannot bypass the shared metadata ownership.
        let recovery = ObservationReanalysisPreparationRecovery(files: .init(documents: root), ownership: owner, account: account)
        await #expect(throws: ObservationReanalysisPreparationOwner.Failure.busy) {
            try await recovery.recover(identity, container: seed.container, isCurrent: { true })
        }
        let saved = try ObservationReanalysisAdmissionStore.read(identity, container: seed.container, isCurrent: { true })
        #expect(saved.work.preparation == pending && saved.work.phase == .filesPending && saved.work.attempt == 0)
        #expect(try ObservationReanalysisPreparationIntent.decode(Data(saved.metadata.utf8)) == pending)
        if cancel { owner.cancelAll() }
        try #require(release).resume()
        if cancel {
            await #expect(throws: CancellationError.self) { try await writing.value }
            guard case .pending = try ObservationReanalysisPersistence.preparation(identity, container: seed.container, isCurrent: { true }) else {
                Issue.record("Cancellation changed durable preparation"); return
            }
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        } else {
            let result = try await writing.value
            guard case let .submitted(saved) = result else { Issue.record("Submission was lost"); return }
            #expect(saved.preparation == pending)
            let replay = try await recovery.recover(identity, container: seed.container, isCurrent: { true })
            guard case let .submitted(replayed) = replay else { Issue.record("Recovery changed identity"); return }
            #expect(replayed == saved)
        }
        #expect(!owner.contains(identity.analysisID) && finished == (cancel ? 2 : 3))
    }

    @Test func queueAuthQuiescenceWaitsForPreparationOwner() async throws {
        let manager = OfflineQueueManager.shared, child = identity(), entered = AsyncStream<Void>.makeStream()
        defer { entered.continuation.finish() }
        var release: CheckedContinuation<Void, Never>?, drained = false
        let working = Task {
            try await manager.reanalysisPreparationOwner.perform(child) { _ in
                await withCheckedContinuation { release = $0; entered.continuation.yield() }
                return true
            }
        }
        for await _ in entered.stream { break }
        let draining = Task { await manager.awaitRetainedSyncQuiescenceForAuthTransition(); drained = true }
        await Task.yield()
        #expect(!drained && manager.reanalysisPreparationOwner.contains(child.analysisID))
        try #require(release).resume()
        await draining.value
        await #expect(throws: CancellationError.self) { try await working.value }
        #expect(drained && !manager.reanalysisPreparationOwner.contains(child.analysisID))
    }
}
