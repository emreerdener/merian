import Foundation
@testable import Merian
import SwiftData
import Testing

/// Injects historical accepted rows into a real native graph after its owner
/// drains. This qualifies only accounting, never the absent admission writer.
@MainActor
enum SharedMediaOrdinaryAccountingTests {
    static func check(_ binding: SharedMediaOrdinaryPhotoHoldBinding, container: ModelContainer,
                      detachedFixtureID: UUID, inspect: () async throws -> Void) async throws {
        let c = ModelContext(container); c.autosaveEnabled = false
        let submission = try SharedMediaOrdinarySubmission(binding: binding)
        let holds = try SharedMediaOrdinaryHoldCohort(binding.orderedRequests)
        let body = try submission.encoded()
        let inventoryID = submission.profile.inventoryID
        let inventory = try SharedMediaNativeAppOriginalRows.one(c,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let baseline = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inventory,
            ownerID: submission.profile.ownerID, format: .appV2)
        let parent = SharedMediaOrdinarySubmissionRecord(inventoryID: inventoryID,
            inventoryGeneration: submission.profile.generation, ownerID: submission.profile.ownerID,
            recipientScanID: submission.scanID, submissionGeneration: submission.generation,
            jobID: submission.jobID, eventID: submission.eventID, writerEpoch: submission.writerEpoch,
            formatRaw: submission.format.rawValue, requestData: body,
            requestSHA256: SharedMediaAcquisitionEncoding.digest(body), observationSHA256: submission.observation.sha256)
        let acceptance = try SharedMediaOrdinarySubmissionAcceptance(submission: submission, holds: holds)
        let acceptedBytes = try acceptance.encoded(submission: submission, holds: holds)
        parent.phaseRaw = "accepted"; parent.revision = 1
        parent.acceptanceData = acceptedBytes; parent.acceptanceSHA256 = SharedMediaAcquisitionEncoding.digest(acceptedBytes)
        c.insert(parent)
        let perHold = try holds.acceptances()
        for request in holds.requests {
            let bytes = try request.encoded(), accepted = try #require(perHold[request.id])
            let row = SharedMediaOrdinaryTransferRecord(id: request.id, inventoryID: inventoryID,
                inventoryGeneration: submission.profile.generation, ownerID: submission.profile.ownerID,
                sourceAssetID: request.source.assetID, sourceReferenceID: request.source.referenceID,
                recipientScanID: submission.scanID, submissionGeneration: submission.generation,
                writerEpoch: submission.writerEpoch, requestData: bytes, requestSHA256: SharedMediaAcquisitionEncoding.digest(bytes))
            let receipt = try accepted.encoded(request: request)
            row.phaseRaw = "accepted"; row.revision = 1
            row.acceptanceData = receipt; row.acceptanceSHA256 = SharedMediaAcquisitionEncoding.digest(receipt)
            c.insert(row)
            let assetID = request.source.assetID
            let counter = try SharedMediaNativeAppOriginalRows.one(c,
                FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID }))
            counter.liveCount = accepted.liveCount; counter.revision = accepted.countRevision
            inventory.revision = accepted.inventoryRevision
        }
        try c.save()
        let request = try #require(holds.requests.first), assetID = request.source.assetID
        func read(_ context: ModelContext) throws -> SharedMediaNativeOriginalAccounting.Snapshot {
            try SharedMediaNativeOriginalAccounting.auditAcceptedOrdinary(assetID: assetID, inventoryID: inventoryID, context: context)
        }
        func auditStore(_ context: ModelContext) throws -> SharedMediaOrdinaryStoreAudit.Snapshot {
            try SharedMediaOrdinaryStoreAudit.verify(context: context, profile: submission.profile)
        }
        #expect(try read(c).liveCount == 2)
        let store = try auditStore(c)
        #expect(store.submissions == 1)
        #expect(store.holds == Int64(holds.requests.count))
        #expect(store.metadataBytes == (try SharedMediaOrdinarySubmissionReceipt.read(parent, in: c)).metadataBytes)
        var escaped: SharedMediaOrdinaryInspection?
        try await SharedMediaOrdinaryInspection.withVerified(container: container, profile: submission.profile, checkpoint: {}) { scope in
            let scope = try #require(scope); escaped = scope
            let budget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inventory,
                ownerID: submission.profile.ownerID, format: .appV2, ordinary: scope)
            var expected = baseline.totals
            try expected.includePhotoPhysical(materialized: store.metadataBytes, reserved: 0)
            #expect(budget.totals == expected) // Shared pending/held bytes are not charged twice.
            let dirty = ModelContext(container); dirty.autosaveEnabled = false
            let dirtyInventory = try SharedMediaNativeAppOriginalRows.one(dirty,
                FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
            dirtyInventory.revision += 1
            #expect(throws: (any Error).self) { try scope.requireCurrent(dirty) }
            dirty.rollback()
            let persisted = ModelContext(container); persisted.autosaveEnabled = false
            let persistedInventory = try SharedMediaNativeAppOriginalRows.one(persisted,
                FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
            let revision = persistedInventory.revision
            persistedInventory.revision = revision + 1; try persisted.save()
            #expect(throws: (any Error).self) { try scope.requireCurrent(persisted) }
            persistedInventory.revision = revision; try persisted.save()
        }
        #expect(throws: (any Error).self) { try escaped?.requireCurrent(c) }
        let identity = SharedMediaNativeScopeIdentity(inventoryID: inventoryID,
            generation: submission.profile.generation, ownerID: submission.profile.ownerID,
            storeIdentity: submission.profile.storeIdentity, rootBinding: try submission.profile.rootIdentity)
        await #expect(throws: (any Error).self) {
            _ = try await SharedMediaNativeScopedAudit.runAppErasureInitial(container: container, profile: submission.profile,
                files: nil, header: { try SharedMediaNativeAppEligibility.snapshot(context: ModelContext(container), scope: identity) }, betweenPages: {})
        }
        let detached = try SharedMediaNativeAppOriginalRows.one(c,
            FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == detachedFixtureID }))
        #expect(detached.supportingContextData == Data("ordinary-draft".utf8))
        c.delete(detached); try c.save()
        let erasure = try await SharedMediaNativeScopedAudit.runAppErasureInitial(container: container, profile: submission.profile,
            files: nil, header: { try SharedMediaNativeAppEligibility.snapshot(context: ModelContext(container), scope: identity) }, betweenPages: {})
        #expect(erasure.receipts == Int64(holds.requests.count))
        await #expect(throws: (any Error).self) {
            _ = try await SharedMediaNativeScopedAudit.runApp(container: container, profile: { submission.profile },
                header: { try SharedMediaNativeAppEligibility.snapshot(context: c, scope: identity) },
                betweenPages: {}, configure: { _ in })
        }
        // Unsupported receiving states cannot enter the accepted read route.
        let unsupported = SharedMediaReceivingIntentRecord(packageID: UUID(), inventoryID: inventoryID,
            inventoryGeneration: submission.profile.generation, ownerID: submission.profile.ownerID,
            draftGeneration: UUID(), operationID: UUID(), preparedData: Data(), preparedSHA256: String(repeating: "0", count: 64))
        c.insert(unsupported); try c.save()
        for phase in ["prepared", "releasing", "released"] {
            unsupported.phaseRaw = phase; try c.save()
            await #expect(throws: (any Error).self) {
                try await SharedMediaOrdinaryInspection.withVerified(container: container, profile: submission.profile, checkpoint: {}) { _ in
                    Issue.record("Unsupported receiving state entered ordinary inspection")
                }
            }
            await #expect(throws: (any Error).self) {
                _ = try await SharedMediaNativeScopedAudit.runAppErasureInitial(container: container, profile: submission.profile,
                    files: nil, header: { try SharedMediaNativeAppEligibility.snapshot(context: ModelContext(container), scope: identity) }, betweenPages: {})
            }
        }
        unsupported.phaseRaw = "received"
        for field in [\SharedMediaReceivingIntentRecord.allocationData, \.initialAdmissionData, \.initialCompletionData, \.releaseStartData] {
            unsupported[keyPath: field] = Data(); try c.save()
            await #expect(throws: (any Error).self) {
                try await SharedMediaOrdinaryInspection.withVerified(container: container, profile: submission.profile, checkpoint: {}) { _ in
                    Issue.record("Advanced receiving state entered ordinary inspection")
                }
            }
            unsupported[keyPath: field] = nil
        }
        c.delete(unsupported); try c.save()
        try await inspect()
        // Rows cannot disappear from the whole-store audit by changing scope.
        let priorInventory = parent.inventoryID
        parent.inventoryID = UUID(); try c.save()
        #expect(throws: (any Error).self) { _ = try auditStore(c) }
        parent.inventoryID = priorInventory; try c.save()
        // The default audit must remain P1-only, and generic owners stay closed.
        #expect(throws: (any Error).self) {
            _ = try SharedMediaNativeOriginalAccounting.audit(assetID: assetID, inventoryID: inventoryID, context: c)
        }
        #expect(throws: (any Error).self) { try SharedMediaStorageLookup.requireNoUnqualifiedOrdinaryTransfers(c) }
        let counter = try SharedMediaNativeAppOriginalRows.one(c,
            FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID }))
        counter.liveCount = 1
        #expect(throws: (any Error).self) { _ = try read(c) }
        try c.save()
        #expect(throws: (any Error).self) { _ = try read(c) }
        counter.liveCount = 2; try c.save()
        parent.phaseRaw = "reserved"; try c.save()
        #expect(throws: (any Error).self) { _ = try auditStore(c) }
        #expect(throws: (any Error).self) { _ = try read(c) }
        parent.phaseRaw = "accepted"; try c.save()
        let hold = try SharedMediaNativeAppOriginalRows.one(c,
            FetchDescriptor<SharedMediaOrdinaryTransferRecord>(predicate: #Predicate { $0.sourceAssetID == assetID }))
        let before = hold.sourceReferenceID
        hold.sourceReferenceID = UUID(); try c.save()
        #expect(throws: (any Error).self) { _ = try read(c) }
        hold.sourceReferenceID = before; try c.save()
        hold.phaseRaw = "reserved"; try c.save()
        #expect(throws: (any Error).self) { _ = try read(c) }
        hold.phaseRaw = "accepted"; try c.save()
        // An extra valid per-source envelope still violates complete membership.
        let extraRequest: SharedMediaOrdinaryHoldRequest = try SharedMediaNativeReceivingTestFixture.copy(request,
            changes: ["id": UUID().uuidString])
        let extraBytes = try extraRequest.encoded()
        let extra = SharedMediaOrdinaryTransferRecord(id: extraRequest.id, inventoryID: inventoryID,
            inventoryGeneration: submission.profile.generation, ownerID: submission.profile.ownerID,
            sourceAssetID: assetID, sourceReferenceID: request.source.referenceID,
            recipientScanID: submission.scanID, submissionGeneration: submission.generation,
            writerEpoch: submission.writerEpoch, requestData: extraBytes, requestSHA256: SharedMediaAcquisitionEncoding.digest(extraBytes))
        let extraAcceptance = try SharedMediaOrdinaryHoldAcceptance(request: extraRequest,
            inventoryRevision: inventory.revision, countRevision: counter.revision, liveCount: counter.liveCount)
        let extraReceipt = try extraAcceptance.encoded(request: extraRequest)
        extra.phaseRaw = "accepted"; extra.revision = 1
        extra.acceptanceData = extraReceipt; extra.acceptanceSHA256 = SharedMediaAcquisitionEncoding.digest(extraReceipt)
        c.insert(extra); try c.save()
        #expect(throws: (any Error).self) { _ = try read(c) }
        #expect(throws: (any Error).self) { _ = try auditStore(c) }
        // A completely orphaned row must be rejected even when all scope and
        // correlation fields would exclude it from per-source/parent queries.
        extra.inventoryID = UUID(); extra.sourceAssetID = UUID()
        extra.recipientScanID = UUID(); extra.submissionGeneration = UUID()
        try c.save()
        #expect(throws: (any Error).self) { _ = try auditStore(c) }
        c.delete(extra); try c.save()
        // Simulate a later qualified removal's persisted after-image. No P1
        // pair remains, but the accepted hold still retains the physical asset.
        let referenceID = request.source.referenceID
        let reference = try SharedMediaNativeAppOriginalRows.one(c,
            FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == referenceID }))
        let edge = try SharedMediaNativeAppOriginalRows.one(c,
            FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == referenceID }))
        c.delete(reference); c.delete(edge)
        counter.liveCount = 1; counter.revision += 1; inventory.revision += 1
        try c.save()
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let location = try #require(container.configurations.first).url
        let reopened = try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, url: location, cloudKitDatabase: .none)])
        let fresh = ModelContext(reopened); fresh.autosaveEnabled = false
        #expect(try read(fresh).liveCount == 1)
        #expect(try read(fresh).retirement == nil)
        #expect(try auditStore(fresh).holds == Int64(holds.requests.count))
        try await SharedMediaOrdinaryInspection.withVerified(container: reopened, profile: submission.profile, checkpoint: {}) { scope in
            let scope = try #require(scope)
            var actual = SharedMediaStoragePolicy.Totals(), expected = SharedMediaStoragePolicy.Totals()
            let peers = Set(holds.requests.map { $0.source.assetID }).subtracting([assetID])
            try scope.includeLiability(context: fresh, pendingAssets: peers, totals: &actual, checkpoint: {})
            let metadata = try SharedMediaAcquisitionReceipt.metadataCharge(request: request.acquisition, result: request.completion)
            let identity = Int64(request.completion.descriptor.file.utf8.count)
            try expected.includePhotoPhysical(materialized: PhotoPreparationPolicy.add([
                scope.snapshot.metadataBytes, request.completion.byteCount, metadata, identity]), reserved: 512 - identity)
            #expect(actual == expected) // Held-only original survives with one complete charge.
        }
        // A hold does not itself authorize the final zero-count retirement.
        counter.liveCount = 0; counter.revision += 1; try c.save()
        #expect(throws: (any Error).self) { _ = try read(c) }
        #expect(throws: (any Error).self) { _ = try auditStore(c) }
    }
}
