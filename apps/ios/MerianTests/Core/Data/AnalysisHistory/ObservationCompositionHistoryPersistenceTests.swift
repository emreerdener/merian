import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationCompositionHistoryPersistenceTests {
    let fixture = ObservationHistorySyncTests()
    var owner: UUID { fixture.owner }
    var observation: String { fixture.observation }

    @Test func compositionResultSyncReplaysAndReopensWithoutChangingSelectionOrCorrection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("composition-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fixture.store"), snapshot = try fixture.compositionSnapshot(), data = try fixture.audioPage(snapshot)
        let analysis = try ObservationHistoryPage.uuid(snapshot["analysis_id"])
        do {
            let container = try fixture.container(url: url)
            let service = ObservationHistorySyncService(cloud: fixture.client(fetch: { _ in data }))
            _ = try await service.syncPage(observationID: observation, container: container)
            _ = try await service.syncPage(observationID: observation, container: container)
            #expect(try fixture.count(container) == 1)
            var changed = snapshot; changed["completed_at_ms"] = 1750000000001 as Int64
            let conflict = ObservationHistorySyncService(cloud: fixture.client(fetch: { _ in try fixture.audioPage(changed) }))
            await #expect(throws: ObservationHistoryError.resultConflict) {
                try await conflict.syncPage(observationID: observation, container: container)
            }
        }
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let reopened = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let context = ModelContext(reopened), scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let entry = try ObservationHistoryListingService.entry(analysis, scan: scan, context: context)
        #expect(try entry.result.bytes == fixture.bytes(snapshot))
        #expect(entry.result.version == 6 && entry.result.composition != nil && entry.result.video == nil && entry.result.audio == nil && entry.result.photos.isEmpty)
        #expect(scan.selectedAnalysisID == "00000000-0000-4000-8000-000000000009")
        #expect(scan.userIdentificationOverride == "Existing correction")
        let observationID = try #require(UUID(uuidString: observation))
        let frozen = try ObservationReanalysisSource.capture(observationID: observationID,
            analysisID: analysis, ownerID: owner, container: reopened)
        #expect(frozen.composition == entry.result.composition && frozen.snapshot == entry.result.bytes)
        let source = try ObservationCompositionSource.capture(observationID: observationID,
            analysisID: analysis, ownerID: owner, container: reopened)
        let kinds = source.nodes.map { node in
            switch node {
            case .image: return "image"
            case .audio: return "audio"
            case .video, .initialVideo: return "video"
            case .description: return "description"
            }
        }
        #expect(kinds == ["image", "description", "audio"])
        #expect(source.artifacts.map { $0.mediaID.uuidString.lowercased() } == [
            "00000000-0000-4000-8000-000000000010", "00000000-0000-4000-8000-000000000020"])
        try source.validate(container: reopened)
        try frozen.validate(container: reopened)
    }

    @Test func compositionSourceRetainsAuthorityAndRejectsInvalidation() throws {
        let source = ObservationReanalysisSourceTests()
        try source.frozenSourceSurvivesSelectionAndReviewRevisionChanges(version: 6)
        for reason in ["owner", "deleted-parent", "deleted-source", "pending-delete", "enrollment", "changed-bytes"] {
            try source.frozenSourceFailsClosedAfterInvalidation(reason: reason, version: 6)
        }
    }

    @Test func compositionSourceCreatesOneReopenableChild() async throws {
        try await ObservationCompositionPreparationTests().completeCompositionReopensAsOneHeldChild(version: 6)
    }
}
