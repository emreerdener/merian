import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized)
struct ObservationHistoryPreviewTests {
    let support = ObservationHistorySyncTests()
    let target = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    let selected = UUID(uuidString: "00000000-0000-4000-8000-000000000009")!
    typealias Failure = ObservationHistoryPreviewService.AdmissionError

    func response(revision: Int = 10, selected: UUID? = nil, native: Bool = false) throws -> Data {
        var value = try ObservationHistoryStateTests().fixture()
        value["state_revision"] = revision
        value["selected_analysis_id"] = (selected ?? self.selected).uuidString.lowercased()
        if native {
            var item = value["analysis"] as! [String: Any]
            let page = try support.fixture()
            item["snapshot"] = (page["items"] as! [[String: Any]])[0]["snapshot"]
            value["analysis"] = item
        }
        return try support.bytes(value)
    }

    func service(_ data: Data, current: @escaping () -> Bool = { true },
                 duringFetch: @escaping () throws -> Void = {}, finish: @escaping () -> Void = {}) -> ObservationHistoryPreviewService {
        var cloud = support.client(fetch: { _ in throw ObservationHistoryError.unavailable }, current: current, finish: finish)
        cloud.fetchState = { request in
            #expect(request.analysis_id == target.uuidString.lowercased())
            try duringFetch()
            return data
        }
        return .init(cloud: cloud)
    }

    func assertNoHistory(_ container: ModelContainer) throws {
        let context = ModelContext(container)
        #expect(try context.fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<LocalAnalysisStateRecord>()) == 0)
    }

    @Test func importedPreviewCachesExactEvidenceAndAuthorityWithoutSelectingOrInventingDisplay() async throws {
        let container = try support.container(), service = service(try response())
        let preview = try await service.preview(observationID: support.observation, analysisID: target, container: container)
        #expect(preview.display == nil && !preview.isSelected)
        #expect(preview.state.result.completedAt == nil)
        #expect(preview.state.result.importedAt != nil)
        _ = try await service.preview(observationID: support.observation, analysisID: target, container: container)
        let context = ModelContext(container)
        let scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(scan.selectedAnalysisID == selected.uuidString.lowercased() && scan.observationStateRevision == 10)
        #expect(scan.scientificName == "Preserved correction" && scan.userIdentificationOverride == "Existing correction")
        #expect(scan.userConfirmedIdentification && scan.aiIdentificationReviewData == Data("synthetic review bytes".utf8))
        let result = try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)
        #expect(result.resultSnapshotData == preview.state.result.bytes)
        #expect(result.state?.reviewSnapshotData == preview.state.review.data)
        #expect(try context.fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<LocalAnalysisStateRecord>()) == 1)
        context.delete(scan)
        try context.save()
        try assertNoHistory(container)
    }

    @Test func nativePreviewReturnsItsOwnDisplayAndPreservesPendingReview() async throws {
        let container = try support.container(), context = ModelContext(container)
        context.insert(OfflineJobRecord(id: "synthetic-pending-review", kind: .identificationReviewSync,
            subjectId: support.observation))
        try context.save()
        let preview = try await service(response(native: true)).preview(observationID: support.observation, analysisID: target, container: container)
        #expect(preview.display?.scientificName == "Danaus plexippus")
        #expect(preview.display?.analysisID == target && !preview.isSelected)
        let fresh = ModelContext(container)
        #expect(try fresh.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 1)
        #expect(try fresh.fetch(FetchDescriptor<LocalScanRecord>()).first?.userIdentificationOverride == "Existing correction")
    }

    @Test func staleFutureAndEqualRevisionDifferentSelectionDoNotWrite() async throws {
        for (revision, selection, failure) in [(9, selected, Failure.staleRevision), (11, selected, Failure.refreshRequired),
                                               (10, target, Failure.conflictingRevision)] {
            let container = try support.container()
            await #expect(throws: failure) {
                try await service(response(revision: revision, selected: selection)).preview(observationID: support.observation,
                    analysisID: target, container: container)
            }
            try assertNoHistory(container)
        }
    }

    @Test func accountChangeAndCancellationDiscardResponseAndFinishLease() async throws {
        let container = try support.container()
        var current = true, finished = false
        let service = service(try response(), current: { current }, duringFetch: { current = false }, finish: { finished = true })
        await #expect(throws: ObservationHistoryError.accountChanged) {
            try await service.preview(observationID: support.observation, analysisID: target, container: container)
        }
        #expect(finished)
        try assertNoHistory(container)
        let cancelled = serviceForCancellation()
        let task = Task { try await cancelled.preview(observationID: support.observation, analysisID: target, container: container) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        try assertNoHistory(container)
    }

    private func serviceForCancellation() -> ObservationHistoryPreviewService {
        var cloud = support.client(fetch: { _ in Data() })
        cloud.fetchState = { _ in try Task.checkCancellation(); return try response() }
        return .init(cloud: cloud)
    }

    @Test func deletionAndSelectionChangesDuringFetchWin() async throws {
        for delete in [false, true] {
            let container = try support.container()
            let service = service(try response(), duringFetch: {
                let context = ModelContext(container)
                if delete {
                    try context.ensurePendingCloudDeletionTask(scanId: support.observation, requestingAccountID: support.owner, origin: .explicitUserDeletion)
                } else {
                    let scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
                    scan.selectedAnalysisID = target.uuidString.lowercased()
                    scan.observationStateRevision = 11
                }
                try context.save()
            })
            if delete {
                await #expect(throws: ObservationHistoryError.deleted) {
                    try await service.preview(observationID: support.observation, analysisID: target, container: container)
                }
            } else {
                await #expect(throws: Failure.conflictingRevision) {
                    try await service.preview(observationID: support.observation, analysisID: target, container: container)
                }
            }
            try assertNoHistory(container)
        }
    }

    @Test func unacknowledgedObservationNeverStartsNetworkWork() async throws {
        let container = try support.container(enrolled: false)
        let service = service(try response(), duringFetch: { Issue.record("Unenrolled preview reached network") })
        await #expect(throws: ObservationHistoryError.unavailable) {
            try await service.preview(observationID: support.observation, analysisID: target, container: container)
        }
        try assertNoHistory(container)
    }
}
