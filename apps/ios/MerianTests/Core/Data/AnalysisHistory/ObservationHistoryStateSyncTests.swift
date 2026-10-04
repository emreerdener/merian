import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized)
struct ObservationHistoryStateSyncTests {
    let support = ObservationHistorySyncTests()
    let analysisID = "00000000-0000-4000-8000-000000000002"
    typealias Failure = ObservationHistoryStateSyncService.AdmissionError

    func fixture(revision: Int = 11, rejected: Bool = false) throws -> Data {
        var value = try ObservationHistoryStateTests().fixture()
        value["state_revision"] = revision
        if rejected {
            var item = value["analysis"] as! [String: Any]
            var review = item["review_snapshot"] as! [String: Any]
            review["ai_identification_review"] = ["version": 1, "revision": 2, "state": "ai_rejected",
                "origin_scan_id": support.observation,
                "origin_identification": ["scientific_name": "Saved fixture", "common_name": NSNull()],
                "operation_id": NSNull(), "operation_digest": NSNull(), "community": NSNull()] as [String: Any]
            item["review_snapshot"] = review
            item["review_revision"] = 1
            value["analysis"] = item
        }
        return try support.bytes(value)
    }

    func container() throws -> ModelContainer {
        let container = try support.container()
        try update(container) { scan, _ in
            scan.selectedAnalysisID = analysisID
            scan.aiIdentificationReviewData = nil
            scan.userIdentificationOverride = nil
            scan.userConfirmedIdentification = false
            scan.confirmedSpeciesIdentityData = try ConfirmedSpeciesReview(revision: 0, identity: nil,
                override: nil, confirmed: false, speciesID: nil, state: .unreviewed).storedData()
            scan.customTags = ["Preserved tag"]
            scan.fieldNotes = "Preserved private note"
        }
        return container
    }

