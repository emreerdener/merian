import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized)
struct ObservationHistoryEnrollmentTests {
    let support = ObservationHistoryStateSyncTests()
    typealias Failure = ObservationHistoryEnrollmentService.AdmissionError

    func receipt() throws -> Data {
        Data(try DatabaseActorTestSupport.loadRepositorySource(at:
            "services/supabase/functions/_shared/analysisHistory/fixtures/enrollment-v1.json").utf8)
    }

    func container() throws -> ModelContainer {
        let container = try SavedIdentificationDisplayBaselineTests().container()
        try support.update(container) { scan, _ in
            scan.analysisOwnerAccountID = nil
            scan.selectedAnalysisID = nil
            scan.observationStateRevision = nil
        }
        return container
    }

    func service(state: Data? = nil, duringEnroll: @escaping () throws -> Void = {},
                 duringRead: @escaping () throws -> Void = {}, current: @escaping () -> Bool = { true },
                 finish: @escaping () -> Void = {}) -> ObservationHistoryEnrollmentService {
        var cloud = support.support.client(fetch: { _ in throw ObservationHistoryError.unavailable }, current: current, finish: finish)
        cloud.enroll = { observation in
            #expect(observation == UUID(uuidString: support.support.observation))
            try duringEnroll()
            return try receipt()
        }
        cloud.fetchState = { request in
            #expect(request.analysis_id == nil && request.observation_id == support.support.observation)
            try duringRead()
            return try state ?? support.fixture(revision: 1)
        }
        return .init(cloud: cloud)
    }

    func run(_ service: ObservationHistoryEnrollmentService, _ container: ModelContainer) async throws -> UUID {
        try await service.enroll(observationID: support.support.observation,
            expectedOwnerID: support.support.owner, container: container)
    }

    func expectUnenrolled(_ container: ModelContainer) throws {
        let context = ModelContext(container)
        if let scan = try context.fetch(FetchDescriptor<LocalScanRecord>()).first {
            #expect(scan.analysisOwnerAccountID == nil && scan.selectedAnalysisID == nil && scan.observationStateRevision == nil)
        }
        #expect(try context.fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<LocalAnalysisStateRecord>()) == 0)
    }

