import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationReanalysisPersistenceTests {
    let fixture = ObservationPublicationPersistenceTests()
    let child = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
    let media = UUID(uuidString: "20000000-0000-4000-8000-000000000002")!

    func intent(text: String = "Leaf") throws -> ObservationReanalysisIntent {
        let photo = ObservationEvidenceUpload.Reference(mediaID: media, contentType: "image/jpeg", byteCount: 3,
            sha256: "039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81")
        return try .init(ownerID: fixture.owner, request: .init(observationID: fixture.observation, analysisID: child,
            sourceAnalysisID: fixture.analysis, processor: .gemini, evidence: [.description(text), .image(photo)]))
    }

    func stage(_ container: ModelContainer) throws -> ObservationReanalysisPersistence.Stored {
        try ObservationReanalysisPersistence.stage(intent(), container: container, isCurrent: { true })
    }

    func stored(_ container: ModelContainer) throws -> (ModelContext, OfflineQueuedScan, OfflineJobRecord) {
        let context = ModelContext(container)
        let row = try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
        let savedJob = try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: row.id))
        let job = try #require(savedJob)
        return (context, row, job)
    }

    @Test func stagePersistsQualifiedIdentityAndLeavesSelectionAlone() throws {
        let container = try fixture.container(), original = try intent()
        let result = try stage(container)
        let (context, row, job) = try stored(container)
        #expect(result.intent == original && result.status == .needsAttention)
        #expect(row.work == .reanalysis(original.identity) && !row.permitsOrdinaryInference)
        #expect(row.inferenceImagePaths == original.photoPaths && row.queueNeedsAttention)
        #expect(row.queueNextRetryAt == nil && job.nextRunAt == nil)
        #expect(job.kind == .observationReanalysisSync && job.kind != .scanIngestion)
        #expect(try ObservationReanalysisPersistence.restore(row: row, job: job).intent == original)
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(parent.selectedAnalysisID == fixture.analysis.uuidString.lowercased())
        #expect(parent.observationStateRevision == 3 && parent.analysisRecords?.count == 1)
    }

    @Test func exactReplayPreservesTerminalAndAttemptState() throws {
        let container = try fixture.container(); _ = try stage(container)
        let (context, _, job) = try stored(container)
        job.status = .complete; job.attemptCount = 7; try context.save()
        let replay = try stage(container)
        #expect(replay.isTerminal && replay.status == .complete)
        let (_, _, fresh) = try stored(container)
        #expect(fresh.attemptCount == 7 && fresh.status == .complete)
        #expect(throws: (any Error).self) {
            try ObservationReanalysisPersistence.stage(intent(text: "Changed"), container: container, isCurrent: { true })
        }
    }

    @Test func saveFailureAndAccountChangeRollBackBothRows() throws {
        for changeAccount in [false, true] {
            let container = try fixture.container(); var current = true
            #expect(throws: (any Error).self) {
                try ObservationReanalysisPersistence.stage(intent(), container: container, isCurrent: { current },
                    validateNew: { _ in if changeAccount { current = false } },
                    save: { _ in throw CocoaError(.fileWriteUnknown) })
            }
            let context = ModelContext(container)
            #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
        }
    }

    @Test(arguments: ["missing-job", "missing-row", "owner", "source", "kind", "path", "metadata", "status"])
    func damagedIdentityNeverReconstructsOrRevives(field: String) throws {
        let container = try fixture.container(); _ = try stage(container)
        let (context, row, job) = try stored(container)
        switch field {
        case "missing-job": context.delete(job)
        case "missing-row": context.delete(row)
        case "owner": row.reanalysisOwnerAccountID = UUID().uuidString.lowercased()
        case "source": row.sourceAnalysisID = nil
        case "kind": row.workKindRaw = "ordinary"
        case "path": row.inferenceImagePaths = ["parent/photo.jpg"]
        case "metadata": job.metadataJSON = nil
        default: job.statusRaw = "future-status"
        }
        try context.save()
        #expect(throws: (any Error).self) { try stage(container) }
    }

    @Test func parentDeletionWinsAndRemovesExactMediaNamespace() throws {
        let container = try fixture.container(); _ = try stage(container)
        let context = ModelContext(container)
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let cleanup = try ObservationReanalysisErasure.removeChildren(of: parent.id, context: context)
        context.delete(parent); try context.save()
        #expect(cleanup.childIDs == [child.uuidString.lowercased()])
        #expect(cleanup.mediaPaths == (try intent().photoPaths.map { URL.documentsDirectory.appendingPathComponent($0).path }))
        #expect(throws: (any Error).self) { try stage(container) }
        let receipt = try #require(try ModelContext(container).fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(child)))
        #expect(try ObservationReanalysisErasureReceipt.restore(receipt).parentID == fixture.observation)
    }

    @Test func historicalSourceDoesNotNeedToBeSelected() throws {
        let container = try fixture.container(), context = ModelContext(container)
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let selected = UUID().uuidString.lowercased()
        parent.selectedAnalysisID = selected; try context.save()
        _ = try stage(container)
        let fresh = try #require(ModelContext(container).fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(fresh.selectedAnalysisID == selected && fresh.observationStateRevision == 3)
    }

    @Test(arguments: ["owner", "source", "deletion", "hold", "child-scan", "child-job"])
    func freshAdmissionRejectsMissingAuthorityAndIdentityCollision(reason: String) throws {
        let container = try fixture.container(), context = ModelContext(container)
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        switch reason {
        case "owner": parent.analysisOwnerAccountID = UUID().uuidString.lowercased()
        case "source": context.delete(try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first))
        case "deletion": context.insert(PendingCloudDeletionTask(scanId: parent.id))
        case "hold": _ = try ObservationHistoryEnrollmentIntent.stage(observationID: fixture.observation, ownerID: fixture.owner, context: context)
        case "child-scan": context.insert(LocalScanRecord(id: child.uuidString, speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture"))
        default: context.insert(OfflineJobRecord(id: OfflineQueueManager.scanIngestionJobId(scanId: child.uuidString.lowercased()), kind: .scanIngestion, status: .complete))
        }
        try context.save()
        #expect(throws: (any Error).self) { try stage(container) }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
    }

    @Test func diskReopenRetainsExactRequestAndOwner() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store.sqlite")
        do { let container = try fixture.container(url: url); _ = try stage(container) }
        let reopened = try fixture.container(url: url, seed: false)
        #expect(try stage(reopened).intent == intent())
    }

    @Test func intentRejectsUnknownFieldsBooleanVersionAndChangedRequestBytes() throws {
        let original = try intent(), data = try original.storedData()
        #expect(try ObservationReanalysisIntent.decode(data) == original)
        let row = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for patch: [String: Any] in [["version": true], ["owner_id": fixture.owner.uuidString],
                                    ["request_base64": "invalid"], ["extra": true]] {
            // The fixture UUID is all digits, so uppercase is not a distinct spelling.
            var modified = row.merging(patch) { _, new in new }
            if patch["owner_id"] != nil { modified["owner_id"] = "not-a-uuid" }
            #expect(throws: (any Error).self) {
                try ObservationReanalysisIntent.decode(JSONSerialization.data(withJSONObject: modified))
            }
        }
    }

    @Test func reanalysisDoesNotRestoreLegacyFundingBlocker() throws {
        let container = try fixture.container(); _ = try stage(container)
        let manager = OfflineQueueManager.shared, previous = manager.modelContext
        manager.modelContext = ModelContext(container)
        EntitlementManager.shared.resetForTesting(userID: fixture.owner)
        defer {
            EntitlementManager.shared.resetForTesting()
            manager.modelContext = previous
        }
        manager.restoreFundingReservationsForCurrentAccount()
        #expect(!EntitlementManager.shared.fundingBlockerScanIds.contains(child.uuidString.lowercased()))
    }

    @Test func heldAndDamagedChildrenCannotScheduleLegacyWake() throws {
        let container = try fixture.container(); _ = try stage(container)
        let (context, row, job) = try stored(container)
        row.queueNeedsAttention = false; row.queueNextRetryAt = Date()
        job.status = .waiting; job.nextRunAt = Date(); try context.save()
        let manager = OfflineQueueManager.shared, previous = manager.modelContext
        manager.modelContext = context
        defer { manager.modelContext = previous }
        let scheduler = OfflineJobScheduler(drainOperations: .init(reconcileFunding: { _ in }, syncPendingScans: { _ in },
            replayInference: { _ in }, replayFieldTripProgress: { _ in }, syncPendingDeletions: { _ in }, syncCollections: { _ in }))
        #expect(scheduler.nextPersistedWakeDate(using: manager) == nil)
        job.kind = .scanIngestion; try context.save()
        #expect(scheduler.nextPersistedWakeDate(using: manager) == nil)
        row.sourceAnalysisID = nil; try context.save()
        #expect(scheduler.nextPersistedWakeDate(using: manager) == nil)
        context.delete(row); try context.save()
        #expect(scheduler.nextPersistedWakeDate(using: manager) == nil)
        job.kind = .observationReanalysisSync; job.id = "library-details:damaged-reanalysis"
        try context.save()
        #expect(scheduler.nextPersistedWakeDate(using: manager) == nil)
    }
    @Test func boundDispatchEnvelopeIsClosedAndCannotConfuseDraftVersions() throws {
        let original = try intent(), ready = try original.storedData()
        let row = try #require(JSONSerialization.jsonObject(with: ready) as? [String: Any])
        #expect(try ObservationReanalysisIntent.Bound.decode(ready).dispatch == .ready)
        for patch: [String: Any] in [
            ["version": 6], ["dispatch_state": "legacy_unknown"], ["dispatch_attempt": 1],
            ["dispatch_state": "consumed", "dispatch_attempt": NSNull()],
            ["dispatch_state": "consumed", "dispatch_attempt": true],
            ["dispatch_state": "consumed", "dispatch_attempt": 0],
            ["dispatch_state": "consumed", "dispatch_attempt": 1.5]
        ] {
            let data = try JSONSerialization.data(withJSONObject: row.merging(patch) { _, new in new })
            #expect(throws: (any Error).self) { try ObservationReanalysisIntent.Bound.decode(data) }
        }
        let consumed = try ObservationReanalysisIntent.Bound(intent: original, dispatch: .consumed(attempt: 2)).data()
        #expect(try ObservationReanalysisIntent.decode(consumed) == original)
        #expect(try ObservationReanalysisIntent.Bound.decode(consumed).dispatch == .consumed(attempt: 2))
    }

}

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationReanalysisDraftTests {
    let fixture = ObservationReanalysisPersistenceTests()

    func draft(text: String = "Leaf") throws -> ObservationReanalysisDraft {
        let intent = try fixture.intent(text: text)
        return try .init(identity: intent.identity, evidence: intent.request.evidence)
    }

    @Test func offlineDraftHasNoRecipientAndBindsOnceWithoutChangingFilesOrSelection() throws {
        let container = try fixture.fixture.container(), original = try draft()
        let bytes = try original.storedData()
        let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(Set(object.keys) == ["version", "phase", "owner_id", "observation_id", "analysis_id", "source_analysis_id", "evidence_manifest"])
        #expect(try ObservationReanalysisDraft.decode(bytes) == original)
        #expect(throws: (any Error).self) { try ObservationReanalysisIntent.decode(bytes) }
        let staged = try ObservationReanalysisPersistence.stageDraft(original, container: container, isCurrent: { true })
        guard case let .draft(saved) = staged else { Issue.record("Draft became bound without preflight"); return }
        #expect(saved == original)
        let bound = try ObservationReanalysisPersistence.bindDraft(original, processor: .gemini, container: container, isCurrent: { true })
        #expect(bound.intent == (try fixture.intent()))
        let (context, row, job) = try fixture.stored(container)
        #expect(row.inferenceImagePaths == original.photoPaths && job.status == .needsAttention && job.nextRunAt == nil)
        #expect(row.queueNeedsAttention && job.attemptCount == 0 && job.lastAttemptAt == nil)
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(parent.selectedAnalysisID == fixture.fixture.analysis.uuidString.lowercased() && parent.observationStateRevision == 3)
        #expect(try ObservationReanalysisPersistence.bindDraft(original, processor: .gemini, container: container, isCurrent: { true }).intent == bound.intent)
        #expect(throws: (any Error).self) {
            try ObservationReanalysisPersistence.bindDraft(original, processor: .openAI, container: container, isCurrent: { true })
        }
        #expect(throws: (any Error).self) {
            try ObservationReanalysisPersistence.bindDraft(draft(text: "Changed"), processor: .gemini, container: container, isCurrent: { true })
        }
    }

    @Test func staleDraftReplayRecoversExactBoundTerminalWithoutRevival() throws {
        let container = try fixture.fixture.container(), original = try draft()
        _ = try ObservationReanalysisPersistence.stageDraft(original, container: container, isCurrent: { true })
        let bound = try ObservationReanalysisPersistence.bindDraft(original, processor: .openAI, container: container, isCurrent: { true })
        let (context, _, job) = try fixture.stored(container)
        job.status = .complete; job.attemptCount = 3; try context.save()
        let replay = try ObservationReanalysisPersistence.stageDraft(original, container: container, isCurrent: { true })
        guard case let .bound(saved) = replay else { Issue.record("Bound work downgraded to draft"); return }
        #expect(saved.isTerminal && saved.intent == bound.intent)
        let same = try ObservationReanalysisPersistence.bindDraft(original, processor: .openAI, container: container, isCurrent: { true })
        #expect(same.isTerminal && same.intent.request.body == bound.intent.request.body)
        let (_, _, fresh) = try fixture.stored(container)
        #expect(fresh.attemptCount == 3 && fresh.status == .complete)
    }

    @Test func recoveryOnlyAndSaveFailureLeaveTheDraftIntact() throws {
        let container = try fixture.fixture.container(), original = try draft()
        _ = try ObservationReanalysisPersistence.stageDraft(original, container: container, isCurrent: { true })
        for processor in [IdentificationRecipientExpectation.recoveryOnly, .gemini] {
            #expect(throws: (any Error).self) {
                try ObservationReanalysisPersistence.bindDraft(original, processor: processor, container: container, isCurrent: { true },
                    save: { _ in throw CocoaError(.fileWriteUnknown) })
            }
            let (_, _, job) = try fixture.stored(container)
            let text = try #require(job.metadataJSON)
            #expect(try ObservationReanalysisDraft.decode(Data(text.utf8)) == original)
        }
    }

    @Test(arguments: ["parent-deleted", "owner", "source", "job-missing", "row-missing", "paths", "metadata", "attempt", "terminal"])
    func bindingRejectsDeletionAndDamagedOrPreviouslyAttemptedDrafts(_ reason: String) throws {
        let container = try fixture.fixture.container(), original = try draft()
        _ = try ObservationReanalysisPersistence.stageDraft(original, container: container, isCurrent: { true })
        let (context, row, job) = try fixture.stored(container)
        switch reason {
        case "parent-deleted": context.insert(PendingCloudDeletionTask(scanId: original.identity.observationID.uuidString.lowercased()))
        case "owner": row.reanalysisOwnerAccountID = UUID().uuidString.lowercased()
        case "source": context.delete(try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first))
        case "job-missing": context.delete(job)
        case "row-missing": context.delete(row)
        case "paths": row.inferenceImagePaths = ["parent/photo.jpg"]
        case "metadata": job.metadataJSON = nil
        case "attempt": job.attemptCount = 1
        default: job.status = .complete
        }
        try context.save()
        #expect(throws: (any Error).self) {
            try ObservationReanalysisPersistence.bindDraft(original, processor: .gemini, container: container, isCurrent: { true })
        }
    }

    @Test func stagingAndBindingAccountFencesRollbackAllChanges() throws {
        let container = try fixture.fixture.container(), original = try draft()
        var checks = 0
        #expect(throws: (any Error).self) {
            try ObservationReanalysisPersistence.stageDraft(original, container: container, isCurrent: { checks += 1; return checks == 1 })
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
        _ = try ObservationReanalysisPersistence.stageDraft(original, container: container, isCurrent: { true })
        checks = 0
        #expect(throws: (any Error).self) {
            try ObservationReanalysisPersistence.bindDraft(original, processor: .gemini, container: container, isCurrent: { checks += 1; return checks == 1 })
        }
        let (_, _, job) = try fixture.stored(container)
        let metadata = try #require(job.metadataJSON)
        #expect(try ObservationReanalysisDraft.decode(Data(metadata.utf8)) == original)
    }

    @Test func exactDraftDecoderRejectsUnknownPhaseAndRecipientInjection() throws {
        let original = try draft()
        let row = try #require(JSONSerialization.jsonObject(with: original.storedData()) as? [String: Any])
        for patch: [String: Any] in [["version": true], ["version": 3], ["phase": "bound"], ["expected_processor_permission": "openai"],
                                    ["analysis_id": original.identity.observationID.uuidString.lowercased()], ["owner_id": "invalid"],
                                    ["request_base64": "e30="]] {
            #expect(throws: (any Error).self) {
                try ObservationReanalysisDraft.decode(JSONSerialization.data(withJSONObject: row.merging(patch) { _, new in new }))
            }
        }
        #expect(throws: (any Error).self) { try ObservationReanalysisDraft.decode(Data(repeating: 32, count: 1_044_481)) }
        #expect(throws: (any Error).self) { try ObservationReanalysisDraft(identity: original.identity, evidence: []) }
    }

}
