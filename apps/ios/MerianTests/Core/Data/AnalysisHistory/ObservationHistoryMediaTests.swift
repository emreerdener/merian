import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationHistoryMediaTests {
    let support = ObservationHistoryPhotoTests()

    func source(_ container: ModelContainer) throws -> ObservationCompositionSource {
        try .capture(observationID: #require(UUID(uuidString: support.support.observation)),
            analysisID: support.analysis, ownerID: support.support.owner, container: container)
    }

    @Test func photoSourceKeepsExactNotesAndSelectionDoesNotRetargetIt() async throws {
        let container = try await support.seed(), saved = try source(container)
        #expect(saved.artifacts.count == 1)
        #expect(saved.nodes.contains { if case .description = $0 { return true }; return false })
        let context = ModelContext(container)
        let scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        scan.selectedAnalysisID = UUID().uuidString.lowercased()
        try context.save()
        try saved.validate(container: container)
        #expect(try source(container) == saved)
    }

    @Test(arguments: [4, 5]) func originalAudioAndVideoRemainSingleToolbarNodes(version: Int) async throws {
        let (container, ticket) = try await ObservationAnalysisReviewAdmissionTests().seed(audio: version == 4, video: version == 5)
        let saved = try ObservationCompositionSource.capture(observationID: ticket.observationID,
            analysisID: ticket.analysisID, ownerID: ticket.ownerID, container: container)
        let physical = saved.nodes.filter { if case .description = $0 { return false }; return true }
        #expect(physical.count == 1)
        if version == 4 {
            guard case .audio = physical.first else { Issue.record("Audio source lost its original type"); return }
            #expect(saved.artifacts.count == 1)
        } else {
            guard case let .video(video) = physical.first else { Issue.record("Video was flattened into derived frames"); return }
            #expect(saved.artifacts.count == 1 + video.provenance.frames.count + (video.provenance.audio == nil ? 0 : 1))
        }
        try saved.validate(container: container)
    }

    @Test func verifiedBytesLoadWithoutPersistingCapabilitiesAndCorruptionIsRejected() async throws {
        let container = try await support.seed(), saved = try source(container)
        let artifact = try #require(saved.artifacts.first), ticket = try support.ticket()
        var finished = 0
        var loader = ObservationHistoryMediaLoader(account: support.support.client(fetch: { _ in Data() }, finish: { finished += 1 }),
            resolve: { request in
                #expect(request.analysis_id == saved.analysisID.uuidString.lowercased())
                #expect(request.resolution_protocol == 1)
                return ticket
            }, download: { _ in Data([1, 2, 3]) })
        #expect(try await loader.load(source: saved, artifact: artifact, container: container, isCurrent: { true }) == Data([1, 2, 3]))
        loader.download = { _ in Data([3, 2, 1]) }
        await #expect(throws: ObservationHistoryError.invalidSnapshot) {
            try await loader.load(source: saved, artifact: artifact, container: container, isCurrent: { true })
        }
        #expect(finished == 2)
        #expect(try support.support.count(container) == 2)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }

    @Test(arguments: ["owner", "delete", "snapshot", "presentation"])
    func changedAuthorityDuringResolutionPreventsDownload(change: String) async throws {
        let container = try await support.seed(), saved = try source(container)
        let artifact = try #require(saved.artifacts.first), ticket = try support.ticket()
        var current = true
        let loader = ObservationHistoryMediaLoader(account: support.support.client(fetch: { _ in Data() }), resolve: { _ in
            let context = ModelContext(container)
            let scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
            switch change {
            case "owner": scan.analysisOwnerAccountID = UUID().uuidString.lowercased()
            case "delete": context.delete(scan)
            case "snapshot":
                let record = try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first { $0.id == saved.analysisID.uuidString.lowercased() })
                let replacement = try LocalAnalysisRecord(analysisID: saved.analysisID, observationID: record.observationID,
                    ownerAccountID: saved.ownerID, completedAt: record.completedAt, snapshotVersion: record.snapshotVersion,
                    resultSnapshotData: record.resultSnapshotData + Data([0x20]))
                context.delete(record)
                try context.save()
                context.insert(replacement)
                scan.analysisRecords?.append(replacement)
            default: current = false
            }
            try context.save()
            return ticket
        }, download: { _ in Issue.record("Stale authority reached download"); return Data() })
        await #expect(throws: (any Error).self) {
            try await loader.load(source: saved, artifact: artifact, container: container, isCurrent: { current })
        }
    }

    @Test func unrelatedArtifactAndUnsafeTicketNeverDownload() async throws {
        let container = try await support.seed(), saved = try source(container)
        let artifact = try #require(saved.artifacts.first)
        let wrong = ObservationVideoProvenance.Artifact(mediaID: UUID(), contentType: artifact.contentType,
            byteCount: artifact.byteCount, sha256: artifact.sha256)
        let forbidden = ObservationHistoryMediaLoader(account: support.support.client(fetch: { _ in Data() }), resolve: { _ in
            Issue.record("Nonmember reached resolution"); throw ObservationHistoryError.unavailable
        })
        await #expect(throws: ObservationHistoryError.invalidSnapshot) {
            try await forbidden.load(source: saved, artifact: wrong, container: container, isCurrent: { true })
        }
        for ticket in [try support.ticket(owner: UUID().uuidString), try support.ticket(url: "https://example.invalid/media"),
                       try support.ticket(expiry: Date().addingTimeInterval(-1))] {
            let loader = ObservationHistoryMediaLoader(account: support.support.client(fetch: { _ in Data() }), resolve: { _ in ticket },
                download: { _ in Issue.record("Invalid ticket reached download"); return Data() })
            await #expect(throws: ObservationHistoryError.invalidSnapshot) {
                try await loader.load(source: saved, artifact: artifact, container: container, isCurrent: { true })
            }
        }
    }
}
