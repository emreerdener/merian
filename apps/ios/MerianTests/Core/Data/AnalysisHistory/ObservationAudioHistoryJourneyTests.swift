import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationAudioHistoryJourneyTests {
    typealias Review = ObservationAnalysisReviewPersistence
    let history = ObservationHistoryStateSyncTests()
    var owner: UUID { ObservationPublicationPersistenceTests().owner }
    var observation: UUID { UUID(uuidString: history.support.observation)! }
    var original: UUID { UUID(uuidString: history.analysisID)! }

    struct Saved {
        let source: ObservationReanalysisSource
        let preparation: ObservationAudioPreparation
        let result: Data
        let request: Data
        let rejection: ObservationAnalysisReviewIntent
    }

    func state(snapshot: Data, revision: Int, selected: UUID, review: Int = 0,
               rejection: ObservationAnalysisReviewIntent? = nil, cleared: Bool = false) throws -> Data {
        var value = try ObservationHistoryStateTests().fixture()
        value["owner_id"] = owner.uuidString.lowercased()
        value["state_revision"] = revision; value["selected_analysis_id"] = selected.uuidString.lowercased()
        var item = try #require(value["analysis"] as? [String: Any])
        item["snapshot"] = try #require(String(bytes: snapshot, encoding: .utf8)); item["review_revision"] = review
        if let rejection {
            var authority = try #require(item["review_snapshot"] as? [String: Any])
            authority["ai_identification_review"] = ["version": 1, "revision": cleared ? 2 : 1, "state": cleared ? "clear" : "ai_rejected",
                "origin_scan_id": observation.uuidString.lowercased(),
                "origin_identification": NSNull(),
                "operation_id": rejection.request.operationID.uuidString.lowercased(),
                "operation_digest": String(repeating: cleared ? "b" : "a", count: 32), "community": NSNull()] as [String: Any]
            authority["confirmed_species_identity_revision"] = cleared ? 2 : 1
            item["review_snapshot"] = authority
        }
        value["analysis"] = item
        return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    func client() -> ObservationHistoryCloudClient {
        .init(begin: { expected in
            #expect(expected == owner)
            return AccountBoundWorkLease(id: UUID(), session: .init(userID: owner, isAnonymous: false))
        }, isCurrent: { _ in true }, finish: { _ in }, fetch: { _ in throw ObservationHistoryError.unavailable })
    }

    func ticket(_ id: UUID, container: ModelContainer) throws -> ObservationAnalysisReviewTicket {
        let context = ModelContext(container)
        let scan = try ObservationHistorySyncService.enrolledScan(observation.uuidString, context: context)
        let entry = try ObservationHistoryListingService.entry(id, scan: scan, context: context)
        return try .init(entry: entry, context: .init(owner: owner,
            selected: #require(UUID(uuidString: scan.selectedAnalysisID!)), revision: #require(scan.observationStateRevision),
            pendingOperation: nil, undoOperation: nil), observationID: observation)
    }

    func settle(_ intent: ObservationAnalysisReviewIntent, data: Data,
                container: ModelContainer) async throws -> ObservationAnalysisReviewIntent {
        let now = Date(), fixtures = ObservationAnalysisReviewPersistenceTests()
        let claim = try #require(try Review.claim(intent, at: now, container: container, isCurrent: { true }))
        let received = try Review.acknowledge(fixtures.receipt(intent.request), claim: claim, at: now,
            container: container, isCurrent: { true })
        let receiptClaim = try #require(try Review.claim(received, at: now, container: container, isCurrent: { true }))
        var cloud = client()
        cloud.fetchState = { request in
            #expect(request.analysis_id == intent.request.analysisID.uuidString.lowercased())
            return data
        }
        return try await ObservationAnalysisReviewReconciliation(cloud: cloud).reconcile(receiptClaim,
            container: container, isCurrent: { true })
    }

    // Returning only values releases the first container before the test opens the same disk store.
    func interrupted(_ url: URL, root: URL) async throws -> Saved {
        let seed = try ObservationReanalysisSourceTests().seed(version: 3, url: url)
        try history.update(seed.container) { scan, _ in
            scan.speciesId = ""; scan.isBiological = true; scan.confidenceScore = 0.75
            scan.aiReasoning = "Synthetic saved identification."; scan.inferenceTier = "flash"
            scan.candidatesData = Data("{}".utf8)
            scan.confirmedSpeciesIdentityData = try ConfirmedSpeciesReview(revision: 0, identity: nil,
                override: nil, confirmed: false, speciesID: nil, state: .unreviewed).storedData()
        }
        var initialCloud = client()
        initialCloud.fetchState = { _ in try state(snapshot: seed.result.bytes, revision: 10, selected: original) }
        _ = try await ObservationHistoryStateSyncService(cloud: initialCloud)
            .syncSelected(observationID: observation.uuidString, container: seed.container)
        let displayed = try ticket(original, container: seed.container)
        let pending = try ObservationAnalysisReviewAdmission.stage(displayed.request(.reject, operationID: UUID()),
            ticket: displayed, container: seed.container, isCurrent: { true })
        let rejected = try await settle(pending, data: state(snapshot: seed.result.bytes, revision: 11,
            selected: original, review: 1, rejection: pending), container: seed.container)
        #expect(rejected.isComplete)
        let source = try ObservationReanalysisSource.captureForAudio(observationID: observation, ownerID: owner, container: seed.container)
        let wav = makeInferenceTestPCM16WAVData(sampleRate: 44_100, frameCount: 16, sampleAt: { Int16($0) })
        let child = UUID(), media = UUID()
        let upload = try ObservationAudioEvidenceUpload(observationID: observation, analysisID: child, mediaID: media, bytes: wav).prepare()
        let preparation = try ObservationAudioPreparation(identity: .init(observationID: observation,
            sourceAnalysisID: original, analysisID: child, ownerID: owner), evidence: [.audio(upload.reference)], source: source, action: .submit)
        let audio = ObservationAudioPreparationTests.Seed(container: seed.container, source: source,
            preparation: preparation, bytes: wav, root: root)
        _ = try await ObservationAudioPreparationTests().producer(audio).prepare(preparation, source: source,
            bytes: wav, container: seed.container, isCurrent: { true })
        let permit = try ObservationAudioCompletionTests().consumed(audio)
        try ObservationAudioExecutionStore.hold(permit.claim, proof: audio.proof, container: seed.container, isCurrent: { true })
        return try Saved(source: source, preparation: preparation, result: ObservationAudioCompletionTests().result(audio),
            request: permit.snapshot.work.intent.request.body, rejection: rejected)
    }

    func select(_ target: UUID, data: Data, previous: UUID, container: ModelContainer,
                undo: UUID? = nil) async throws -> UUID {
        var cloud = client()
        cloud.select = { request in
            #expect(request.analysis_id == target.uuidString.lowercased())
            return try JSONEncoder().encode(ObservationHistorySelectionReceipt(schema_version: 1,
                operation_id: request.operation_id, observation_id: request.observation_id,
                previous_analysis_id: previous.uuidString.lowercased(), selected_analysis_id: request.analysis_id,
                observation_revision: request.expected_observation_revision + 1, review_revision: request.expected_review_revision))
        }
        cloud.fetchState = { request in #expect(request.analysis_id == nil); return data }
        let service = ObservationHistorySelectionService(cloud: cloud)
        let request: ObservationHistorySelectionRequest
        if let undo {
            request = try service.prepareUndo(observationID: observation.uuidString, operationID: undo, ownerID: owner, container: container)
        } else {
            request = try service.prepare(observationID: observation.uuidString, analysisID: target, ownerID: owner, container: container)
        }
        #expect(try ticket(previous, container: container).selectedAnalysisID == previous)
        _ = try await service.sendPending(observationID: observation.uuidString, container: container)
        return try #require(UUID(uuidString: request.operation_id))
    }

    @Test func rejectedOriginalAudioRecoverySelectionAndUndoRemainIndependent() async throws {
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("journey.store")
        let saved = try await interrupted(url, root: root)
        let container = try ObservationReanalysisSourceTests().fixture.container(url: url, seed: false)
        let seed = ObservationAudioPreparationTests.Seed(container: container, source: saved.source,
            preparation: saved.preparation, bytes: Data(), root: root)
        let resumed = try await ObservationAudioResumeStore.read(saved.preparation.identity, container: container, isCurrent: { true })
        guard case let .bound(work) = resumed.state else { Issue.record("Lost original request"); return }
        #expect(work.work.intent.request.body == saved.request && work.work.consumedAttempt == 1)
        let boundary = try ObservationAudioExecutionServiceTests.Boundary(seed); boundary.bytes = saved.result
        let proof = try seed.proof
        try await ObservationAudioInterruptionTests().owned(work, seed: seed) { scope, _ in
            #expect(await boundary.service.run(work, proof: proof, container: container, scope: scope, cleanup: boundary.cleanup) == .completed)
        }
        #expect(boundary.events == ["outcome", "cleanup"])
        let child = saved.preparation.identity.analysisID
        let unpreviewed = try ModelContext(container).fetch(FetchDescriptor<LocalAnalysisRecord>())
        #expect(unpreviewed.first { $0.id == child.uuidString.lowercased() }?.state == nil)
        let cleanup = try #require(try ModelContext(container).fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(child)))
        #expect(try ObservationReanalysisErasureReceipt.restore(cleanup) == .init(parentID: observation, childID: child))
        var cloud = client()
        cloud.fetchState = { request in
            #expect(request.analysis_id == child.uuidString.lowercased())
            return try state(snapshot: saved.result, revision: 11, selected: original)
        }
        _ = try await ObservationHistoryPreviewService(cloud: cloud).preview(observationID: observation.uuidString,
            analysisID: child, container: container)
        #expect(try ticket(original, container: container).rejectionOperationID == saved.rejection.request.operationID)
        let selection = try await select(child, data: state(snapshot: saved.result, revision: 12, selected: child),
            previous: original, container: container)
        #expect(try ticket(child, container: container).reviewState == .unreviewed)
        _ = try await select(original, data: state(snapshot: saved.source.snapshot, revision: 13, selected: original,
            review: 1, rejection: saved.rejection), previous: child, container: container, undo: selection)
        let displayed = try ticket(original, container: container)
        #expect(displayed.rejectionOperationID == saved.rejection.request.operationID)
        let undo = try ObservationAnalysisReviewAdmission.stage(displayed.request(.undo(rejectionOperationID: saved.rejection.request.operationID), operationID: UUID()),
            ticket: displayed, container: container, isCurrent: { true })
        let completed = try await settle(undo, data: state(snapshot: saved.source.snapshot, revision: 14,
            selected: original, review: 2, rejection: undo, cleared: true), container: container)
        #expect(completed.isComplete && completed.request.operationID != saved.rejection.request.operationID)
        let final = try ticket(original, container: container)
        #expect(final.selectedAnalysisID == original && final.rejectionOperationID == nil && final.reviewRevision == 2 && final.reviewState == .unreviewed)
        let records = try ModelContext(container).fetch(FetchDescriptor<LocalAnalysisRecord>())
        #expect(records.count == 2)
        #expect(records.first { $0.id == original.uuidString.lowercased() }?.resultSnapshotData == saved.source.snapshot)
        #expect(records.first { $0.id == child.uuidString.lowercased() }?.resultSnapshotData == saved.result)
        let receiptJob = try #require(try ModelContext(container).fetchOfflineJob(id: Review.jobID(saved.rejection.request.operationID, observationID: observation)))
        #expect(try Review.restore(receiptJob).storedData() == saved.rejection.storedData())
    }
}
