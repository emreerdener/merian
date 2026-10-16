import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite("Reanalysis Parent Erasure", .sharedProcessState(.offlineQueueManager))
struct ObservationReanalysisErasureTests {
    private let parent = "00000000-0000-4000-8000-000000000801"
    private let other = "00000000-0000-4000-8000-000000000802"

    private func context() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container); context.autosaveEnabled = false
        return context
    }

    private func child(_ context: ModelContext, kind: String = "reanalysis", parentID: String? = nil) -> OfflineQueuedScan {
        let row = OfflineQueuedScan(id: UUID().uuidString.lowercased(), capturedMediaJSON: "[]")
        row.workKindRaw = kind
        row.parentObservationID = parentID ?? parent
        // Deliberately absent source/owner and damaged job JSON: erasure must
        // not use dispatch eligibility or optional metadata as its index.
        context.insert(row)
        context.insert(OfflineJobRecord(id: OfflineQueueManager.scanIngestionJobId(scanId: row.id),
            kind: .scanIngestion, subjectId: "damaged", metadataJSON: "not-json"))
        return row
    }

    @Test func exactParentErasesDamagedChildrenWithoutTouchingOtherParents() throws {
        let context = try context()
        let targets = [child(context), child(context, kind: "ordinary"), child(context, kind: "unknown")]
        let sibling = child(context, parentID: other)
        let malformed = child(context, parentID: "not-a-uuid")
        let detached = child(context); detached.parentObservationID = nil
        try context.save()
        let ids = Set(targets.map(\.id))
        let cleanup = try ObservationReanalysisErasure.removeChildren(of: parent.uppercased(), context: context)
        #expect(Set(cleanup.childIDs) == ids)
        try context.save()
        #expect(Set(try context.fetch(FetchDescriptor<OfflineQueuedScan>()).map(\.id)) == Set([sibling.id, malformed.id, detached.id]))
        #expect(try context.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 6)
        #expect(try ObservationReanalysisErasure.removeChildren(of: parent, context: context).childIDs.isEmpty)
    }

    @Test func rollbackPreservesParentChildAndJob() throws {
        let context = try context()
        let record = LocalScanRecord(id: parent, speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture")
        context.insert(record)
        let row = child(context)
        let childID = row.id
        try context.save()
        _ = try ObservationReanalysisErasure.removeChildren(of: parent, context: context)
        context.delete(record)
        context.rollback()
        let read = ModelContext(context.container)
        #expect(try read.fetchCount(FetchDescriptor<LocalScanRecord>()) == 1)
        #expect(try read.fetch(FetchDescriptor<OfflineQueuedScan>()).first?.id == childID)
        #expect(try read.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 1)
    }

    @Test func onlyExactPrivateChildFilesAreReturnedForPostCommitCleanup() throws {
        let context = try context()
        let row = child(context)
        let owned = "ReanalysisQueue/\(row.id)/photo.webp"
        row.inferenceImagePaths = [owned, "parent.webp", "ReanalysisQueue/\(other)/photo.webp",
            "ReanalysisQueue/\(row.id)/../parent.webp", "/private/parent.webp", "https://example.invalid/photo.webp"]
        try context.save()
        let cleanup = try ObservationReanalysisErasure.removeChildren(of: parent, context: context)
        #expect(cleanup.mediaPaths == [URL.documentsDirectory.appendingPathComponent(owned).path])
        #expect(ObservationReanalysisErasure.ownedFile("ReanalysisQueue/\(row.id)//", childID: row.id) == nil)
        context.rollback()
    }

    @Test func nonBiologicalDeletionCommitsChildrenWithParentAndOnlyOneCloudIntent() async throws {
        let context = try context()
        let record = LocalScanRecord(id: parent, speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture", isBiological: false)
        context.insert(record)
        let row = child(context, kind: "unknown"); let id = row.id
        try context.save()
        let actor = BackgroundDatabaseActor(modelContainer: context.container)
        let result = try await actor.bulkDeleteNonBiologicalScansWithQueueCleanup(payloads: [.init(id: parent, mediaPaths: [])])
        #expect(result.childIDs == [id])
        let read = ModelContext(context.container)
        #expect(try read.fetchCount(FetchDescriptor<LocalScanRecord>()) == 0)
        #expect(try read.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try read.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: id)) == nil)
        #expect(try read.fetch(FetchDescriptor<PendingCloudDeletionTask>()).map(\.scanId) == [parent])
    }

    @Test func automaticLegacyPurgeAndPermissionRecoveryLeaveHeldChildrenAlone() throws {
        let context = try context()
        let row = child(context)
        row.scanStateRaw = ScanQueueState.failed.rawValue
        let owner = UUID()
        let job = try #require(try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: row.id)))
        job.status = .needsAttention
        job.lastErrorCode = "ai_openai_consent_required"
        job.subjectId = row.id
        job.metadataJSON = OfflineScanJobMetadataContract.json(generation: nil,
            funding: ScanFundingReservation(accountId: owner, scanId: row.id, source: .complimentaryPro))
        try context.save()
        let queue = OfflineQueueManager.shared; let previous = queue.modelContext
        defer { queue.modelContext = previous }
        queue.modelContext = context
        #expect(!queue.ownsOpenAIConsentPausedScan(scanId: row.id, accountId: owner))
        queue.purgeSoftDeletedRecords()
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(job.status == .needsAttention)
    }

    @Test func directDeletionCommitsChildrenAndCancelsOnlyRemovedRuntimeOwners() async throws {
        let context = try context()
        let record = LocalScanRecord(id: parent, speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture")
        context.insert(record)
        let row = child(context); let id = row.id
        let retained = child(context, parentID: other); let retainedID = retained.id
        try context.save()
        let queue = OfflineQueueManager.shared
        let previousContext = queue.modelContext; let previousOnline = queue.isOnline
        defer { queue.modelContext = previousContext; queue.isOnline = previousOnline; queue.latestUploadGenerations[id] = nil; queue.latestUploadGenerations[retainedID] = nil }
        queue.modelContext = context; queue.isOnline = false
        let generation = UUID(); queue.latestUploadGenerations[id] = generation
        let retainedGeneration = UUID(); queue.latestUploadGenerations[retainedID] = retainedGeneration
        await ScanRepository.shared.eradicateScan(record: record, modelContext: context, allowsMutation: { true })?.value
        #expect(try context.fetch(FetchDescriptor<OfflineQueuedScan>()).map(\.id) == [retainedID])
        #expect(queue.latestUploadGenerations[id] != generation)
        await queue.finishReanalysisErasure([retainedID], in: context.container)
        #expect(queue.latestUploadGenerations[retainedID] == retainedGeneration)
    }
}

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ReanalysisRetirementSettlementTests {
    typealias Store = ObservationReanalysisExecutionStore
    let staging = ReanalysisRetirementStagingTests()

    func claim(_ container: ModelContainer) throws -> Store.RetirementClaim {
        let original = try staging.consumed(container)
        let saved = try Store.stageRetirement(original.snapshot, status: staging.status(original.intent), operationID: staging.operation,
            now: staging.execution.now, container: container, isCurrent: { true })
        return try Store.claimRetirement(saved, admission: .initial, now: staging.execution.now, container: container, isCurrent: { true })
    }

    func proof(_ claim: Store.RetirementClaim) throws -> ObservationAnalysisRetirementReceipt {
        var object = try #require(JSONSerialization.jsonObject(with: claim.request.body) as? [String: Any])
        object["state"] = "retired_before_dispatch"
        return try .init(data: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), request: claim.request)
    }

    @Test func proofRetiresOnlyExactChildAndRemainsAfterCleanup() throws {
        let container = try staging.execution.fixture.fixture.container(), active = try claim(container), answer = try proof(active)
        let receipt = try Store.completeRetirement(active, proof: answer, container: container, isCurrent: { true })
        #expect(receipt.retirementProof == answer && receipt.retirementOwnerID == active.snapshot.intent.ownerID)
        let context = ModelContext(container)
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 1)
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(parent.selectedAnalysisID == staging.execution.fixture.fixture.analysis.uuidString.lowercased())
        #expect(try ObservationReanalysisErasurePersistence.validate(receipt, container: container, isCurrent: { true }, complete: true))
        #expect(try Store.completeRetirement(active, proof: answer, container: container, isCurrent: { true }) == receipt)
        let retainedJob = try context.fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(receipt.childID))
        let retained = try #require(retainedJob)
        #expect(try ObservationReanalysisErasureReceipt.restore(retained) == receipt)
        let ordinary = ObservationReanalysisErasureReceipt(parentID: receipt.parentID, childID: receipt.childID)
        #expect(ordinary != receipt)
        #expect(throws: (any Error).self) { try ordinary.record(in: context) }
        try ordinary.recordParentErasure(in: context)
        #expect(try ObservationReanalysisErasureReceipt.restore(retained) == receipt)
    }

    @Test func holdHasNoTimerAndExplicitReplayKeepsOperationButFencesOldClaim() throws {
        let container = try staging.execution.fixture.fixture.container(), first = try claim(container)
        try Store.holdRetirement(first, now: staging.execution.now, container: container, isCurrent: { true })
        let held = try Store.read(first.snapshot.intent.identity, container: container, isCurrent: { true })
        #expect(held.status == .needsAttention && held.nextRun == nil && held.hold == .reconciliationRequired)
        #expect(try Store.candidates(ownerID: held.intent.ownerID, container: container, isCurrent: { true }).isEmpty)
        #expect(throws: (any Error).self) {
            try Store.claimRetirement(held, admission: .initial, now: staging.execution.now, container: container, isCurrent: { true })
        }
        let second = try Store.claimRetirement(held, admission: .explicitRetry, now: staging.execution.now, container: container, isCurrent: { true })
        #expect(second.request == first.request && second.snapshot.attempt == first.snapshot.attempt + 1)
        #expect(second.snapshot.dispatch == first.snapshot.dispatch)
        #expect(throws: (any Error).self) { try Store.validateRetirement(first, container: container, isCurrent: { true }) }
        #expect(throws: (any Error).self) {
            try Store.completeRetirement(first, proof: proof(first), container: container, isCurrent: { true })
        }
        _ = try Store.completeRetirement(second, proof: proof(second), container: container, isCurrent: { true })
    }

    @Test(arguments: [false, true])
    func receiptSaveAmbiguityIsAtomicAndExactReplayable(_ commits: Bool) throws {
        let container = try staging.execution.fixture.fixture.container(), active = try claim(container), answer = try proof(active)
        #expect(throws: (any Error).self) {
            try Store.completeRetirement(active, proof: answer, container: container, isCurrent: { true }, save: { context in
                if commits { try context.save() }
                throw CocoaError(.fileWriteUnknown)
            })
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == (commits ? 0 : 1))
        let receipt = try Store.completeRetirement(active, proof: answer, container: container, isCurrent: { true })
        #expect(receipt.retirementProof == answer)
    }

    @Test(arguments: [true, false])
    func cancelledKnownAnswerSettlesOnlyWhileAccountScopeRemainsCurrent(_ current: Bool) async throws {
        let container = try staging.execution.fixture.fixture.container(), active = try claim(container), answer = try proof(active)
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try Store.completeRetirement(active, proof: answer, container: container, isCurrent: { current })
        }
        if current {
            #expect(try await task.value.retirementProof == answer)
        } else {
            await #expect(throws: (any Error).self) { try await task.value }
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == (current ? 0 : 1))
    }

    @Test func deletionAndDifferentOperationDenyKnownAnswer() throws {
        let container = try staging.execution.fixture.fixture.container(), active = try claim(container)
        let request = try ObservationAnalysisRetirementRequest(operationID: UUID(), execution: active.request.execution)
        var object = try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any]); object["state"] = "retired_before_dispatch"
        let wrong = try ObservationAnalysisRetirementReceipt(data: JSONSerialization.data(withJSONObject: object), request: request)
        #expect(throws: (any Error).self) { try Store.completeRetirement(active, proof: wrong, container: container, isCurrent: { true }) }
        let context = ModelContext(container)
        context.insert(PendingCloudDeletionTask(scanId: active.snapshot.intent.identity.observationID.uuidString.lowercased())); try context.save()
        #expect(throws: (any Error).self) {
            try Store.completeRetirement(active, proof: proof(active), container: container, isCurrent: { true })
        }
    }

    @Test func terminalRetirementCannotBecomeNormalCompletionAndV1CannotBecomeRetirement() throws {
        let container = try staging.execution.fixture.fixture.container(), original = try staging.consumed(container)
        let saved = try Store.stageRetirement(original.snapshot, status: staging.status(original.intent), operationID: staging.operation,
            now: staging.execution.now, container: container, isCurrent: { true })
        let active = try Store.claimRetirement(saved, admission: .initial, now: staging.execution.now, container: container, isCurrent: { true })
        let answer = try proof(active)
        _ = try Store.completeRetirement(active, proof: answer, container: container, isCurrent: { true })
        #expect(throws: (any Error).self) {
            try Store.complete(original, resultBytes: staging.execution.result(), container: container, isCurrent: { true })
        }
        let other = try staging.execution.fixture.fixture.container(), otherClaim = try claim(other)
        let context = ModelContext(other)
        try ObservationReanalysisErasureReceipt(parentID: saved.intent.identity.observationID,
            childID: saved.intent.identity.analysisID).record(in: context)
        try context.save()
        #expect(throws: (any Error).self) {
            try Store.completeRetirement(otherClaim, proof: proof(otherClaim), container: other, isCurrent: { true })
        }
    }

    @Test func dispatchWinningOutcomeAppendsWithoutSelectionOrRetirementProof() throws {
        let container = try staging.execution.fixture.fixture.container(), active = try claim(container), bytes = try staging.execution.result()
        let receipt = try Store.completeRetirementOutcome(active, resultBytes: bytes, container: container, isCurrent: { true })
        #expect(receipt.retirementProof == nil && receipt.completedRetirementRequest == active.request)
        #expect(receipt.retirementOwnerID == active.snapshot.intent.ownerID)
        let context = ModelContext(container)
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(parent.selectedAnalysisID == staging.execution.fixture.fixture.analysis.uuidString.lowercased())
        #expect(parent.observationStateRevision == 3 && parent.analysisRecords?.count == 2)
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try Store.completeRetirementOutcome(active, resultBytes: bytes, container: container, isCurrent: { true }) == receipt)
        #expect(throws: (any Error).self) {
            try Store.completeRetirement(active, proof: proof(active), container: container, isCurrent: { true })
        }
        #expect(try ObservationReanalysisErasurePersistence.validate(receipt, container: container, isCurrent: { true }, complete: true))
        try ObservationReanalysisErasureReceipt(parentID: receipt.parentID, childID: receipt.childID).recordParentErasure(in: ModelContext(container))
        #expect(try Store.completeRetirementOutcome(active, resultBytes: bytes, container: container, isCurrent: { true }) == receipt)
    }

    @Test(arguments: [false, true])
    func recoveredOutcomeSaveRemainsAtomicAcrossLostLocalResponse(_ commits: Bool) throws {
        let container = try staging.execution.fixture.fixture.container(), active = try claim(container), bytes = try staging.execution.result()
        #expect(throws: (any Error).self) {
            try Store.completeRetirementOutcome(active, resultBytes: bytes, container: container, isCurrent: { true }, save: { context in
                if commits { try context.save() }
                throw CocoaError(.fileWriteUnknown)
            })
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == (commits ? 2 : 1))
        let receipt = try Store.completeRetirementOutcome(active, resultBytes: bytes, container: container, isCurrent: { true })
        #expect(receipt.completedRetirementRequest == active.request)
    }

    @Test func recoveredOutcomeRequiresExactResultAndCurrentClaim() throws {
        let container = try staging.execution.fixture.fixture.container(), first = try claim(container), bytes = try staging.execution.result()
        var changed = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        changed["request_digest"] = String(repeating: "0", count: 64)
        let wrong = try JSONSerialization.data(withJSONObject: changed)
        #expect(throws: (any Error).self) {
            try Store.completeRetirementOutcome(first, resultBytes: wrong, container: container, isCurrent: { true })
        }
        let second = try Store.claimRetirement(first.snapshot, admission: .interrupted, now: staging.execution.now,
            container: container, isCurrent: { true })
        #expect(throws: (any Error).self) {
            try Store.completeRetirementOutcome(first, resultBytes: bytes, container: container, isCurrent: { true })
        }
        #expect(throws: (any Error).self) {
            try Store.completeRetirementOutcome(second, resultBytes: bytes, container: container, isCurrent: { false })
        }
        _ = try Store.completeRetirementOutcome(second, resultBytes: bytes, container: container, isCurrent: { true })
    }

    @Test func recoveredOutcomeEnvelopeCannotMasqueradeAsRetirement() throws {
        let container = try staging.execution.fixture.fixture.container(), active = try claim(container)
        let receipt = try Store.completeRetirementOutcome(active, resultBytes: staging.execution.result(), container: container, isCurrent: { true })
        let context = ModelContext(container)
        let fetched = try context.fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(receipt.childID))
        let job = try #require(fetched), text = try #require(job.metadataJSON)
        #expect(try ObservationReanalysisErasureReceipt.restore(job) == receipt)
        let original = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        for field in ["version", "kind", "request_base64", "receipt_base64"] {
            var changed = original
            switch field {
            case "version": changed[field] = 2
            case "kind": changed[field] = "retired_before_dispatch"
            case "request_base64": changed[field] = Data("{}".utf8).base64EncodedString()
            default: changed[field] = "unexpected"
            }
            job.metadataJSON = String(data: try JSONSerialization.data(withJSONObject: changed), encoding: .utf8)
            #expect(throws: (any Error).self) { try ObservationReanalysisErasureReceipt.restore(job) }
        }
        context.rollback()
    }

    @Test func terminalEnvelopeRejectsMalformedOrCrossChildProof() throws {
        let container = try staging.execution.fixture.fixture.container(), active = try claim(container)
        let receipt = try Store.completeRetirement(active, proof: proof(active), container: container, isCurrent: { true })
        let context = ModelContext(container)
        let savedJob = try context.fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(receipt.childID))
        let job = try #require(savedJob)
        let text = try #require(job.metadataJSON)
        let original = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        for field in ["version", "kind", "owner_id", "child_id", "receipt_base64", "extra"] {
            var changed = original
            switch field {
            case "version": changed[field] = true
            case "kind": changed[field] = "complete"
            case "owner_id": changed[field] = "invalid"
            case "child_id": changed[field] = UUID().uuidString.lowercased()
            case "receipt_base64": changed[field] = Data("{}".utf8).base64EncodedString()
            default: changed[field] = true
            }
            job.metadataJSON = String(data: try JSONSerialization.data(withJSONObject: changed), encoding: .utf8)
            #expect(throws: (any Error).self) { try ObservationReanalysisErasureReceipt.restore(job) }
        }
        job.metadataJSON = text
        #expect(try ObservationReanalysisErasureReceipt.restore(job) == receipt)
    }
}
