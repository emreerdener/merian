import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationVideoResumeStoreTests {
    typealias Store = ObservationVideoResumeStore
    typealias Seed = ObservationVideoDurabilityTests.Seed

    func seed(_ phase: String) async throws -> Seed {
        switch phase {
        case "pending", "ready":
            let fixture = ObservationVideoDurabilityTests(), seed = try await fixture.seed()
            if phase == "pending" {
                _ = try ObservationVideoPreparationStore.begin(seed.proof, container: seed.container, isCurrent: { true })
            } else {
                _ = try await fixture.producer(seed).prepare(seed.preparation, source: seed.source, cohort: seed.cohort,
                    container: seed.container, isCurrent: { true })
            }
            return seed
        case "staged", "unknown":
            let (seed, entry) = try await ObservationVideoReservationLifecycleTests().staged()
            if phase == "unknown" {
                let claim = try ObservationVideoSourceReservationStore.claim(entry, proof: seed.proof, container: seed.container, isCurrent: { true })
                _ = try ObservationVideoSourceReservationStore.hold(claim, proof: seed.proof, container: seed.container, isCurrent: { true })
            }
            return seed
        case "reserved": return try await ObservationVideoUploadStagingTests().reserved().0
        case "upload", "uploadUnknown":
            let (seed, entry) = try await ObservationVideoUploadLifecycleTests().staged()
            if phase == "uploadUnknown" {
                let claim = try ObservationVideoUploadLifecycleStore.claim(entry, proof: seed.proof, container: seed.container, isCurrent: { true })
                _ = try ObservationVideoUploadLifecycleStore.hold(claim, proof: seed.proof, container: seed.container, isCurrent: { true })
            }
            return seed
        case "uploadReady": return try await ObservationVideoExecutionStoreTests().ready().0
        default: return try await ObservationVideoExecutionServiceTests().seed(phase).0
        }
    }

    func metadata(_ seed: Seed, container: ModelContainer? = nil) throws -> String {
        let context = ModelContext(container ?? seed.container)
        let pair = try #require(try ObservationReanalysisPersistence.pair(seed.preparation.identity, context: context))
        return try #require(pair.1.metadataJSON)
    }

    @Test(arguments: ["pending", "ready", "staged", "unknown", "reserved", "upload", "uploadUnknown", "uploadReady", "idle", "running", "held", "running-consumed", "held-consumed"])
    func reopenedExactChildKeepsPhaseAndOriginalBytes(_ phase: String) async throws {
        let seed = try await seed(phase); defer { seed.remove() }
        let before = try metadata(seed)
        let reopened = try ObservationPublicationPersistenceTests().container(url: seed.storeURL, seed: false)
        let saved = try await Store().read(seed.preparation.identity, container: reopened, isCurrent: { true })
        #expect(saved.proof.preparation == seed.preparation && saved.source == seed.source)
        switch saved.state {
        case let .preparation(value): #expect(value == (phase == "pending" ? .pending : .ready))
        case let .reservation(value):
            #expect(value.work.phase == (phase == "staged" ? .staged : phase == "unknown" ? .unknown : .observed))
        case let .upload(value):
            #expect(value.work.receipt?.state == (phase == "uploadReady" ? .ready : nil))
            #expect(value.work.attempts.last?.phase == (phase == "uploadUnknown" ? .unknown : phase == "uploadReady" ? .observed : nil))
        case let .execution(value):
            #expect(value.work.phase == (phase == "idle" ? .idle : phase.contains("held") ? .held : .running))
            #expect(value.work.consumed == phase.contains("consumed"))
        }
        try Store.validate(saved, container: reopened, isCurrent: { true })
        let expected: [String: ObservationVideoSavedStatus.Phase] = [
            "pending": .filesPending, "ready": .prepared, "staged": .reservationStaged,
            "unknown": .reservationUnknown, "reserved": .reserved, "upload": .uploadPending,
            "uploadUnknown": .uploadUnknown, "uploadReady": .uploadReady, "idle": .executionIdle,
            "running": .executionRunning, "held": .executionHeld,
            "running-consumed": .outcomeRecovery, "held-consumed": .outcomeRecovery
        ]
        let page = try await ObservationVideoSavedStatus().page(ownerID: seed.source.ownerID,
            observationID: seed.source.observationID, container: reopened, isCurrent: { true })
        #expect(page.items == [.init(identity: seed.preparation.identity, phase: try #require(expected[phase]))])
        #expect(page.next == nil && page.omittedCount == 0)
        #expect(try metadata(seed, container: reopened) == before)
    }

    @Test(arguments: ["phase", "account", "erasure", "metadata", "parent"])
    func changeAcrossVerificationCannotReturnStaleState(_ change: String) async throws {
        let seed = try await seed("staged"); defer { seed.remove() }
        var current = true
        var store = Store()
        store.verify = { data, identity, source in
            let decoded = try Store.decode(data, identity: identity, source: source)
            if change == "account" { current = false }
            else if change == "phase" {
                let prior = try ObservationVideoSourceReservationStore.read(proof: seed.proof, container: seed.container, isCurrent: { true })
                _ = try ObservationVideoSourceReservationStore.claim(prior, proof: seed.proof, container: seed.container, isCurrent: { true })
            } else {
                let context = ModelContext(seed.container)
                if change == "erasure" {
                    try ObservationReanalysisErasureReceipt(parentID: identity.observationID, childID: identity.analysisID).record(in: context)
                } else if change == "metadata" {
                    let pair = try #require(try ObservationReanalysisPersistence.pair(identity, context: context))
                    pair.1.metadataJSON = "{}"
                } else {
                    let parent = try ObservationHistorySyncService.enrolledScan(identity.observationID.uuidString, context: context)
                    parent.analysisOwnerAccountID = UUID().uuidString.lowercased()
                }
                try context.save()
            }
            return decoded
        }
        await #expect(throws: (any Error).self) {
            try await store.read(seed.preparation.identity, container: seed.container, isCurrent: { current })
        }
    }

    @Test func exactSyncedResultRemainsRecoverableWithoutAClaim() async throws {
        let seed = try await seed("held-consumed"); defer { seed.remove() }
        let context = ModelContext(seed.container), before = try metadata(seed)
        let parent = try ObservationHistorySyncService.enrolledScan(seed.source.observationID.uuidString, context: context)
        let bytes = try ObservationVideoCompletionTests().result(seed.preparation.request)
        let result = try ObservationReanalysisResult.decode(bytes, matching: seed.preparation.request)
        _ = try ObservationHistorySyncService.insert([result], into: parent, ownerID: seed.source.ownerID, context: context)
        try context.save()
        let saved = try await Store().read(seed.preparation.identity, container: seed.container, isCurrent: { true })
        guard case let .execution(snapshot) = saved.state else { Issue.record("Expected consumed execution"); return }
        #expect(snapshot.work.consumed && snapshot.work.phase == .held)
        #expect(try metadata(seed) == before)
        #expect(try ModelContext(seed.container).fetch(FetchDescriptor<LocalAnalysisRecord>()).count == 2)
    }

    @Test func cancellationRetainsPreparationSlotAndAccountUntilActualExit() async throws {
        let seed = try await seed("staged"); defer { seed.remove() }
        let ownership = ObservationReanalysisPreparationOwner(), entered = AsyncStream<Void>.makeStream()
        defer { entered.continuation.finish() }
        var release: CheckedContinuation<Void, Never>?, finishes = 0, drained = false
        let account = ObservationReanalysisProducerTests().account(finish: { finishes += 1 })
        var reader = ObservationVideoResumeReader(ownership: ownership, account: account)
        reader.store.verify = { data, identity, source in
            let result = try Store.decode(data, identity: identity, source: source)
            await withCheckedContinuation { release = $0; entered.continuation.yield(()) }
            return result
        }
        let frozen = reader
        let task = Task { try await frozen.read(seed.preparation.identity, container: seed.container, isCurrent: { true }) }
        var iterator = entered.stream.makeAsyncIterator(); _ = await iterator.next()
        task.cancel()
        let drain = Task { entered.continuation.yield(()); await ownership.cancelAndAwaitAll(); drained = true }
        _ = await iterator.next()
        #expect(ownership.contains(seed.preparation.identity.analysisID) && finishes == 0 && !drained)
        try #require(release).resume()
        await drain.value
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(finishes == 1 && drained && !ownership.contains(seed.preparation.identity.analysisID))
    }
}
