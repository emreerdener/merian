import CryptoKit
import Foundation
@testable import Merian
import SwiftData
import Testing
import UIKit

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct CaptureReanalysisSessionTests {
    let fixture = ObservationReanalysisProducerTests()

    struct Seed {
        let container: ModelContainer
        let source: ObservationReanalysisSource
        let bytes: Data
    }

    func seed(count: Int = 3) throws -> Seed {
        let seed = try fixture.fixture.seed(), bytes = try fixture.image()
        let context = ModelContext(seed.container)
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let old = try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)
        var snapshot = try #require(JSONSerialization.jsonObject(with: old.resultSnapshotData) as? [String: Any])
        var items: [[String: Any]] = []
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        for index in 0..<count {
            items.append(["kind": "description", "text": "  Synthetic note \(index)  "])
            items.append(["kind": "image", "media_id": UUID().uuidString.lowercased(), "content_type": "image/png",
                          "byte_count": bytes.count, "sha256": hash])
        }
        snapshot["evidence_manifest"] = ["schema_version": 2, "items": items]
        let replacement = try LocalAnalysisRecord(analysisID: seed.result.analysisID, observationID: parent.id,
            ownerAccountID: fixture.fixture.fixture.owner, completedAt: old.completedAt, snapshotVersion: 2,
            resultSnapshotData: JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]))
        context.delete(old); try context.save(); context.insert(replacement); parent.analysisRecords = [replacement]; try context.save()
        return Seed(container: seed.container, source: try fixture.source(seed), bytes: bytes)
    }

    @Test func explicitSubsetPreservesMixedOrderAndNeverTakesFirstTwoOrFive() throws {
        let seed = try seed(count: 6), photos = seed.source.photos
        #expect(throws: (any Error).self) {
            try CaptureReanalysisEvidenceSelection(source: seed.source, selectedPhotoIDs: Set(photos.map(\.mediaID)))
        }
        let selection = try CaptureReanalysisEvidenceSelection(source: seed.source,
            selectedPhotoIDs: [photos[1].mediaID, photos[5].mediaID])
        let selected = selection.evidence.compactMap { item -> UUID? in
            if case let .photo(photo) = item { return photo.mediaID }; return nil
        }
        #expect(selected == [photos[1].mediaID, photos[5].mediaID])
        #expect(selection.evidence.count == 8)
        #expect(selection.evidence[0] == .description("  Synthetic note 0  "))
        #expect(throws: (any Error).self) {
            try CaptureReanalysisEvidenceSelection(source: seed.source, selectedPhotoIDs: [UUID()])
        }
    }

    @Test func verifiedLoaderStagesWholeCohortWithOriginalProvenanceAndNoParentFallback() async throws {
        let seed = try seed(), selection = try CaptureReanalysisEvidenceSelection(source: seed.source,
            selectedPhotoIDs: Set(seed.source.photos.map(\.mediaID)))
        var calls = [UUID]()
        let loader = CaptureReanalysisEvidenceLoader(account: fixture.account(), loadPhoto: { source, photo, _ in
            #expect(source == seed.source); calls.append(photo.mediaID); return seed.bytes
        })
        let capture = try await loader.load(selection, container: seed.container, isCurrent: { true })
        #expect(capture.images.count == 3 && calls == seed.source.photos.map(\.mediaID))
        let plan = try CaptureReanalysisPreparation.plan(source: seed.source, capture: capture)
        #expect(plan.items.count == 6)
        for index in 0..<3 {
            #expect(capture.images[index].compressedData == seed.bytes)
            #expect(capture.images[index].reanalysisProvenance == .original(analysisID: seed.source.analysisID, photo: seed.source.photos[index]))
            #expect(capture.images[index].original.environmentContext == nil)
            guard case let .description(text) = plan.items[index * 2] else { Issue.record("Lost note order"); return }
            #expect(text == "  Synthetic note \(index)  ")
        }
    }

    @Test(arguments: [1, 3])
    func legacySourcesInheritNothing(version: Int) async throws {
        let seed = try fixture.fixture.seed(version: version), source = try fixture.source(seed)
        let selection = try CaptureReanalysisEvidenceSelection(source: source, selectedPhotoIDs: [])
        let loader = CaptureReanalysisEvidenceLoader(account: fixture.account(), loadPhoto: { _, _, _ in
            Issue.record("Legacy source borrowed a photo"); throw MerianError.invalidResponse
        })
        let capture = try await loader.load(selection, container: seed.container, isCurrent: { true })
        #expect(capture.isEmpty)
        #expect(throws: (any Error).self) { try CaptureReanalysisPreparation.plan(source: source, capture: capture) }
    }

    @Test(arguments: ["account", "generation", "digest", "deleted-parent"])
    func lateLoaderFailureNeverReturnsPartialCohort(reason: String) async throws {
        let seed = try seed(), selection = try CaptureReanalysisEvidenceSelection(source: seed.source,
            selectedPhotoIDs: Set(seed.source.photos.map(\.mediaID)))
        var current = true, calls = 0, finishes = 0
        let loader = CaptureReanalysisEvidenceLoader(account: fixture.account(current: { reason != "account" || current }, finish: { finishes += 1 }),
            loadPhoto: { _, _, _ in
                calls += 1
                if calls == 2 {
                    current = false
                    if reason == "digest" { return seed.bytes + Data([0]) }
                    if reason == "deleted-parent" {
                        let context = ModelContext(seed.container)
                        context.delete(try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)); try context.save()
                    }
                }
                return seed.bytes
            })
        await #expect(throws: (any Error).self) {
            try await loader.load(selection, container: seed.container, isCurrent: { reason != "generation" || current })
        }
        #expect(calls == 2 && finishes == 1)
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
    }

    @Test func retryKeepsExactPlanAndRejectsChangedEvidenceOrGeneration() async throws {
        let seed = try seed(count: 1), generation = UUID()
        let selection = try CaptureReanalysisEvidenceSelection(source: seed.source, selectedPhotoIDs: [seed.source.photos[0].mediaID])
        let loader = CaptureReanalysisEvidenceLoader(account: fixture.account(), loadPhoto: { _, _, _ in seed.bytes })
        var capture = try await loader.load(selection, container: seed.container, isCurrent: { true })
        let session = CaptureReanalysisSession(source: seed.source, generation: generation)
        let first = try session.preparation(capture: capture, generation: generation)
        let second = try session.preparation(capture: capture, generation: generation)
        #expect(first.analysisID == second.analysisID)
        guard case let .photo(firstID, _) = first.items[1], case let .photo(secondID, _) = second.items[1] else {
            Issue.record("Lost photo"); return
        }
        #expect(firstID == secondID && firstID != seed.source.photos[0].mediaID)
        #expect(throws: ObservationHistoryError.accountChanged) { try session.preparation(capture: capture, generation: UUID()) }
        capture.observationContexts[0].context.freeText += " edited"
        #expect(throws: ObservationHistoryError.resultConflict) { try session.preparation(capture: capture, generation: generation) }
        capture.clearAll()
        #expect(throws: ObservationHistoryError.resultConflict) { try session.preparation(capture: capture, generation: generation) }
        #expect(session.plan?.analysisID == first.analysisID)
    }

    @Test(arguments: [false, true])
    func lostPreparationResponseRetriesSameChildAndActionWithoutLegacyAdmission(submitted: Bool) async throws {
        let seed = try seed(count: 1), generation = UUID()
        let selection = try CaptureReanalysisEvidenceSelection(source: seed.source, selectedPhotoIDs: [seed.source.photos[0].mediaID])
        let capture = try await CaptureReanalysisEvidenceLoader(account: fixture.account(), loadPhoto: { _, _, _ in seed.bytes })
            .load(selection, container: seed.container, isCurrent: { true })
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let producer = ObservationReanalysisProducer(files: .init(documents: root), account: fixture.account(), loadOriginal: { _, _, _ in seed.bytes })
        let session = CaptureReanalysisSession(source: seed.source, generation: generation)
        await #expect(throws: ObservationHistoryError.accountChanged) {
            try await session.stage(capture: capture, generation: generation, container: seed.container, producer: producer, action: submitted ? .submit : .hold, isCurrent: {
                let context = ModelContext(seed.container)
                guard let text = try? context.fetch(FetchDescriptor<OfflineJobRecord>()).first?.metadataJSON else { return true }
                return (try? ObservationReanalysisPreparationIntent.decode(Data(text.utf8))) != nil
            })
        }
        let child = try #require(session.plan?.analysisID)
        let result = try await session.stage(capture: capture, generation: generation, container: seed.container, producer: producer, action: submitted ? .submit : .hold, isCurrent: { true })
        let draft: ObservationReanalysisDraft
        switch result {
        case let .draft(saved): #expect(!submitted); draft = saved
        case let .submitted(saved): #expect(submitted); draft = saved.draft
        case .bound: Issue.record("Unexpected admission"); return
        }
        #expect(draft.identity.analysisID == child)
        await #expect(throws: ObservationHistoryError.resultConflict) {
            try await session.stage(capture: capture, generation: generation, container: seed.container,
                producer: producer, action: submitted ? .hold : .submit, isCurrent: { true })
        }
        let context = ModelContext(seed.container)
        let jobs = try context.fetch(FetchDescriptor<OfflineJobRecord>())
        #expect(jobs.count == 1 && jobs[0].kind == .observationReanalysisSync && jobs[0].attemptCount == 0)
        #expect(jobs[0].status == .needsAttention)
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(try context.fetch(FetchDescriptor<LocalScanRecord>()).first?.selectedAnalysisID == seed.source.analysisID.uuidString.lowercased())
    }

    @Test func discardedSessionNeverStagesOrMintsASuccessor() throws {
        let seed = try seed(count: 1), generation = UUID()
        var capture = StagedCapture()
        capture.images = [.init(compressedData: seed.bytes, displayData: Data(), uiImage: UIImage(), original: .init(image: UIImage()))]
        let session = CaptureReanalysisSession(source: seed.source, generation: generation)
        let plan = try session.preparation(capture: capture, generation: generation)
        var finishes = 0
        let account = fixture.account(finish: { finishes += 1 })
        let discarded = try session.discard(generation: generation, container: seed.container, account: account, isCurrent: { true })
        let receipt = try #require(discarded)
        #expect(receipt.childID == plan.analysisID && session.isDiscarded && session.plan?.analysisID == plan.analysisID)
        #expect(throws: ObservationHistoryError.unavailable) { try session.preparation(capture: capture, generation: generation) }
        #expect(try session.discard(generation: generation, container: seed.container, account: account, isCurrent: { true }) == receipt)
        #expect(finishes == 2)
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
    }

    @Test func staleDiscardCannotReleasePlanOrCreateReceipt() throws {
        let seed = try seed(count: 1), generation = UUID()
        var capture = StagedCapture()
        capture.images = [.init(compressedData: seed.bytes, displayData: Data(), uiImage: UIImage(), original: .init(image: UIImage()))]
        let session = CaptureReanalysisSession(source: seed.source, generation: generation)
        let plan = try session.preparation(capture: capture, generation: generation)
        #expect(throws: ObservationHistoryError.accountChanged) {
            try session.discard(generation: generation, container: seed.container, account: fixture.account(current: { false }), isCurrent: { true })
        }
        #expect(!session.isDiscarded && session.plan?.analysisID == plan.analysisID)
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }

}
