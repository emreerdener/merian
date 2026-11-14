import Foundation
import SwiftData
import Testing
@testable import Merian

/// Synthetic saved-state construction only. No production release writer or
/// physical deletion is exercised or qualified by these fixtures.
@MainActor
final class SharedMediaNativeReleaseLiveFixture {
    typealias Values = SharedMediaNativeReceivingReleaseValues
    typealias Intent = SharedMediaNativeReceivingIntent
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    typealias Audit = SharedMediaNativeReceivingReleaseLiveAudit
    let store: Store, prepared: Intent.Prepared, received: Intent.Received
    let entries: [SharedMediaNativeFrozenEntry]
    var packageID: UUID { prepared.package.id }
    var progress: Values.Progress

    init(store: Store, prepared: Intent.Prepared, received: Intent.Received, plan: Values.Plan) throws {
        self.store = store; self.prepared = prepared; self.received = received
        entries = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes).entries
        progress = try .init(plan: plan)
    }
    static func make(count: Int, foreignOriginal: Bool = false) async throws -> SharedMediaNativeReleaseLiveFixture {
        let (store, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture(count: count, staged: true, foreignOriginal: foreignOriginal)
        let prepared = try Intent.Prepared(request)
        _ = try await owner.receiveAppPrepared(prepared)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let c = store.context(), packageID = store.packageID
        let slot = try one(c, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == packageID }))
        guard case .received(_, let received, _) = try SharedMediaNativeReceivingSlot.decode(.init(slot), profile: prepared.profile) else {
            throw SharedMediaStorageFailure.conflict
        }
        let ids = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes).entries.map { entry in
            let assetID = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes).preparation.original.reference.assetID
            return try one(c, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == assetID })).id
        }
        let p = prepared.profile
        let header = try SharedMediaNativeAppEligibility.snapshot(context: c,
            scope: .init(inventoryID: p.inventoryID, generation: p.generation, ownerID: p.ownerID,
                storeIdentity: p.storeIdentity, rootBinding: try p.rootIdentity))
        let plan = try Values.Plan(prepared: prepared, received: received, header: header, releaseID: UUID(), acquisitionIDs: ids)
        let result = try SharedMediaNativeReleaseLiveFixture(store: store, prepared: prepared, received: received, plan: plan)
        try result.save(c)
        return result
    }
    func read() throws -> Audit.Witness {
        let c = store.context()
        let result = try Audit.read(packageID: packageID, inventoryID: store.inventoryID, context: c)
        #expect(!c.hasChanges); #expect(result.progress == progress)
        return result
    }
    func save(_ c: ModelContext) throws {
        let expected = try SharedMediaNativeReceivingReleaseState.expected(progress, prepared: prepared, received: received)
        let id = packageID, invID = store.inventoryID
        let package = try store.package(packageID, in: c)
        let member = try Self.one(c, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
        let inventory = try Self.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == invID }))
        let slot = try Self.one(c, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id }))
        package.revision = expected.package.revision; package.allocatedByteCount = expected.package.allocated
        member.revision = expected.member.revision; member.membersData = expected.member.bytes
        inventory.revision = max(inventory.revision + 1, expected.minimumInventoryRevision)
        slot.phaseRaw = "releasing"; slot.schemaVersion = 2; slot.revision = expected.slotRevision
        slot.preparedData = nil; slot.resultData = try progress.encoded()
        slot.resultSHA256 = SharedMediaAcquisitionEncoding.digest(try progress.encoded())
        try c.save()
    }
    func inventoryAdvance() throws {
        let c = store.context(), id = store.inventoryID
        try Self.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id })).revision += 7
        try c.save()
    }
    func retirePair(_ index: Int) throws {
        let c = store.context(), target = progress.plan.targets[index], entry = entries[index]
        let intent = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes), id = target.pairID
        let row = try Self.one(c, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == id }))
        let invID = store.inventoryID, package = try store.package(packageID, in: c)
        let inventory = try Self.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == invID }))
        let packageID = package.id
        let member = try Self.one(c, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        let works = try [intent.ai.id, intent.display.id].map { workID in
            try Self.one(c, FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == workID }))
        }
        let workValues = works.map { work in
            SharedMediaNativePairFileState.Work(id: work.id, writerEpoch: work.writerEpoch, phase: work.phaseRaw,
                writerState: work.writerStateRaw, device: work.partialDevice, inode: work.partialInode,
                finalIdentity: work.finalIdentity, retirementID: nil, retirementPartial: nil, retirementFinal: nil,
                retirementParent: nil, retirementNamespace: nil, closure: nil)
        }
        let before = SharedMediaNativePairFileState(plan: .init(intent: entry.intent, writerEpoch: works[0].writerEpoch,
            inventoryID: inventory.id, inventoryGeneration: inventory.generation, inventoryRevision: inventory.revision,
            packageID: package.id, draftGeneration: package.draftGeneration, packageRevision: package.revision,
            envelope: package.supportingContextData, membershipRevision: member.revision, membership: member.membersData),
            phase: "ready", publishedRevision: row.publishedRevision, allocatedBytes: package.allocatedByteCount, work: workValues)
        let closure = SharedMediaNativePairClosure(version: 1, retirementID: UUID(), pairID: id,
            inventoryID: inventory.id, inventoryGeneration: inventory.generation, packageID: package.id,
            draftGeneration: package.draftGeneration, writerEpoch: works[0].writerEpoch,
            beforeHash: SharedMediaNativePairClosure.digest(try SharedMediaNativeDraftEnvelope.bytes(before)),
            intentHash: entry.intent.sha256, envelopeHash: progress.plan.package.envelopeSHA256,
            afterMembershipHash: SharedMediaNativePairClosure.digest(try SharedMediaNativePairClosure.retirementMembership(before)),
            afterMembershipRevision: member.revision + 1,
            previous: .init(inventoryRevision: inventory.revision, packageRevision: package.revision,
                membershipRevision: member.revision, membership: member.membersData, phase: "ready",
                publishedRevision: row.publishedRevision, allocatedBytes: package.allocatedByteCount),
            entries: zip(workValues, [entry.aiDescriptor, entry.displayDescriptor]).map { work, descriptor in
                .init(work: work, mode: .bound, identity: .init(partial: "absent", final: descriptor.file,
                    parent: descriptor.parent, namespace: descriptor.namespace))
            })
        let raw = try closure.encoded()
        for (work, input) in zip(works, [intent.ai, intent.display]) {
            let assetID = input.assetID, refID = input.referenceID
            let allocation = try Self.one(c, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == assetID }))
            let token = allocation.fileToken
            c.insert(PhotoPreparationLease(id: input.leaseID, packageID: package.id, assetID: assetID,
                ownerID: package.ownerID, processEpoch: work.writerEpoch, purposeRaw: SharedMediaNativePairPlanGraph.contract,
                partialFileToken: token + ".partial", finalFileToken: token, reservedByteCount: 0,
                allocatedByteCount: input.byteCount, writerStateRaw: "closedNativePairRetirementV2",
                terminalProof: work.id == intent.ai.id ? raw : try closure.siblingMarker()))
            c.insert(SharedMediaLeaseRecord(id: input.leaseID, allocationID: assetID, processEpoch: work.writerEpoch,
                purposeRaw: SharedMediaNativePairPlanGraph.contract, stateRaw: "closed"))
            let proof = try #require(closure.entries.first { $0.work.id == work.id })
            work.phaseRaw = "retiring"; work.retirementID = closure.retirementID
            work.retirementPartialIdentity = proof.identity.partial; work.retirementFinalIdentity = proof.identity.final
            work.retirementParentIdentity = proof.identity.parent; work.retirementNamespaceIdentity = proof.identity.namespace
            allocation.stateRaw = "nativePairRetiringV2"
            try Self.one(c, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID })).cleanupStateRaw = "retiring"
            let ref = try Self.one(c, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == refID }))
            let edge = try Self.one(c, FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == refID }))
            let counter = try Self.one(c, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID }))
            ref.isLive = false; ref.revision = 1; edge.stateRaw = "retired"; edge.revision = 1
            counter.liveCount = 0; counter.revision = 1; counter.retirementID = closure.retirementID
        }
        row.phaseRaw = "retiring"; row.publishedRevision = nil
        progress = try progress.advancing(.init(pairID: id, stage: .retiringPair,
            pair: .init(retirementID: closure.retirementID, closureSHA256: SharedMediaNativePairClosure.digest(Data(raw.utf8))), original: nil))
        try save(c)
    }
    func removePair(_ index: Int) throws {
        let c = store.context(), target = progress.plan.targets[index], id = target.pairID
        for output in [target.ai, target.display] {
            let asset = output.assetID, ref = output.referenceID, work = output.workID, lease = output.leaseID
            c.delete(try Self.one(c, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == asset })))
            c.delete(try Self.one(c, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == asset })))
            c.delete(try Self.one(c, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == ref })))
            c.delete(try Self.one(c, FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == ref })))
            c.delete(try Self.one(c, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == asset })))
            c.delete(try Self.one(c, FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == lease })))
            c.delete(try Self.one(c, FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == lease })))
            c.delete(try Self.one(c, FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == work })))
        }
        c.delete(try Self.one(c, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == id })))
        progress = try progress.advancing(.init(pairID: id, stage: .pairGoneOriginalLive, pair: progress.targets[index].pair, original: nil))
        try save(c)
    }
    func retireOriginal(_ index: Int) throws {
        let c = store.context(), target = progress.plan.targets[index], assetID = target.original.assetID
        let source = try SharedMediaNativeDerivativeIntent.decode(entries[index].intent.bytes).preparation.original
        let proof = try SharedMediaNativeRetirementIdentity(retirementID: UUID(), assetID: assetID,
            assetGeneration: target.original.assetGeneration, inventoryID: store.inventoryID,
            inventoryGeneration: progress.plan.profile.generation, ownerID: store.ownerID, proof: source.descriptor)
        let (ref, edge) = try SharedMediaNativeAppOriginalRows.reference(c, source: target.original, live: true)
        ref.isLive = false; ref.revision += 1; edge.stateRaw = "retired"; edge.revision = ref.revision
        try Self.one(c, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID })).cleanupStateRaw = "retiring"
        let allocation = try Self.one(c, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == assetID }))
        allocation.stateRaw = SharedMediaNativeRetirementIdentity.allocationState; allocation.physicalIdentity = try proof.encoded()
        let counter = try Self.one(c, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID }))
        counter.liveCount = 0; counter.revision += 1; counter.retirementID = proof.retirementID
        progress = try progress.advancing(.init(pairID: target.pairID, stage: .originalRetiring, pair: progress.targets[index].pair,
            original: .init(disposition: .removed, retirementID: proof.retirementID,
                closureSHA256: SharedMediaAcquisitionEncoding.digest(Data(try proof.encoded().utf8)))))
        try save(c)
    }
    func removeOriginal(_ index: Int) throws {
        let c = store.context(), target = progress.plan.targets[index]
        try eraseOriginal(target, context: c)
        progress = try progress.advancing(.init(pairID: target.pairID, stage: .removed,
            pair: progress.targets[index].pair, original: progress.targets[index].original))
        try save(c)
    }
    func eraseOriginal(_ target: Values.Target, context c: ModelContext) throws {
        let assetID = target.original.assetID, receiptID = target.acquisitionID
        for ref in try c.fetch(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.assetID == assetID })) { c.delete(ref) }
        for edge in try c.fetch(FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.allocationID == assetID })) { c.delete(edge) }
        c.delete(try Self.one(c, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID })))
        c.delete(try Self.one(c, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == assetID })))
        c.delete(try Self.one(c, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID })))
        c.delete(try Self.one(c, FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == receiptID })))
        let receipt = try Self.one(c, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == receiptID }))
        receipt.phaseRaw = "terminal"; receipt.revision = 2; receipt.terminalOutcomeRaw = "released"
        receipt.requestData = nil; receipt.resultData = nil; receipt.packageID = nil; receipt.assetID = nil
    }
    static func one<T: PersistentModel>(_ c: ModelContext, _ query: FetchDescriptor<T>) throws -> T {
        try SharedMediaNativePairPlanGraph.one(c, query)
    }
}