    func update(_ container: ModelContainer, _ action: (LocalScanRecord, ModelContext) throws -> Void) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        try action(scan, context)
        try context.save()
    }

    func service(data: Data, current: @escaping () -> Bool = { true },
                 duringFetch: @escaping () throws -> Void = {}, finish: @escaping () -> Void = {}) -> ObservationHistoryStateSyncService {
        var cloud = support.client(fetch: { _ in throw ObservationHistoryError.unavailable }, current: current, finish: finish)
        cloud.fetchState = { request in
            #expect(request.observation_id == support.observation)
            #expect(request.analysis_id == nil)
            try duringFetch()
            return data
        }
        return .init(cloud: cloud)
    }

    @Test func atomicAuthorityRefreshPreservesIdentificationAndPrivateDetailsAndReplays() async throws {
        let container = try container(), service = service(data: try fixture(rejected: true))
        #expect(try await service.syncSelected(observationID: support.observation, container: container) == 11)
        #expect(try await service.syncSelected(observationID: support.observation, container: container) == 11)
        let context = ModelContext(container)
        let scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(scan.localAIIdentificationReview.authority?.state == .aiRejected)
        #expect(scan.observationStateRevision == 11)
        #expect(scan.selectedAnalysisID == analysisID)
        #expect(scan.scientificName == "Preserved correction")
        #expect(scan.customTags == ["Preserved tag"])
        #expect(scan.fieldNotes == "Preserved private note")
        #expect(try support.count(container) == 1)
        let state = try ObservationHistoryState.decode(fixture(rejected: true),
            request: .init(observation_id: support.observation, analysis_id: nil), ownerID: support.owner)
        #expect(scan.analysisRecords?.first?.resultSnapshotData == state.result.bytes)
        let cached = try #require(scan.analysisRecords?.first?.state)
        #expect(cached.reviewSnapshotData == state.review.data)
        #expect(cached.reviewRevision == state.reviewRevision && cached.observationStateRevision == state.revision)
        // This fixture is imported V3: never manufacture its missing provider result.
        #expect(cached.displaySnapshotData == nil)
    }

    @Test func staleAndEqualConflictingResponsesDoNotWrite() async throws {
        for (revision, rejected, error) in [(9, false, Failure.staleRevision), (10, true, Failure.conflictingRevision)] {
            let container = try container(), service = service(data: try fixture(revision: revision, rejected: rejected))
            await #expect(throws: error) { try await service.syncSelected(observationID: support.observation, container: container) }
            #expect(try support.count(container) == 0)
        }
    }

    @Test func equalIdenticalStateCanHydrateMissingImmutableResult() async throws {
        let container = try container(), service = service(data: try fixture(revision: 10))
        _ = try await service.syncSelected(observationID: support.observation, container: container)
        #expect(try support.count(container) == 1)
    }

    @Test func differentSelectedAnalysisRequiresProjectionBeforeAnyWrite() async throws {
        let container = try container()
        try update(container) { scan, _ in scan.selectedAnalysisID = "00000000-0000-4000-8000-000000000099" }
        let service = service(data: try fixture())
        await #expect(throws: Failure.selectionProjectionRequired) {
            try await service.syncSelected(observationID: support.observation, container: container)
        }
        #expect(try support.count(container) == 0)
    }

    @Test func everyUnfinishedReviewJobDefersBeforeFetchIncludingUnknownStatus() async throws {
        for status in ["pending", "running", "waiting", "needsAttention", "future-status"] {
            let container = try container()
            try update(container) { scan, context in
                let job = OfflineJobRecord(id: "fixture-review", kind: .identificationReviewSync, subjectId: scan.id.uppercased())
                job.statusRaw = status
                context.insert(job)
            }
            var fetched = false
            let service = service(data: try fixture(), duringFetch: { fetched = true })
            await #expect(throws: Failure.pendingReview) { try await service.syncSelected(observationID: support.observation, container: container) }
            #expect(!fetched)
        }
    }

    @Test func optimisticReviewAndMalformedLocalAuthorityArePreserved() async throws {
        for data in [try LocalAIIdentificationReview(optimisticState: .aiRejected).storedData(), Data("invalid".utf8)] {
            let container = try container()
            try update(container) { scan, _ in scan.aiIdentificationReviewData = data }
            let service = service(data: try fixture())
            await #expect(throws: Failure.pendingReview) { try await service.syncSelected(observationID: support.observation, container: container) }
            #expect(try support.count(container) == 0)
        }
    }

    @Test func localReviewChangeDuringFetchWins() async throws {
        let container = try container()
        let service = service(data: try fixture(), duringFetch: {
            try update(container) { scan, _ in scan.userIdentificationOverride = "New local intent" }
        })
        await #expect(throws: Failure.pendingReview) { try await service.syncSelected(observationID: support.observation, container: container) }
        #expect(try support.count(container) == 0)
        #expect(try ModelContext(container).fetch(FetchDescriptor<LocalScanRecord>()).first?.userIdentificationOverride == "New local intent")
    }

    @Test func pendingDeletionAndOwnerChangeDuringFetchWin() async throws {
        for ownerChanged in [false, true] {
            let container = try container()
            let service = service(data: try fixture(), duringFetch: {
                try update(container) { scan, context in
                    if ownerChanged { scan.analysisOwnerAccountID = "00000000-0000-4000-8000-000000000099" }
                    else { try context.ensurePendingCloudDeletionTask(scanId: support.observation, requestingAccountID: support.owner, origin: .explicitUserDeletion) }
                }
            })
            await #expect(throws: ownerChanged ? ObservationHistoryError.accountChanged : .deleted) {
                try await service.syncSelected(observationID: support.observation, container: container)
            }
            #expect(try support.count(container) == 0)
        }
    }

    @Test func finalAccountFenceRollsBackAuthorityRevisionAndResultTogether() async throws {
        let container = try container()
        var checks = 0, finished = false
        let service = service(data: try fixture(rejected: true), current: { checks += 1; return checks < 4 }, finish: { finished = true })
        await #expect(throws: ObservationHistoryError.accountChanged) {
            try await service.syncSelected(observationID: support.observation, container: container)
        }
        #expect(finished)
        #expect(try support.count(container) == 0)
        let scan = try #require(ModelContext(container).fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(scan.observationStateRevision == 10)
        #expect(scan.aiIdentificationReviewData == nil)
    }

    @Test func oldLegacyCorrectionWithoutAcknowledgementIsNeverErased() async throws {
        let container = try container()
        try update(container) { scan, _ in
            scan.confirmedSpeciesIdentityData = nil
            scan.userIdentificationOverride = "Existing legacy correction"
        }
        let service = service(data: try fixture())
        await #expect(throws: Failure.pendingReview) { try await service.syncSelected(observationID: support.observation, container: container) }
        #expect(try support.count(container) == 0)
    }

    @Test func localVerifiedIntentWithoutOutboxStillDefers() async throws {
        let container = try container()
        try update(container) { scan, _ in
            scan.confirmedSpeciesIdentityData = try ConfirmedSpeciesReview(revision: 1, identity: nil,
                override: nil, confirmed: false, speciesID: nil, state: .unreviewed).storedData()
            scan.userConfirmedIdentification = true
            scan.userReviewState = .aiConfirmed
        }
        let service = service(data: try fixture())
        await #expect(throws: Failure.pendingReview) { try await service.syncSelected(observationID: support.observation, container: container) }
    }

    @Test func revisionedSpeciesClearIsDurableAndEqualReplayWorks() async throws {
        let container = try container()
        try update(container) { scan, _ in
            scan.confirmedSpeciesIdentityData = try ConfirmedSpeciesReview(revision: 1, identity: nil,
                override: nil, confirmed: false, speciesID: nil, state: .unreviewed).storedData()
        }
        var value = try ObservationHistoryStateTests().fixture()
        value["state_revision"] = 11
        var item = value["analysis"] as! [String: Any]
        var review = item["review_snapshot"] as! [String: Any]
        review["confirmed_species_identity_revision"] = 2
        item["review_snapshot"] = review
        value["analysis"] = item
        let service = service(data: try support.bytes(value))
        _ = try await service.syncSelected(observationID: support.observation, container: container)
        _ = try await service.syncSelected(observationID: support.observation, container: container)
        let scan = try #require(ModelContext(container).fetch(FetchDescriptor<LocalScanRecord>()).first)
        let stored = try #require(try ConfirmedSpeciesReview.restoring(scan.confirmedSpeciesIdentityData))
        #expect(stored.revision == 2)
        #expect(stored.identity == nil)
    }

    @Test func higherObservationRevisionCannotRegressReviewAuthority() async throws {
        let container = try container()
        let first = service(data: try fixture(rejected: true))
        _ = try await first.syncSelected(observationID: support.observation, container: container)
        let staleReview = service(data: try fixture(revision: 12))
        await #expect(throws: Failure.staleRevision) {
            try await staleReview.syncSelected(observationID: support.observation, container: container)
        }
        let scan = try #require(ModelContext(container).fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(scan.observationStateRevision == 11)
        #expect(scan.localAIIdentificationReview.authority?.state == .aiRejected)
    }

    @Test func conflictingImmutableResultCannotPartiallyApplyReview() async throws {
        let container = try container(), original = try fixture(revision: 10)
        _ = try await service(data: original).syncSelected(observationID: support.observation, container: container)
        var value = try #require(JSONSerialization.jsonObject(with: fixture(rejected: true)) as? [String: Any])
        var item = value["analysis"] as! [String: Any]
        item["snapshot"] = (item["snapshot"] as! String) + " "
        value["analysis"] = item
        let conflict = service(data: try support.bytes(value))
        await #expect(throws: ObservationHistoryError.resultConflict) {
            try await conflict.syncSelected(observationID: support.observation, container: container)
        }
        let scan = try #require(ModelContext(container).fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(scan.observationStateRevision == 10)
        #expect(scan.aiIdentificationReviewData == nil)
    }

    @Test func unrepresentableLegacyAuthorityCannotLoseItsRevision() async throws {
        let container = try container()
        var value = try ObservationHistoryStateTests().fixture()
        value["state_revision"] = 11
        var item = value["analysis"] as! [String: Any]
        var review = item["review_snapshot"] as! [String: Any]
        review["confirmed_species_identity_revision"] = 2
        review["user_confirmed_identification"] = NSNull()
        item["review_snapshot"] = review
        value["analysis"] = item
        let service = service(data: try support.bytes(value))
        await #expect(throws: Failure.authorityStorageRequired) {
            try await service.syncSelected(observationID: support.observation, container: container)
        }
        #expect(try support.count(container) == 0)
    }

    @Test func ambiguousLegacyOfflineUndoCannotBeOverwrittenByNewerRemoteReview() async throws {
        let container = try container()
        try update(container) { scan, _ in scan.confirmedSpeciesIdentityData = nil }
        let service = service(data: try fixture(rejected: true))
        await #expect(throws: Failure.pendingReview) {
            try await service.syncSelected(observationID: support.observation, container: container)
        }
        #expect(try support.count(container) == 0)
        let scan = try #require(ModelContext(container).fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(scan.observationStateRevision == 10)
        #expect(scan.aiIdentificationReviewData == nil)
        #expect(scan.userReviewState == .unreviewed)
    }
}
