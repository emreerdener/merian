import Foundation
import SwiftData

/// File transitions use the existing native fence and a complete fresh witness.
/// No file descriptor, generic save, or caller-supplied mutation authority escapes.
@MainActor
final class SharedMediaNativePairFileMutation {
    private let container: ModelContainer
    private let authority: SharedMediaNativeMutationAuthority
    private let context: ModelContext
    private let inventory: SharedMediaInventoryRecord
    private let package: PhotoPreparationRecord
    private let member: SharedMediaPendingMembershipRecord
    private let pair: SharedMediaDerivativePairRecord
    private let before: SharedMediaNativePairFileState

    init(container: ModelContainer, inventoryID: UUID, packageID: UUID, authority: SharedMediaNativeMutationAuthority) throws {
        try authority.validate()
        self.container = container; self.authority = authority
        context = ModelContext(container); context.autosaveEnabled = false
        inventory = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        package = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        member = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        guard !authority.binding.initializing, package.ownerID == authority.ownerID,
              authority.binding.bytes == (try JSONEncoder().encode(["nativeQualificationV1", inventory.id.uuidString, inventory.storeIdentity, inventory.rootIdentity])) else {
            throw SharedMediaStorageFailure.closed
        }
        try SharedMediaNativeAcquisitionGraph.audit(context: context, inventoryID: inventoryID)
        before = try SharedMediaNativePairFileGraph.state(context: context, inventory: inventory, package: package, member: member)
        let pairID = try before.intent().pairID
        pair = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == pairID }))
    }
    func state() -> SharedMediaNativePairFileState { before }

    func reserve(_ expected: SharedMediaNativePairFileState, availableBytes: Int64,
                 beforeSave: () throws -> Void, afterSave: () throws -> Void) throws -> SharedMediaNativePairFileState {
        guard expected == before, before.phase == "planned", before.plan.writerEpoch == authority.binding.epoch else { throw SharedMediaStorageFailure.stale }
        for item in before.work {
            let (work, input) = try rows(item.id), file = try before.file(item.id)
            guard work.phaseRaw == "planned", work.writerStateRaw == "absent" else { throw SharedMediaStorageFailure.conflict }
            work.phaseRaw = "reserved"; work.writerStateRaw = "open"
            context.insert(PhotoPreparationLease(id: input.leaseID, packageID: package.id, assetID: input.assetID,
                ownerID: package.ownerID, processEpoch: work.writerEpoch, purposeRaw: SharedMediaNativePairPlanGraph.contract,
                partialFileToken: file.token + ".partial", finalFileToken: file.token, reservedByteCount: input.byteCount,
                allocatedByteCount: 0, writerStateRaw: "open", terminalProof: nil))
            context.insert(SharedMediaAllocationRecord(id: input.assetID, inventoryID: inventory.id, accountID: package.ownerID,
                packageID: package.id, namespaceRaw: SharedMediaPhotoLedger.namespace, fileToken: file.token,
                poolRaw: "durable", stateRaw: "nativePairReservedV2", materializedBytes: 0, reservedBytes: input.byteCount, physicalIdentity: nil))
            context.insert(SharedMediaLeaseRecord(id: input.leaseID, allocationID: input.assetID,
                processEpoch: work.writerEpoch, purposeRaw: SharedMediaNativePairPlanGraph.contract, stateRaw: "open"))
        }
        pair.phaseRaw = "writing"
        try advance()
        let budget = try SharedMediaNativeAcquisitionBudget.evaluate(context: context, inventory: inventory)
        try budget.totals.checkAvailable(availableBytes, additionalReservation: 0)
        return try save(beforeSave, afterSave)
    }

    func partial(_ proof: SharedMediaNativePairPartial, beforeSave: () throws -> Void,
                 afterSave: () throws -> Void) throws -> SharedMediaNativePairFileState {
        try binding(proof.binding, proof.epoch)
        guard proof.state == before, before.phase == "writing", proof.identity.bytes == 0,
              before.plan.writerEpoch == authority.binding.epoch else { throw SharedMediaStorageFailure.stale }
        let (work, _) = try rows(proof.workID)
        guard work.phaseRaw == "reserved", work.writerStateRaw == "open", work.partialDevice == nil, work.partialInode == nil else { throw SharedMediaStorageFailure.conflict }
        work.partialDevice = proof.identity.device; work.partialInode = proof.identity.inode; work.phaseRaw = "writing"
        try advance(); return try save(beforeSave, afterSave)
    }

    func complete(_ proof: SharedMediaNativePairCompletion, beforeSave: () throws -> Void,
                  afterSave: () throws -> Void) throws -> SharedMediaNativePairFileState {
        try binding(proof.binding, proof.epoch)
        guard proof.state == before, ["writing", "ready"].contains(before.phase), proof.file == (try before.file(proof.workID)) else { throw SharedMediaStorageFailure.stale }
        let (work, input) = try rows(proof.workID)
        guard ["writing", "completed"].contains(work.phaseRaw), proof.identity.bytes == input.byteCount,
              proof.identity.device == work.partialDevice, proof.identity.inode == work.partialInode else { throw SharedMediaStorageFailure.conflict }
        if work.phaseRaw == "completed" {
            guard work.finalIdentity == proof.identity.exact else { throw SharedMediaStorageFailure.conflict }; return before
        }
        let assetID = input.assetID, leaseID = input.leaseID
        let allocation = try one(FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == assetID }))
        let lease = try one(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == leaseID }))
        let shared = try one(FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == leaseID }))
        context.insert(PhotoPreparationAsset(id: assetID, ownerID: package.ownerID, generation: input.assetGeneration,
            fileToken: proof.file.token, contentType: input.contentType, byteCount: input.byteCount, sha256: input.sha256,
            acquisitionKindRaw: "nativeDerivativeV2", cleanupStateRaw: "ready"))
        context.insert(PhotoPreparationReference(id: input.referenceID, packageID: package.id, assetID: assetID,
            ownerID: package.ownerID, roleRaw: input.role, ordinal: pair.ordinal, revision: 0, isLive: true))
        context.insert(SharedMediaReferenceRecord(id: input.referenceID, allocationID: assetID, accountID: package.ownerID,
            ownerID: input.referenceID.uuidString.lowercased(), roleRaw: SharedMediaPhotoLedger.namespace, stateRaw: "live", revision: 0))
        context.insert(SharedMediaAssetReferenceCountRecord(assetID: assetID, assetGeneration: input.assetGeneration,
            inventoryID: inventory.id, inventoryGeneration: inventory.generation, ownerID: package.ownerID, liveCount: 1))
        work.phaseRaw = "completed"; work.writerStateRaw = "closed"; work.finalIdentity = proof.identity.exact
        allocation.stateRaw = "nativePairMaterializedV2"; allocation.materializedBytes = input.byteCount
        allocation.reservedBytes = 0; allocation.physicalIdentity = proof.identity.exact
        lease.reservedByteCount = 0; lease.allocatedByteCount = input.byteCount; lease.writerStateRaw = "closedPairWaiting"; shared.stateRaw = "closed"
        package.allocatedByteCount = try SharedMediaStoragePolicy.add(package.allocatedByteCount, input.byteCount)
        try advance(); return try save(beforeSave, afterSave)
    }

    func publish(_ expected: SharedMediaNativePairFileState, proofs: [SharedMediaNativePairCompletion],
                 beforeSave: () throws -> Void, afterSave: () throws -> Void) throws -> SharedMediaNativePairFileState {
        guard expected == before, before.phase == "writing", proofs.count == 2,
              Set(proofs.map(\.workID)) == Set(before.work.map(\.id)), before.work.allSatisfy({ $0.phase == "completed" }) else { throw SharedMediaStorageFailure.stale }
        for proof in proofs {
            try binding(proof.binding, proof.epoch)
            let (work, input) = try rows(proof.workID), leaseID = input.leaseID
            guard proof.state == before, proof.file == (try before.file(work.id)), proof.identity.exact == work.finalIdentity else { throw SharedMediaStorageFailure.conflict }
            context.delete(try one(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == leaseID })))
            context.delete(try one(FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == leaseID })))
        }
        pair.phaseRaw = "ready"; package.phaseRaw = "draftOwned"
        pair.publishedRevision = try SharedMediaStoragePolicy.add(package.revision, 1)
        try advance()
        return try save(beforeSave, afterSave)
    }

    func retire(_ expected: SharedMediaNativePairFileState, proofs: [SharedMediaNativePairInspection],
                beforeSave: () throws -> Void, afterSave: () throws -> Void) throws -> SharedMediaNativePairFileState {
        guard expected == before, ["writing", "ready"].contains(before.phase), proofs.count == 2,
              Set(proofs.map(\.workID)) == Set(before.work.map(\.id)) else { throw SharedMediaStorageFailure.stale }
        let entries = try before.work.map { work -> SharedMediaNativePairClosure.Entry in
            guard let proof = proofs.first(where: { $0.workID == work.id }), proof.state == before else { throw SharedMediaStorageFailure.conflict }
            try binding(proof.binding, proof.epoch)
            let mode: SharedMediaNativePairClosure.Mode = work.device != nil ? .bound : proof.identity.partial == "absent" ? .unboundAbsent : .unboundPartial
            return .init(work: work, mode: mode, identity: proof.identity)
        }
        let afterMembership = try SharedMediaNativePairClosure.retirementMembership(before)
        let closure = SharedMediaNativePairClosure(version: 1, retirementID: UUID(), pairID: pair.id,
            inventoryID: inventory.id, inventoryGeneration: inventory.generation, packageID: package.id,
            draftGeneration: package.draftGeneration, writerEpoch: before.plan.writerEpoch,
            beforeHash: SharedMediaNativePairClosure.digest(try SharedMediaNativeDraftEnvelope.bytes(before)),
            intentHash: SharedMediaNativePairClosure.digest(before.plan.intent.bytes),
            envelopeHash: SharedMediaNativePairClosure.digest(before.plan.envelope),
            afterMembershipHash: SharedMediaNativePairClosure.digest(afterMembership),
            afterMembershipRevision: try SharedMediaStoragePolicy.add(member.revision, afterMembership == member.membersData ? 0 : 1),
            previous: .init(inventoryRevision: inventory.revision, packageRevision: package.revision,
                membershipRevision: member.revision, membership: member.membersData, phase: before.phase,
                publishedRevision: before.publishedRevision, allocatedBytes: package.allocatedByteCount), entries: entries)
        let raw = try closure.encoded(), marker = try closure.siblingMarker()
        guard raw.utf8.count + marker.utf8.count <= (try SharedMediaNativePairClosure.maximumEncodingBytes(before)) else { throw SharedMediaStorageFailure.capacity }
        for entry in entries {
            let (work, input) = try rows(entry.work.id), assetID = input.assetID, leaseID = input.leaseID
            let token = try before.file(work.id).token
            if before.phase == "ready" {
                context.insert(PhotoPreparationLease(id: leaseID, packageID: package.id, assetID: assetID,
                    ownerID: package.ownerID, processEpoch: work.writerEpoch, purposeRaw: SharedMediaNativePairPlanGraph.contract,
                    partialFileToken: token + ".partial", finalFileToken: token, reservedByteCount: 0,
                    allocatedByteCount: input.byteCount, writerStateRaw: "closedNativePairRetirementV2", terminalProof: nil))
                context.insert(SharedMediaLeaseRecord(id: leaseID, allocationID: assetID, processEpoch: work.writerEpoch,
                    purposeRaw: SharedMediaNativePairPlanGraph.contract, stateRaw: "closed"))
            }
            let lease = try one(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == leaseID }))
            lease.writerStateRaw = "closedNativePairRetirementV2"; lease.terminalProof = work.id == pair.aiWorkID ? raw : marker
            try one(FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == leaseID })).stateRaw = "closed"
            try one(FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == assetID })).stateRaw = "nativePairRetiringV2"
            work.phaseRaw = "retiring"; work.writerStateRaw = "closed"; work.retirementID = closure.retirementID
            work.retirementPartialIdentity = entry.identity.partial; work.retirementFinalIdentity = entry.identity.final
            work.retirementParentIdentity = entry.identity.parent; work.retirementNamespaceIdentity = entry.identity.namespace
            if work.finalIdentity != nil {
                let referenceID = input.referenceID
                let reference = try one(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == referenceID }))
                let edge = try one(FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == referenceID }))
                let counter = try one(FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID }))
                guard counter.liveCount == 1, counter.revision == 0, counter.retirementID == nil else { throw SharedMediaStorageFailure.inUse }
                reference.isLive = false; reference.revision = 1; edge.stateRaw = "retired"; edge.revision = 1
                counter.liveCount = 0; counter.revision = 1; counter.retirementID = closure.retirementID
                try one(FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID })).cleanupStateRaw = "retiring"
            }
        }
        pair.phaseRaw = "retiring"; pair.publishedRevision = nil; package.phaseRaw = "needsAttention"
        try advance(); return try save(beforeSave, afterSave)
    }

    /// Only this fenced owner mints disposal after exact persisted readback.
    func disposal(_ expected: SharedMediaNativePairFileState) throws -> SharedMediaNativePairDisposal {
        guard expected == before, before.phase == "retiring" else { throw SharedMediaStorageFailure.stale }
        try authority.validate()
        return .init(state: before, binding: authority.binding.bytes, epoch: authority.binding.epoch)
    }

    func release(_ proofs: [SharedMediaNativePairAbsence], beforeSave: () throws -> Void, afterSave: () throws -> Void) throws {
        guard before.phase == "retiring", proofs.count == 2, Set(proofs.map(\.workID)) == Set(before.work.map(\.id)) else { throw SharedMediaStorageFailure.stale }
        for proof in proofs {
            try binding(proof.binding, proof.epoch)
            guard proof.state == before else { throw SharedMediaStorageFailure.stale }
        }
        for proof in proofs {
            let (work, input) = try rows(proof.workID), assetID = input.assetID, referenceID = input.referenceID, leaseID = input.leaseID
            if work.finalIdentity != nil {
                context.delete(try one(FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID })))
                context.delete(try one(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == referenceID })))
                context.delete(try one(FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == referenceID })))
                context.delete(try one(FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID })))
                guard package.allocatedByteCount >= input.byteCount else { throw SharedMediaStorageFailure.conflict }
                package.allocatedByteCount -= input.byteCount
            }
            context.delete(try one(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == leaseID })))
            context.delete(try one(FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == leaseID })))
            context.delete(try one(FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == assetID })))
            context.delete(work)
        }
        context.delete(pair)
        guard case .preparation(let envelope) = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData) else { throw SharedMediaStorageFailure.conflict }
        package.supportingContextData = try SharedMediaNativeDraftEnvelope.V2(version: 2, contexts: envelope.contexts,
            presentation: envelope.presentation, sequence: envelope.sequence, attempt: nil, intents: [], frozen: nil).encoded()
        package.phaseRaw = "draftOwned"; try advance()
        _ = try SharedMediaNativeAcquisitionBudget.evaluate(context: context, inventory: inventory)
        let expected = try releaseWitness(context)
        try beforeSave(); try authority.validate()
        guard try fresh().before == before else { throw SharedMediaStorageFailure.stale }
        func result() throws -> Data {
            let fresh = ModelContext(container); fresh.autosaveEnabled = false
            try SharedMediaNativeAcquisitionGraph.audit(context: fresh, inventoryID: inventory.id)
            return try releaseWitness(fresh)
        }
        do { try context.save(); try afterSave() }
        catch {
            let failure = error; context.rollback()
            guard (try? result()) == expected else { throw failure }
        }
        guard try result() == expected else { throw SharedMediaStorageFailure.stale }
    }

    private func releaseWitness(_ queryContext: ModelContext) throws -> Data {
        let inventoryID = inventory.id, packageID = package.id
        let inv = try SharedMediaNativePairPlanGraph.one(queryContext, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let pkg = try SharedMediaNativePairPlanGraph.one(queryContext, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        let mem = try SharedMediaNativePairPlanGraph.one(queryContext, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        return try SharedMediaNativeDraftEnvelope.bytes([inv.generation.uuidString, String(inv.revision), pkg.id.uuidString,
            pkg.draftGeneration.uuidString, String(pkg.revision), pkg.phaseRaw, String(pkg.allocatedByteCount),
            pkg.supportingContextData.base64EncodedString(), String(mem.revision), mem.membersData.base64EncodedString()])
    }

    private func rows(_ id: UUID) throws -> (SharedMediaDerivativeWorkRecord, SharedMediaDerivativeInput) {
        let (_, input) = try before.selected(id)
        return (try one(FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == id })), input)
    }
    private func one<T: PersistentModel>(_ query: FetchDescriptor<T>) throws -> T { try SharedMediaNativePairPlanGraph.one(context, query) }
    private func binding(_ bytes: Data, _ epoch: UUID) throws {
        try authority.validate()
        guard bytes == authority.binding.bytes, epoch == authority.binding.epoch else { throw SharedMediaStorageFailure.closed }
    }
    private func advance() throws {
        inventory.revision = try SharedMediaStoragePolicy.add(inventory.revision, 1)
        package.revision = try SharedMediaStoragePolicy.add(package.revision, 1)
        let bytes = try SharedMediaPendingGraph.derive(in: context, inventory: inventory).membership(packageID: package.id).encoded()
        if member.membersData != bytes { member.membersData = bytes; member.revision = try SharedMediaStoragePolicy.add(member.revision, 1) }
    }
    private func fresh() throws -> SharedMediaNativePairFileMutation {
        try .init(container: container, inventoryID: inventory.id, packageID: package.id, authority: authority)
    }
    private func save(_ beforeSave: () throws -> Void, _ afterSave: () throws -> Void) throws -> SharedMediaNativePairFileState {
        let expected = try SharedMediaNativePairFileGraph.state(context: context, inventory: inventory, package: package, member: member)
        _ = try SharedMediaNativeAcquisitionBudget.evaluate(context: context, inventory: inventory)
        try beforeSave(); try authority.validate()
        guard try fresh().before == before else { throw SharedMediaStorageFailure.stale }
        do { try context.save(); try afterSave() }
        catch {
            let failure = error; context.rollback()
            guard (try? fresh().before) == expected else { throw failure }
        }
        guard try fresh().before == expected else { throw SharedMediaStorageFailure.stale }; return expected
    }
}

struct SharedMediaNativePairDisposal: Sendable {
    let state: SharedMediaNativePairFileState
    let binding: Data
    let epoch: UUID
    fileprivate init(state: SharedMediaNativePairFileState, binding: Data, epoch: UUID) {
        self.state = state; self.binding = binding; self.epoch = epoch
    }
}
