import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationVideoHistoryJourneyTests {
    struct Saved {
        let root: URL
        let url: URL
        let source: ObservationReanalysisSource
        let request: ObservationVideoReanalysisRequest
        let result: Data
        let receipt: String
        let files: [String]
    }

    @MainActor final class Reads {
        let owner: UUID
        var page = Data(), state = Data()
        var began = 0, finished = 0, pages = 0, states: [ObservationHistoryStateRequest] = []
        var mutations = 0
        init(owner: UUID) { self.owner = owner }
        var cloud: ObservationHistoryCloudClient {
            .init(begin: { expected in
                #expect(expected == self.owner); self.began += 1
                return .init(id: UUID(), session: .init(userID: expected, isAnonymous: false))
            }, isCurrent: { _ in true }, finish: { _ in self.finished += 1 }, fetch: { request in
                #expect(request.before_ordinal == nil && request.limit == 20)
                self.pages += 1; return self.page
            }, fetchState: { request in self.states.append(request); return self.state },
            select: { _ in self.mutations += 1; throw ObservationHistoryError.unavailable })
        }
    }

    func bytes(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    func state(_ result: Data, source: ObservationReanalysisSource) throws -> [String: Any] {
        var value = try ObservationHistoryStateTests().fixture()
        value["owner_id"] = source.ownerID.uuidString.lowercased()
        value["observation_id"] = source.observationID.uuidString.lowercased()
        value["selected_analysis_id"] = source.analysisID.uuidString.lowercased()
        value["state_revision"] = 10
        var item = try #require(value["analysis"] as? [String: Any])
        item["snapshot"] = String(decoding: result, as: UTF8.self)
        value["analysis"] = item
        return value
    }

    func page(_ saved: Saved, result: Data? = nil) throws -> Data {
        var value = try ObservationHistorySyncTests().fixture()
        value["owner_id"] = saved.source.ownerID.uuidString.lowercased()
        value["observation_id"] = saved.source.observationID.uuidString.lowercased()
        value["state_revision"] = 10
        value["items"] = [["ordinal": 2, "snapshot": String(decoding: result ?? saved.result, as: UTF8.self)],
                          ["ordinal": 1, "snapshot": String(decoding: saved.source.snapshot, as: UTF8.self)]]
        return try bytes(value)
    }

    // No provider or execution service is installed. Only values leave this scope,
    // so subsequent reads reopen the disk store after releasing the first container.
    func completed(audio: Bool) async throws -> Saved {
        let helper = ObservationVideoCompletionTests()
        let (seed, consumed) = try await helper.consumed(audio: audio)
        defer { seed.media.remove() }
        do {
            try ObservationHistoryStateSyncTests().update(seed.container) { scan, _ in
                scan.speciesId = ""; scan.isBiological = true; scan.confidenceScore = 0.75
                scan.aiReasoning = "Synthetic saved identification."; scan.inferenceTier = "flash"
                scan.candidatesData = Data("{}".utf8)
                scan.confirmedSpeciesIdentityData = try ConfirmedSpeciesReview(revision: 0, identity: nil,
                    override: nil, confirmed: false, speciesID: nil, state: .unreviewed).storedData()
            }
            let reads = Reads(owner: seed.source.ownerID)
            reads.state = try bytes(state(seed.source.snapshot, source: seed.source))
            _ = try await ObservationHistoryStateSyncService(cloud: reads.cloud)
                .syncSelected(observationID: seed.source.observationID.uuidString, container: seed.container)
            #expect(reads.began == reads.finished)
            let result = try helper.result(consumed.work.request)
            _ = try ObservationVideoExecutionStore.complete(consumed, resultBytes: result, proof: seed.proof,
                container: seed.container, isCurrent: { true })
            let job = try #require(try ModelContext(seed.container).fetchOfflineJob(id:
                ObservationReanalysisErasureReceipt.jobID(seed.preparation.identity.analysisID)))
            return Saved(root: seed.root, url: seed.storeURL, source: seed.source, request: consumed.work.request,
                         result: result, receipt: try #require(job.metadataJSON), files: seed.preparation.files.map(\.path))
        } catch { seed.remove(); throw error }
    }

    func unchanged(_ saved: Saved, container: ModelContainer) throws {
        let context = ModelContext(container)
        let parent = try ObservationHistorySyncService.enrolledScan(saved.source.observationID.uuidString, context: context)
        #expect(parent.selectedAnalysisID == saved.source.analysisID.uuidString.lowercased())
        #expect(parent.observationStateRevision == 10 && parent.scientificName == "Fixture")
        let rows = try context.fetch(FetchDescriptor<LocalAnalysisRecord>())
        #expect(rows.count == 2)
        #expect(rows.first { $0.id == saved.request.analysisID.uuidString.lowercased() }?.resultSnapshotData == saved.result)
        #expect(rows.first { $0.id == saved.source.analysisID.uuidString.lowercased() }?.resultSnapshotData == saved.source.snapshot)
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try ObservationHistorySelectionIntent.load(parent.id, context: context) == nil)
        let jobs = try context.fetch(FetchDescriptor<OfflineJobRecord>())
        #expect(jobs.count == 1)
        let receipt = try #require(jobs.first)
        #expect(receipt.metadataJSON == saved.receipt)
        #expect(try ObservationReanalysisErasureReceipt.restore(receipt) == .init(parentID: saved.source.observationID,
            childID: saved.request.analysisID))
        for path in saved.files { #expect(FileManager.default.fileExists(atPath: saved.root.appendingPathComponent(path).path)) }
    }

    @Test(arguments: [false, true])
    func completedVideoRefreshPreviewAndReopenRemainReadOnly(audio: Bool) async throws {
        let saved = try await completed(audio: audio)
        defer { try? FileManager.default.removeItem(at: saved.root) }
        let reads = Reads(owner: saved.source.ownerID)
        reads.page = try page(saved); reads.state = try bytes(state(saved.result, source: saved.source))
        do {
            let container = try ObservationPublicationPersistenceTests().container(url: saved.url, seed: false)
            let listing = ObservationHistoryListingService(cloud: reads.cloud)
            for _ in 0..<2 {
                let page = try await listing.page(observationID: saved.source.observationID.uuidString, container: container)
                #expect(page.entries.map(\.result.analysisID) == [saved.request.analysisID, saved.source.analysisID])
                #expect(page.nextBeforeOrdinal == nil && page.context.selected == saved.source.analysisID)
                let preview = try await ObservationHistoryPreviewService(cloud: reads.cloud).preview(
                    observationID: saved.source.observationID.uuidString, analysisID: saved.request.analysisID, container: container)
                #expect(!preview.isSelected && preview.displayOrigin == .analysisResult && preview.display != nil)
                #expect(preview.state.result.bytes == saved.result)
                #expect(preview.state.result.video?.provenance == saved.request.manifest.provenance)
                try unchanged(saved, container: container)
            }
        }
        let reopened = try ObservationPublicationPersistenceTests().container(url: saved.url, seed: false)
        let listing = ObservationHistoryListingService(cloud: reads.cloud)
        let entry = try listing.cached(observationID: saved.source.observationID.uuidString,
            analysisID: saved.request.analysisID, container: reopened)
        #expect(entry.result.version == 5 && entry.result.photos.isEmpty && entry.result.audio == nil)
        #expect(entry.result.video?.provenance == saved.request.manifest.provenance)
        #expect(entry.result.video?.descriptions == saved.request.manifest.descriptions)
        #expect((entry.result.video?.provenance.audio != nil) == audio)
        #expect(entry.result.bytes == saved.result && entry.display != nil && entry.authority != nil && entry.reviewRevision == 0)
        let context = try listing.context(observationID: saved.source.observationID.uuidString, container: reopened)
        let original = try listing.cached(observationID: saved.source.observationID.uuidString,
            analysisID: saved.source.analysisID, container: reopened)
        _ = try ObservationAnalysisReviewTicket(entry: original, context: context, observationID: saved.source.observationID)
        #expect(throws: ObservationHistoryError.unavailable) {
            try ObservationHistorySelectionService(cloud: reads.cloud).prepare(observationID: saved.source.observationID.uuidString,
                analysisID: saved.request.analysisID, ownerID: saved.source.ownerID, container: reopened)
        }
        #expect(throws: ObservationHistoryError.unavailable) {
            try ObservationAnalysisReviewTicket(entry: entry, context: context, observationID: saved.source.observationID)
        }
        // Even a selected V5 value cannot supply a Field Chat ticket.
        let selectedVideo = ObservationHistoryListingService.Context(owner: context.owner, selected: entry.result.analysisID,
            revision: context.revision, pendingOperation: nil, undoOperation: nil)
        #expect(throws: ObservationHistoryError.unavailable) {
            try ProtectedInsightChatTicket(entry: entry, context: selectedVideo, observationID: saved.source.observationID)
        }
        var publicationCalls = 0
        let publication = ObservationPublicationConsentService(cloud: reads.cloud, fetch: { _, _ in
            publicationCalls += 1; throw ObservationHistoryError.unavailable
        })
        await #expect(throws: ObservationHistoryError.unavailable) {
            let ticket = try ObservationAnalysisReviewTicket(entry: entry, context: context, observationID: saved.source.observationID)
            _ = try await publication.prepare(ticket: ticket, container: reopened, isCurrent: { true })
        }
        #expect(throws: ObservationHistoryError.unavailable) {
            try ObservationReanalysisSource.capture(observationID: saved.source.observationID,
                analysisID: saved.request.analysisID, ownerID: saved.source.ownerID, container: reopened)
        }
        #expect(throws: ObservationHistoryError.unavailable) {
            try ObservationReanalysisSource.captureForAudio(observationID: saved.source.observationID,
                analysisID: saved.request.analysisID, ownerID: saved.source.ownerID, container: reopened)
        }
        #expect(throws: ObservationHistoryError.unavailable) {
            try ObservationReanalysisSource.captureForVideo(observationID: saved.source.observationID,
                analysisID: saved.request.analysisID, ownerID: saved.source.ownerID, container: reopened)
        }
        #expect(reads.pages == 2 && reads.states.count == 2 && reads.began == reads.finished)
        #expect(reads.states.allSatisfy { $0.analysis_id == saved.request.analysisID.uuidString.lowercased()
            && $0.observation_id == saved.source.observationID.uuidString.lowercased() })
        #expect(reads.mutations == 0 && publicationCalls == 0)
        try unchanged(saved, container: reopened)
    }

    @Test(arguments: [false, true])
    func conflictingRefreshesCannotReplaceCompletedVideoOrReceipt(audio: Bool) async throws {
        let saved = try await completed(audio: audio)
        defer { try? FileManager.default.removeItem(at: saved.root) }
        let container = try ObservationPublicationPersistenceTests().container(url: saved.url, seed: false)
        let reads = Reads(owner: saved.source.ownerID)
        var changed = try #require(JSONSerialization.jsonObject(with: saved.result) as? [String: Any])
        changed["completed_at_ms"] = 1750000000001 as Int64
        reads.page = try page(saved, result: bytes(changed))
        await #expect(throws: ObservationHistoryError.resultConflict) {
            _ = try await ObservationHistoryListingService(cloud: reads.cloud)
                .page(observationID: saved.source.observationID.uuidString, container: container)
        }
        try unchanged(saved, container: container)
        for boundary in ["owner", "analysis", "revision", "source"] {
            var value = try state(saved.result, source: saved.source)
            if boundary == "owner" { value["owner_id"] = UUID().uuidString.lowercased() }
            if boundary == "revision" { value["state_revision"] = 9 }
            if boundary == "analysis" || boundary == "source" {
                var item = try #require(value["analysis"] as? [String: Any])
                var result = try #require(JSONSerialization.jsonObject(with: saved.result) as? [String: Any])
                result[boundary == "analysis" ? "analysis_id" : "source_analysis_id"] = UUID().uuidString.lowercased()
                item["snapshot"] = String(decoding: try bytes(result), as: UTF8.self); value["analysis"] = item
            }
            reads.state = try bytes(value)
            await #expect(throws: (any Error).self) {
                _ = try await ObservationHistoryPreviewService(cloud: reads.cloud).preview(
                    observationID: saved.source.observationID.uuidString, analysisID: saved.request.analysisID, container: container)
            }
            try unchanged(saved, container: container)
        }
        #expect(reads.began == reads.finished && reads.mutations == 0)
    }
}
