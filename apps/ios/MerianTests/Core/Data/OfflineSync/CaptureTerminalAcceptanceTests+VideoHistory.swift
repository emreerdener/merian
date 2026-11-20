import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
extension CaptureTerminalAcceptanceTests {
    func recoverVideoChild(source: ObservationReanalysisSource, container: ModelContainer,
                           cloud: ObservationHistoryCloudClient, withText: Bool, startup: NativeReleaseStartupAdmission) async throws {
        var phase = "preparing video cohort"
        defer { if phase != "complete" { print("Initial video History join stopped at " + phase) } }
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let copies = root.appendingPathComponent("copies"), output = root.appendingPathComponent("output")
        for directory in [copies, output] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let descriptions = withText ? ["  Child e\u{301} 🐾\n", "After\n"] : []
        let choices = try ObservationReanalysisLocalVideoInput.choices(source: source, container: container)
        #expect(choices.count == 1)
        let chosen = try #require(choices.first)
        let input = try await ObservationReanalysisLocalVideoInput.freeze(chosen, descriptions: descriptions,
            container: container, files: .init(documents: .documentsDirectory, temporaryDirectory: copies),
            account: cloud, startup: startup, store: ObservationReanalysisFileStore(documents: root),
            ownership: .init(), owning: { _ in }, isCurrent: { true })
        let files = ObservationReanalysisFileStore(documents: root)
        let producer = ObservationVideoPreparationProducer(files: files, ownership: .init(), account: cloud)
        let proof = try await input.prepare(container: container, account: cloud, producer: producer,
            temporaryDirectory: output, isCurrent: { true })
        let preparation = try #require(input.preparation)
        #expect(input.analysisID == preparation.identity.analysisID)
        if withText {
            var invalid = try #require(JSONSerialization.jsonObject(with: preparation.request.manifest.originalBytes) as? [String: Any])
            invalid["descriptions"] = ["After\u{0}"]
            let request = try ObservationVideoReanalysisRequest(observationID: source.observationID,
                analysisID: preparation.request.analysisID, sourceAnalysisID: source.analysisID,
                manifestBytes: JSONSerialization.data(withJSONObject: invalid, options: [.sortedKeys]))
            #expect(throws: MerianError.invalidResponse) { try ObservationVideoSourceReservationRequest(video: request) }
        }
        let original = try await files.readVideo(preparation: preparation, validateBeforeRead: {}, validateBeforeReturn: {})
        #expect(original.count == 7)
        #expect(preparation.request.manifest.descriptions == descriptions)
        #expect(try await producer.prepare(preparation, source: source, cohort: nil,
            container: container, isCurrent: { true }) == .ready)
        // Synthetic receipts at existing cloud boundaries; no provider or hosted mutation.
        phase = "reserving video source"
        let reservation = try ObservationVideoSourceReservationStore.stage(.init(video: preparation.request),
            proof: proof, container: container, isCurrent: { true })
        let reservationClaim = try ObservationVideoSourceReservationStore.claim(reservation,
            proof: proof, container: container, isCurrent: { true })
        let reserved = try ObservationVideoSourceReservationStore.settle(reservationClaim,
            settlement: .reply(ObservationVideoReservationLifecycleTests().reply(reservation)),
            proof: proof, container: container, isCurrent: { true })
        _ = try ObservationVideoUploadStore.stage(reserved, proof: proof, container: container, isCurrent: { true })
        phase = "uploading video cohort"
        var upload = try ObservationVideoUploadLifecycleStore.read(proof: proof, container: container, isCurrent: { true })
        let uploadFixture = ObservationVideoUploadLifecycleTests()
        for item in upload.work.staged.request.inventory.items {
            #expect(upload.work.nextMediaID == item.artifact.mediaID)
            let claim = try ObservationVideoUploadLifecycleStore.claim(upload, proof: proof, container: container, isCurrent: { true })
            upload = try ObservationVideoUploadLifecycleStore.settle(claim, receipt: uploadFixture.receipt(claim),
                proof: proof, container: container, isCurrent: { true })
        }
        #expect(upload.work.receipt?.state == .ready)
        phase = "executing video child"
        let saved = try ObservationVideoExecutionStore.stage(upload, proof: proof,
            authorization: ObservationVideoExecutionStoreTests().authorization, container: container, isCurrent: { true })
        let fixture = ObservationVideoExecutionServiceTests()
        let boundary = try ObservationVideoExecutionServiceTests.Boundary(source: source, preparation: preparation, container: container)
        let resultBytes = try #require(boundary.bytes)
        boundary.hook = { if $0 == "analyze" { throw URLError(.networkConnectionLost) } }
        try await fixture.owned(saved, source: source, container: container) { scope, _ in
            #expect(await boundary.service.run(saved, proof: proof, container: container,
                scope: scope, cleanup: boundary.cleanup) == .held)
        }
        phase = "recovering video child"
        let held = try ObservationVideoExecutionStore.read(proof: proof, container: container, isCurrent: { true })
        #expect(held.work.consumed && held.work.request.body == saved.work.request.body)
        #expect(throws: (any Error).self) {
            try ObservationVideoExecutionStore.claim(held, proof: proof, container: container, isCurrent: { true })
        }
        try await fixture.owned(held, source: source, container: container) { scope, _ in
            #expect(await boundary.service.run(held, proof: proof, container: container,
                scope: scope, cleanup: boundary.cleanup) == .completed)
        }
        #expect(boundary.events == ["authorize", "analyze", "outcome", "cleanup"])
        #expect(try await files.readVideo(preparation: preparation, validateBeforeRead: {}, validateBeforeReturn: {}) == original)
        let child = preparation.identity.analysisID
        let snapshots = [source.analysisID.uuidString.lowercased(): source.snapshot,
                         child.uuidString.lowercased(): resultBytes]
        var historyCloud = cloud
        var writes = 0
        historyCloud.select = { _ in writes += 1; throw ObservationHistoryError.unavailable }
        historyCloud.fetchState = { request in
            #expect(request.analysis_id == child.uuidString.lowercased())
            var state = try ObservationVideoHistoryJourneyTests().state(resultBytes, source: source)
            state["state_revision"] = 1
            return try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
        }
        historyCloud.fetch = { _ in
            var page = try ObservationHistorySyncTests().fixture()
            page["owner_id"] = source.ownerID.uuidString.lowercased()
            page["observation_id"] = source.observationID.uuidString.lowercased()
            page["state_revision"] = 1
            page["items"] = [["ordinal": 2, "snapshot": String(decoding: resultBytes, as: UTF8.self)],
                             ["ordinal": 1, "snapshot": String(decoding: source.snapshot, as: UTF8.self)]]
            return try JSONSerialization.data(withJSONObject: page, options: [.sortedKeys])
        }
        let observationID = source.observationID.uuidString.lowercased()
        let listing = ObservationHistoryListingService(cloud: historyCloud)
        phase = "listing video History"
        let page = try await listing.page(observationID: observationID, container: container)
        #expect(page.entries.map(\.result.analysisID) == [child, source.analysisID])
        phase = "previewing video child"
        let preview = try await ObservationHistoryPreviewService(cloud: historyCloud).preview(
            observationID: observationID, analysisID: child, container: container)
        #expect(!preview.isSelected && preview.displayOrigin == .analysisResult)
        #expect(preview.state.result.bytes == resultBytes)
        #expect(preview.state.result.video?.descriptions == descriptions)
        var actionState = try ObservationVideoHistoryJourneyTests().state(resultBytes, source: source)
        actionState["state_revision"] = 1
        try await exerciseCompletedChildActions(source: source, child: child, resultBytes: resultBytes,
            container: container, cloud: cloud, baselineState: actionState)
        let fresh = ModelContext(container)
        #expect(try Dictionary(uniqueKeysWithValues: fresh.fetch(FetchDescriptor<LocalAnalysisRecord>())
            .map { ($0.id, $0.resultSnapshotData) }) == snapshots)
        #expect(writes == 0) // Only proves the preview/listing phase did not dispatch.
        #expect(try await files.readVideo(preparation: preparation, validateBeforeRead: {}, validateBeforeReturn: {}) == original)
        #expect(await input.discardCopiedInput())
        #expect(try FileManager.default.contentsOfDirectory(atPath: copies.path).isEmpty)
        phase = "complete"
    }
}