    @Test func strictSharedReceiptIsNotSelectionAuthority() throws {
        let id = UUID(uuidString: support.support.observation)!, owner = support.support.owner
        #expect(try ObservationHistoryEnrollment.decode(receipt(), observationID: id, ownerID: owner).baselineAnalysisID == UUID(uuidString: support.analysisID))
        let value = try JSONSerialization.jsonObject(with: receipt()) as! [String: Any]
        let patches: [[String: Any]] = [["owner_id": id.uuidString.lowercased()], ["observation_id": owner.uuidString.lowercased()],
            ["baseline_analysis_id": owner.uuidString.lowercased()], ["baseline_analysis_id": id.uuidString.lowercased()],
            ["schema_version": true], ["schema_version": 2], ["selected_analysis_id": support.analysisID],
            ["baseline_analysis_id": NSNull()], ["state_revision": 1]]
        for patch in patches {
            #expect(throws: (any Error).self) {
                try ObservationHistoryEnrollment.decode(support.support.bytes(value.merging(patch) { _, new in new }), observationID: id, ownerID: owner)
            }
        }
        #expect(throws: (any Error).self) {
            try ObservationHistoryEnrollment.decode(Data(repeating: 32, count: 4097), observationID: id, ownerID: owner)
        }
    }

    @Test func enrollmentAtomicallyPreservesSavedProjectionAndItsOwnAuthority() async throws {
        for confirmed in [false, true] {
            let container = try container()
            let response = try confirmed ? ObservationHistorySelectionSyncTests().confirmedResponse(revision: 10) : support.fixture(revision: 10, rejected: true)
            let state = try ObservationHistoryState.decode(response,
                request: .init(observation_id: support.support.observation, analysis_id: nil), ownerID: support.support.owner)
            try support.update(container) { scan, _ in
                scan.aiIdentificationReviewData = try LocalAIIdentificationReview(authority: state.review.aiReview).storedData()
                if let review = state.review.speciesReview { scan.confirmedSpeciesIdentityData = try review.storedData() }
                scan.confirmedSpeciesId = state.review.confirmedSpeciesID
                scan.userIdentificationOverride = state.review.override
                scan.userConfirmedIdentification = state.review.confirmed ?? false
                scan.userReviewStateRaw = state.review.state?.rawValue
                scan.capturedMediaJSON = "[]"
                scan.coverImagePath = "synthetic-local-photo.jpg"
            }
            let before = try #require(ModelContext(container).fetch(FetchDescriptor<LocalScanRecord>()).first)
            let display = AnalysisDisplaySnapshot(analysisID: state.selectedAnalysisID, record: before)
            let review = before.aiIdentificationReviewData, identity = before.confirmedSpeciesIdentityData
            #expect(try await run(service(state: response), container) == state.selectedAnalysisID)
            let context = ModelContext(container), scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
            #expect(scan.analysisOwnerAccountID == support.support.owner.uuidString.lowercased())
            #expect(scan.selectedAnalysisID == support.analysisID && scan.observationStateRevision == 10)
            #expect(AnalysisDisplaySnapshot(analysisID: state.selectedAnalysisID, record: scan) == display)
            #expect(scan.aiIdentificationReviewData == review && scan.confirmedSpeciesIdentityData == identity)
            #expect(scan.fieldNotes == "Preserved private note" && scan.customTags == ["Preserved tag"])
            #expect(scan.coverImagePath == "synthetic-local-photo.jpg" && scan.capturedMediaJSON == "[]")
            let child = try #require(scan.analysisRecords?.first)
            #expect(child.completedAt == nil && child.resultSnapshotData == state.result.bytes)
            #expect(child.state?.reviewSnapshotData == state.review.data)
            #expect(try SavedIdentificationDisplayBaseline.restore(#require(child.state?.displaySnapshotData), analysisID: state.selectedAnalysisID) == display)
            await #expect(throws: ObservationHistoryError.unavailable) { try await run(service(), container) }
            #expect(try support.support.count(container) == 1)
        }
    }

    @Test func lostEnrollmentResponseOrStateReadLeavesRetryableLocalState() async throws {
        for loseReceipt in [true, false] {
            let container = try container()
            let unavailable = { throw ObservationHistoryError.unavailable }
            let failed = service(duringEnroll: loseReceipt ? unavailable : {}, duringRead: loseReceipt ? {} : unavailable)
            await #expect(throws: ObservationHistoryError.unavailable) { try await run(failed, container) }
            try expectUnenrolled(container)
            let job = try #require(try ModelContext(container).fetchOfflineJob(id: ObservationHistoryEnrollmentIntent.jobID(support.support.observation)))
            #expect(job.kind == .future && job.status == .needsAttention && job.nextRunAt == nil && job.metadataJSON != nil)
            #expect(try await run(service(), container) == UUID(uuidString: support.analysisID))
            #expect(try support.support.count(container) == 1)
        }
    }

    @Test func receiptReplayAfterAnotherSelectionNeverRestoresBaseline() async throws {
        let container = try container()
        let response = try ObservationHistorySelectionSyncTests().nativeResponse(revision: 2)
        await #expect(throws: Failure.reconciliationRequired) { try await run(service(state: response), container) }
        try expectUnenrolled(container)
    }

    @Test func differingReviewEvidenceOrOversizedDisplayRequiresReconciliation() async throws {
        for mutation in 0..<3 {
            let container = try container()
            if mutation == 0 { try support.update(container) { scan, _ in scan.confidenceScore = 0.2 } }
            if mutation == 1 { try support.update(container) { scan, _ in scan.wikipediaOverview = String(repeating: "x", count: LocalAnalysisRecord.maximumSnapshotBytes) } }
            let response = try support.fixture(revision: 1, rejected: mutation == 2)
            await #expect(throws: Failure.reconciliationRequired) { try await run(service(state: response), container) }
            try expectUnenrolled(container)
        }
    }

    @Test func localEditsAndDeletionAcrossBothNetworkBoundariesWin() async throws {
        for duringEnrollment in [false, true] {
            for deletion in [false, true] {
                let container = try container()
                let mutate = {
                    try support.update(container) { scan, context in
                        if deletion { try context.ensurePendingCloudDeletionTask(scanId: scan.id, requestingAccountID: support.support.owner, origin: .explicitUserDeletion) }
                        else { scan.commonName = "Newer local identification" }
                    }
                }
                let service = service(duringEnroll: duringEnrollment ? mutate : {}, duringRead: duringEnrollment ? {} : mutate)
                await #expect(throws: (any Error).self) { try await run(service, container) }
                try expectUnenrolled(container)
            }
        }
    }

    @Test func accountGenerationChangesAtEveryFenceRollbackAndFinishLease() async throws {
        for failAt in 1...7 {
            let container = try container()
            var checks = 0, finished = false
            let service = service(current: { checks += 1; return checks < failAt }, finish: { finished = true })
            await #expect(throws: ObservationHistoryError.accountChanged) { try await run(service, container) }
            #expect(finished)
            try expectUnenrolled(container)
        }
    }

    @Test func unfinishedIngestionAndReviewDeferBeforeRemoteImport() async throws {
        for kind in [OfflineJobKind.scanIngestion, .identificationReviewSync] {
            for status in ["pending", "running", "future-status"] {
                let container = try container()
                try support.update(container) { scan, context in
                    let job = OfflineJobRecord(id: "fixture-enrollment", kind: kind, subjectId: scan.id)
                    job.statusRaw = status; context.insert(job)
                }
                var called = false
                await #expect(throws: (any Error).self) { try await run(service(duringEnroll: { called = true }), container) }
                #expect(!called)
                try expectUnenrolled(container)
            }
        }
        let container = try container()
        try support.update(container) { scan, context in context.insert(OfflineQueuedScan(id: scan.id)) }
        await #expect(throws: Failure.pendingWork) { try await run(service(), container) }
        try expectUnenrolled(container)
    }

    @Test func legacyOfflineCorrectionAndUndoAreNotOverwritten() async throws {
        for undo in [false, true] {
            let container = try container()
            try support.update(container) { scan, _ in
                scan.confirmedSpeciesIdentityData = nil
                if !undo { scan.userIdentificationOverride = "Offline correction" }
            }
            await #expect(throws: ObservationHistoryStateSyncService.AdmissionError.pendingReview) {
                try await run(service(state: support.fixture(revision: 1, rejected: undo)), container)
            }
            try expectUnenrolled(container)
        }
    }
}
