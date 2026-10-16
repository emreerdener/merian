import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationVideoUploadLifecycleTests {
    typealias Store = ObservationVideoUploadLifecycleStore
    typealias Work = ObservationVideoUploadLifecycle
    enum Simulated: Error { case save }
    func staged(audio: Bool = true) async throws -> (ObservationVideoDurabilityTests.Seed, Store.Snapshot) {
        let (seed, reserved) = try await ObservationVideoUploadStagingTests().reserved(audio: audio)
        do {
            _ = try ObservationVideoUploadStore.stage(reserved, proof: seed.proof, container: seed.container, isCurrent: { true })
            return (seed, try Store.read(proof: seed.proof, container: seed.container, isCurrent: { true }))
        } catch { seed.remove(); throw error }
    }
    func receipt(_ claim: Store.Claim, all: Bool = false) throws -> ObservationVideoEvidenceReceipt {
        try receipt(claim.snapshot, all: all)
    }
    func receipt(_ snapshot: Store.Snapshot, all: Bool = false) throws -> ObservationVideoEvidenceReceipt {
        let work = snapshot.work, request = work.staged.request
        var row = try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        var items = try #require(row["items"] as? [[String: Any]])
        let target = try #require(work.attempts.last).mediaID
        for index in items.indices {
            let media = request.inventory.items[index].artifact.mediaID
            let previous = work.receipt?.items[index]
            items[index]["object_id"] = (previous?.objectID ?? UUID()).uuidString.lowercased()
            items[index]["ready_at"] = previous?.readyAt.map { $0 as Any } ?? ((all || media == target) ? "2026-10-10T01:00:00.000Z" as Any : NSNull())
        }
        row["items"] = items; row["owner_id"] = work.staged.reservation.preparation.identity.ownerID.uuidString.lowercased()
        row["expires_at"] = "2099-10-11T01:00:00.000Z"
        row["state"] = items.allSatisfy { $0["ready_at"] is String } ? "ready" : "allocated"
        return try .init(data: JSONSerialization.data(withJSONObject: row, options: [.prettyPrinted]), request: request,
            ownerID: work.staged.reservation.preparation.identity.ownerID, previous: work.receipt)
    }
    @Test(arguments: [false, true])
    func orderedClaimsRetainEveryReceiptAndReopen(audio: Bool) async throws {
        let (seed, original) = try await staged(audio: audio); defer { seed.remove() }
        var current = original
        var receipts: [Data] = []
        for item in original.work.staged.request.inventory.items {
            #expect(current.work.nextMediaID == item.artifact.mediaID)
            let claim = try Store.claim(current, proof: seed.proof, container: seed.container, isCurrent: { true })
            try Store.validate(claim, proof: seed.proof, container: seed.container, isCurrent: { true })
            #expect(throws: (any Error).self) { try Store.claim(current, proof: seed.proof, container: seed.container, isCurrent: { true }) }
            let reply = try receipt(claim); receipts.append(reply.data)
            current = try Store.settle(claim, receipt: reply, proof: seed.proof, container: seed.container, isCurrent: { true })
            #expect(try Store.settle(claim, receipt: reply, proof: seed.proof, container: seed.container, isCurrent: { true }, save: { _ in Issue.record("Replay saved") }) == current)
            #expect(throws: (any Error).self) { try Store.validate(claim, proof: seed.proof, container: seed.container, isCurrent: { true }) }
        }
        #expect(current.work.receipt?.state == .ready && current.work.nextMediaID == nil)
        #expect(current.work.stagedData == Data(original.metadata.utf8))
        #expect(current.work.attempts.compactMap { $0.receipt?.data } == receipts)
        let reopened = try ObservationPublicationPersistenceTests().container(url: seed.storeURL, seed: false)
        #expect(try Store.read(proof: seed.proof, container: reopened, isCurrent: { true }).work == current.work)
        #expect(throws: (any Error).self) { try Store.claim(current, proof: seed.proof, container: seed.container, isCurrent: { true }) }
        #expect(throws: (any Error).self) { try ObservationVideoUploadStore.read(proof: seed.proof, container: seed.container, isCurrent: { true }) }
        let context = ModelContext(reopened)
        let row = try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        #expect(row.queueAttemptCount == 0 && !row.permitsOrdinaryInference && job.attemptCount == 0)
    }
    @Test func unknownBlocksClaimsButKnownReceiptCanSettleAfterCancellation() async throws {
        let (seed, staged) = try await staged(); defer { seed.remove() }
        let claim = try Store.claim(staged, proof: seed.proof, container: seed.container, isCurrent: { true })
        let unknown = try Store.hold(claim, proof: seed.proof, container: seed.container, isCurrent: { true })
        #expect(unknown.work.nextMediaID == nil)
        #expect(throws: (any Error).self) { try Store.claim(unknown, proof: seed.proof, container: seed.container, isCurrent: { true }) }
        #expect(throws: (any Error).self) { try Store.validate(claim, proof: seed.proof, container: seed.container, isCurrent: { true }) }
        let reply = try receipt(claim, all: true)
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: (any Error).self) { try Store.read(proof: seed.proof, container: seed.container, isCurrent: { true }) }
            #expect(throws: (any Error).self) { try Store.hold(claim, proof: seed.proof, container: seed.container, isCurrent: { true }) }
            return try Store.settle(claim, receipt: reply, proof: seed.proof, container: seed.container, isCurrent: { true })
        }
        let finished = try await task.value
        #expect(finished.work.receipt?.data == reply.data && finished.work.nextMediaID == nil)
        #expect(throws: (any Error).self) { try Store.hold(claim, proof: seed.proof, container: seed.container, isCurrent: { true }) }
    }
    @Test(arguments: [false, true])
    func uncertainClaimAndSettlementSavesRetainOriginalAttempt(commits: Bool) async throws {
        let (seed, original) = try await staged(); defer { seed.remove() }
        let id = UUID()
        #expect(throws: Simulated.save) { try Store.claim(original, proof: seed.proof, container: seed.container, isCurrent: { true }, attemptID: id,
            save: { if commits { try $0.save() }; throw Simulated.save }) }
        let current = try Store.read(proof: seed.proof, container: seed.container, isCurrent: { true })
        if commits {
            #expect(current.work.attempts.last?.id == id && current.work.nextMediaID == nil)
            #expect(throws: (any Error).self) { try Store.claim(current, proof: seed.proof, container: seed.container, isCurrent: { true }) }
            return
        }
        #expect(current == original)
        let claim = try Store.claim(current, proof: seed.proof, container: seed.container, isCurrent: { true }, attemptID: id)
        let reply = try receipt(claim)
        for committed in [false, true] {
            #expect(throws: Simulated.save) { try Store.settle(claim, receipt: reply, proof: seed.proof, container: seed.container, isCurrent: { true },
                save: { if committed { try $0.save() }; throw Simulated.save }) }
            let reopened = try ObservationPublicationPersistenceTests().container(url: seed.storeURL, seed: false)
            let saved = try Store.read(proof: seed.proof, container: reopened, isCurrent: { true })
            #expect(saved.work.attempts.last?.id == id)
            #expect(saved.work.attempts.last?.phase == (committed ? .observed : .running))
        }
        _ = try Store.settle(claim, receipt: reply, proof: seed.proof, container: seed.container, isCurrent: { true }, save: { _ in Issue.record("Replay saved") })
    }
    @Test(arguments: ["account", "erasure", "job", "attempt", "source", "container", "metadata"])
    func knownSettlementStillRequiresDurableScope(_ boundary: String) async throws {
        let (seed, original) = try await staged(); defer { seed.remove() }
        let claim = try Store.claim(original, proof: seed.proof, container: seed.container, isCurrent: { true })
        let reply = try receipt(claim)
        let context = ModelContext(seed.container)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        if boundary == "erasure" { try ObservationReanalysisErasureReceipt(parentID: seed.source.observationID, childID: seed.preparation.identity.analysisID).record(in: context) }
        if boundary == "job" { context.delete(job) }
        if boundary == "attempt" { job.attemptCount = 1 }
        if boundary == "source" { context.delete(try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)) }
        if boundary == "metadata" { job.metadataJSON = claim.snapshot.metadata + " " }
        try context.save()
        let container = boundary == "container" ? try ObservationPublicationPersistenceTests().container(url: seed.storeURL, seed: false) : seed.container
        #expect(throws: (any Error).self) { try Store.settle(claim, receipt: reply, proof: seed.proof, container: container, isCurrent: { boundary != "account" }) }
    }
    @Test func expiredProgressCannotClaimButExactReceiptReplaySurvives() async throws {
        let (seed, original) = try await staged(); defer { seed.remove() }
        let claim = try Store.claim(original, proof: seed.proof, container: seed.container, isCurrent: { true })
        let reply = try receipt(claim)
        let observed = try Store.settle(claim, receipt: reply, proof: seed.proof, container: seed.container, isCurrent: { true })
        #expect(throws: (any Error).self) { try Store.claim(observed, proof: seed.proof, container: seed.container, isCurrent: { true }, now: .distantFuture) }
        #expect(try Store.settle(claim, receipt: reply, proof: seed.proof, container: seed.container, isCurrent: { true }, save: { _ in Issue.record("Replay saved") }) == observed)
    }
    @Test func codecRejectsReceiptRegressionAndUnsupportedTransitions() async throws {
        let (seed, original) = try await staged(); defer { seed.remove() }
        let claim = try Store.claim(original, proof: seed.proof, container: seed.container, isCurrent: { true })
        let reply = try receipt(claim)
        let observed = try Store.settle(claim, receipt: reply, proof: seed.proof, container: seed.container, isCurrent: { true })
        let second = try Store.claim(observed, proof: seed.proof, container: seed.container, isCurrent: { true })
        let next = try receipt(second)
        var row = try #require(JSONSerialization.jsonObject(with: next.data) as? [String: Any])
        var items = try #require(row["items"] as? [[String: Any]])
        for field in ["ready_at", "object_id", "expires_at"] {
            var changed = row, changedItems = items
            if field == "expires_at" { changed[field] = "2099-10-12T01:00:00.000Z" }
            else { changedItems[0][field] = field == "object_id" ? UUID().uuidString.lowercased() as Any : NSNull(); changed["items"] = changedItems }
            let rebound = try ObservationVideoEvidenceReceipt(data: JSONSerialization.data(withJSONObject: changed), request: next.request, ownerID: next.ownerID)
            #expect(throws: (any Error).self) { try Store.settle(second, receipt: rebound, proof: seed.proof, container: seed.container, isCurrent: { true }) }
        }
        items[1]["ready_at"] = NSNull(); row["items"] = items
        let unfinished = try ObservationVideoEvidenceReceipt(data: JSONSerialization.data(withJSONObject: row), request: next.request, ownerID: next.ownerID)
        #expect(throws: (any Error).self) { try Store.settle(second, receipt: unfinished, proof: seed.proof, container: seed.container, isCurrent: { true }) }
        let last = try #require(claim.snapshot.work.attempts.last)
        #expect(throws: (any Error).self) { try Work(stagedData: original.work.stagedData, attempts: [last, last]) }
        var encoded = try #require(JSONSerialization.jsonObject(with: Data(second.snapshot.metadata.utf8)) as? [String: Any])
        for key in ["version", "kind", "extra", "attempts", "staged_base64"] {
            var changed = encoded
            changed[key] = key == "version" ? 3 as Any : "invalid"
            #expect(throws: (any Error).self) { try Work.decode(JSONSerialization.data(withJSONObject: changed)) }
        }
        encoded["attempts"] = []
        #expect(throws: (any Error).self) { try Work.decode(JSONSerialization.data(withJSONObject: encoded)) }
        #expect(throws: (any Error).self) { try Work.decode(Data(repeating: 32, count: Work.maximumBytes + 1)) }
    }
}
