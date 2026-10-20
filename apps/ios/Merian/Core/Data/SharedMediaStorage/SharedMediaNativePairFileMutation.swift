import Foundation
import SwiftData

/// File transitions use the existing native fence and a complete fresh witness.
/// No file descriptor, generic save, or caller-supplied mutation authority escapes.
@MainActor
final class SharedMediaNativePairFileMutation {
    private let container: ModelContainer
    @MainActor private enum Authority {
        case qualification(SharedMediaNativeMutationAuthority), app(SharedMediaNativeAppPairAuthority)
        var binding: SharedMediaNativeBinding {
            switch self { case .qualification(let value): return value.binding; case .app(let value): return value.binding }
        }
        func validate(_ container: ModelContainer) throws {
            switch self { case .qualification(let value): try value.validate(); case .app(let value): try value.validate(container) }
        }
    }
    private let authority: Authority
    private var appConsumed = false, appApplying = false
    private var appAvailableBytes: (() throws -> Int64)?
    private let context: ModelContext
    private let inventory: SharedMediaInventoryRecord
    private let package: PhotoPreparationRecord
    private let member: SharedMediaPendingMembershipRecord
    private let pair: SharedMediaDerivativePairRecord
    private let before: SharedMediaNativePairFileState

    convenience init(container: ModelContainer, inventoryID: UUID, packageID: UUID, authority: SharedMediaNativeMutationAuthority, pairID: UUID? = nil) throws {
        try self.init(container: container, inventoryID: inventoryID, packageID: packageID, authority: .qualification(authority), pairID: pairID)
    }
    convenience init(container: ModelContainer, witness: SharedMediaNativeAppPairFileWitness) throws {
        try self.init(container: container, inventoryID: witness.state.plan.inventoryID, packageID: witness.state.plan.packageID,
            authority: .app(.fresh(witness)), pairID: witness.state.intent().pairID)
    }
    convenience init(container: ModelContainer, recovery: SharedMediaNativeAppPairRecoveryWitness) throws {
        try self.init(container: container, inventoryID: recovery.state.plan.inventoryID, packageID: recovery.state.plan.packageID,
            authority: .app(.recovery(recovery)), pairID: recovery.state.intent().pairID)
    }
    private init(container: ModelContainer, inventoryID: UUID, packageID: UUID, authority: Authority, pairID: UUID?) throws {
        try authority.validate(container)
        self.container = container; self.authority = authority
        context = ModelContext(container); context.autosaveEnabled = false
        inventory = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        package = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        member = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        if case .qualification(let value) = authority {
            guard !value.binding.initializing, package.ownerID == value.ownerID,
                  value.binding.bytes == (try JSONEncoder().encode(["nativeQualificationV1", inventory.id.uuidString, inventory.storeIdentity, inventory.rootIdentity])) else {
                throw SharedMediaStorageFailure.closed
            }
            try SharedMediaNativeAcquisitionGraph.audit(context: context, inventoryID: inventoryID)
        } else if case .app(let value) = authority {
            guard value.preparation.facts.packages[packageID] != nil else { throw SharedMediaStorageFailure.closed }
        }
        before = try SharedMediaNativePairFileGraph.state(context: context, inventory: inventory, package: package, member: member, pairID: pairID)
        let selectedID = try before.intent().pairID
        pair = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == selectedID }))
    }
    func applyApp(availableBytes: @escaping () throws -> Int64, beforeSave: () throws -> Void, afterSave: () throws -> Void) throws -> SharedMediaNativePairFileState {
        guard case .app(let witness) = authority, !appConsumed else { throw SharedMediaStorageFailure.closed }
        appConsumed = true; appApplying = true; appAvailableBytes = availableBytes; defer { appApplying = false; appAvailableBytes = nil }
        switch witness.action {
        case .reserve: return try reserve(before, availableBytes: availableBytes(), beforeSave: beforeSave, afterSave: afterSave)
        case .partial(let proof): return try partial(proof, beforeSave: beforeSave, afterSave: afterSave)
        case .complete(let proof): return try complete(proof, beforeSave: beforeSave, afterSave: afterSave)
        case .publish(let proofs): return try publish(before, proofs: proofs, beforeSave: beforeSave, afterSave: afterSave)
        }
    }
    private func requireAppEntry() throws {
        if case .app = authority, !appApplying { throw SharedMediaStorageFailure.closed }
    }
    func state() -> SharedMediaNativePairFileState { before }
    func reserve(_ expected: SharedMediaNativePairFileState, availableBytes: Int64,
                 beforeSave: () throws -> Void, afterSave: () throws -> Void) throws -> SharedMediaNativePairFileState {
        try requireAppEntry()
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
        let budget = try budgetAfterTransition()
        try budget.totals.checkAvailable(availableBytes, additionalReservation: 0)
        return try save(beforeSave, afterSave)
    }

    func partial(_ proof: SharedMediaNativePairPartial, beforeSave: () throws -> Void,
                 afterSave: () throws -> Void) throws -> SharedMediaNativePairFileState {
        try requireAppEntry()
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
        try requireAppEntry()
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
        try requireAppEntry()
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

    private func rows(_ id: UUID) throws -> (SharedMediaDerivativeWorkRecord, SharedMediaDerivativeInput) {
        let (_, input) = try before.selected(id)
        return (try one(FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == id })), input)
    }
    private func one<T: PersistentModel>(_ query: FetchDescriptor<T>) throws -> T { try SharedMediaNativePairPlanGraph.one(context, query) }
    private func binding(_ bytes: Data, _ epoch: UUID) throws {
        try authority.validate(container)
        guard bytes == authority.binding.bytes, epoch == authority.binding.epoch else { throw SharedMediaStorageFailure.closed }
    }
    private func advance() throws {
        inventory.revision = try SharedMediaStoragePolicy.add(inventory.revision, 1)
        package.revision = try SharedMediaStoragePolicy.add(package.revision, 1)
        let bytes: Data
        if case .app(let witness) = authority { bytes = try SharedMediaNativeAppPairPoststate.membership(witness) }
        else { bytes = try SharedMediaPendingGraph.derive(in: context, inventory: inventory).membership(packageID: package.id).encoded() }
        if member.membersData != bytes { member.membersData = bytes; member.revision = try SharedMediaStoragePolicy.add(member.revision, 1) }
    }
    private func fresh() throws -> SharedMediaNativePairFileMutation {
        guard case .qualification(let value) = authority else { throw SharedMediaStorageFailure.closed }
        return try .init(container: container, inventoryID: inventory.id, packageID: package.id, authority: value, pairID: pair.id)
    }
    private func budgetAfterTransition() throws -> SharedMediaNativeAcquisitionBudget.Snapshot {
        if case .app(let witness) = authority {
            let proof = try SharedMediaNativeAppPairPoststate(context: context, inventory: inventory, package: package, member: member, witness: witness)
            return try SharedMediaNativeAcquisitionBudget.evaluatePairFilePoststate(context: context, inventory: inventory, proof: proof)
        }
        return try SharedMediaNativeAcquisitionBudget.evaluate(context: context, inventory: inventory)
    }
    private func save(_ beforeSave: () throws -> Void, _ afterSave: () throws -> Void) throws -> SharedMediaNativePairFileState {
        if case .app(let witness) = authority { return try saveApp(witness, beforeSave, afterSave) }
        let expected = try SharedMediaNativePairFileGraph.state(context: context, inventory: inventory, package: package, member: member, pairID: pair.id)
        _ = try SharedMediaNativeAcquisitionBudget.evaluate(context: context, inventory: inventory)
        try beforeSave(); try authority.validate(container)
        guard try fresh().before == before else { throw SharedMediaStorageFailure.stale }
        do { try context.save(); try afterSave() }
        catch {
            let failure = error; context.rollback()
            guard (try? fresh().before) == expected else { throw failure }
        }
        guard try fresh().before == expected else { throw SharedMediaStorageFailure.stale }; return expected
    }
    private func saveApp(_ witness: SharedMediaNativeAppPairAuthority, _ beforeSave: () throws -> Void,
                         _ afterSave: () throws -> Void) throws -> SharedMediaNativePairFileState {
        let proof = try SharedMediaNativeAppPairPoststate(context: context, inventory: inventory, package: package, member: member, witness: witness)
        func budget() throws {
            let value = try SharedMediaNativeAcquisitionBudget.evaluatePairFilePoststate(context: context, inventory: inventory, proof: proof)
            if case .reserve = witness.action {
                guard let appAvailableBytes else { throw SharedMediaStorageFailure.closed }
                try value.totals.checkAvailable(appAvailableBytes(), additionalReservation: 0)
            }
        }
        try budget(); try beforeSave(); try witness.validate(container); try budget()
        // All byte/namespace seals are synchronous and last before the save.
        try witness.seal()
        func acknowledge() throws -> SharedMediaNativePairFileState {
            try witness.beforeReadback()
            guard try witness.preparation.authority.header(container) == SharedMediaNativeAppMetadataFacts.successor(witness.preparation.expected) else { throw SharedMediaStorageFailure.stale }
            let read = ModelContext(container); read.autosaveEnabled = false
            try proof.validateSaved(read)
            let id = inventory.id
            let inv = try SharedMediaNativePairPlanGraph.one(read, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
            _ = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: read, inventory: inv, ownerID: proof.profile.ownerID, format: .appV2)
            return proof.expected
        }
        do { try context.save(); try afterSave() }
        catch {
            let failure = error; context.rollback()
            do { return try acknowledge() } catch { throw failure }
        }
        return try acknowledge()
    }

}

/// Minted only by the shared transition core. Each action proves an exact write
/// set and deterministic successor; it never opens a generic dirty projection.
@MainActor
struct SharedMediaNativeAppPairPoststate {
    let profile: SharedMediaNativeAppProfile
    let expected: SharedMediaNativePairFileState
    private let witness: SharedMediaNativeAppPairAuthority
    private let contextID: ObjectIdentifier
    private let inventoryID: PersistentIdentifier
    private let updates: Set<PersistentIdentifier>, inserts: Set<PersistentIdentifier>, deletes: Set<PersistentIdentifier>
    private let package: SharedMediaNativeAppMetadataFacts.Package
    private let member: SharedMediaNativeAppMetadataFacts.Member

    fileprivate init(context: ModelContext, inventory: SharedMediaInventoryRecord, package row: PhotoPreparationRecord,
                     member: SharedMediaPendingMembershipRecord, witness: SharedMediaNativeAppPairAuthority) throws {
        self.witness = witness; profile = witness.preparation.authority.profile
        contextID = ObjectIdentifier(context); inventoryID = inventory.persistentModelID
        let before = witness.state, intent = try before.intent(), facts = witness.preparation.facts
        guard let old = facts.packages[row.id], let oldMember = facts.members[row.id], old.envelope == before.plan.envelope,
              oldMember.bytes == before.plan.membership, old.phase == "needsAttention" else { throw SharedMediaStorageFailure.conflict }
        let bytes = try Self.membership(witness)
        let nextMember = bytes == oldMember.bytes ? oldMember : try oldMember.successor(bytes)
        self.member = nextMember
        var allocated = old.allocated, phase = before.phase, published = before.publishedRevision
        var changed: Set<PersistentIdentifier> = [inventory.persistentModelID, row.persistentModelID]
        if bytes != oldMember.bytes { changed.insert(member.persistentModelID) }
        var added = Set<PersistentIdentifier>(), removed = Set<PersistentIdentifier>()
        func one<T: PersistentModel>(_ q: FetchDescriptor<T>) throws -> T { try SharedMediaNativePairPlanGraph.one(context, q) }
        let pairID = intent.pairID
        switch witness.action {
        case .reserve:
            phase = "writing"
            changed.insert(try one(FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == pairID })).persistentModelID)
            for input in [intent.ai, intent.display] {
                let id = input.id, asset = input.assetID, lease = input.leaseID
                changed.insert(try one(FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == id })).persistentModelID)
                added.insert(try one(FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == asset })).persistentModelID)
                added.insert(try one(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == lease })).persistentModelID)
                added.insert(try one(FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == lease })).persistentModelID)
            }
        case .partial(let proof):
            let id = proof.workID
            changed.insert(try one(FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == id })).persistentModelID)
        case .complete(let proof):
            let (work, input) = try before.selected(proof.workID)
            guard work.phase == "writing" else { throw SharedMediaStorageFailure.closed }
            let id = work.id, asset = input.assetID, lease = input.leaseID, reference = input.referenceID
            allocated = try SharedMediaStoragePolicy.add(allocated, input.byteCount)
            changed.insert(try one(FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == id })).persistentModelID)
            changed.insert(try one(FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == asset })).persistentModelID)
            changed.insert(try one(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == lease })).persistentModelID)
            changed.insert(try one(FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == lease })).persistentModelID)
            added.insert(try one(FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == asset })).persistentModelID)
            added.insert(try one(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == reference })).persistentModelID)
            added.insert(try one(FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == reference })).persistentModelID)
            added.insert(try one(FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == asset })).persistentModelID)
        case .publish:
            phase = "ready"; published = try SharedMediaStoragePolicy.add(old.revision, 1)
            changed.insert(try one(FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == pairID })).persistentModelID)
            let leaseIDs = Set([intent.ai.leaseID, intent.display.leaseID])
            let local = context.deletedModelsArray.compactMap { $0 as? PhotoPreparationLease }
            let shared = context.deletedModelsArray.compactMap { $0 as? SharedMediaLeaseRecord }
            guard local.count == 2, shared.count == 2, Set(local.map(\.id)) == leaseIDs, Set(shared.map(\.id)) == leaseIDs else { throw SharedMediaStorageFailure.conflict }
            removed.formUnion(local.map(\.persistentModelID)); removed.formUnion(shared.map(\.persistentModelID))
        }
        let nextPackage = try old.successor(old.envelope, phase: phase == "ready" ? "draftOwned" : old.phase, allocated: allocated)
        self.package = nextPackage
        let plan = before.plan
        let nextPlan = SharedMediaNativePairPlan(intent: plan.intent, writerEpoch: plan.writerEpoch,
            inventoryID: plan.inventoryID, inventoryGeneration: plan.inventoryGeneration,
            inventoryRevision: try SharedMediaStoragePolicy.add(plan.inventoryRevision, 1), packageID: plan.packageID,
            draftGeneration: plan.draftGeneration, packageRevision: nextPackage.revision, envelope: plan.envelope,
            membershipRevision: nextMember.revision, membership: bytes)
        expected = .init(plan: nextPlan, phase: phase, publishedRevision: published, allocatedBytes: allocated,
            work: try before.work.map { try Self.work($0, action: witness.action) })
        updates = changed; inserts = added; deletes = removed
        try validate(context: context, inventory: inventory)
    }
    fileprivate static func membership(_ witness: SharedMediaNativeAppPairAuthority) throws -> Data {
        let old = try SharedMediaMembership.decode(witness.state.plan.membership), intent = try witness.state.intent()
        var groups = Dictionary(uniqueKeysWithValues: old.groups.map { ($0.kind, Set($0.ids)) })
        func add(_ kind: SharedMediaMembership.Kind, _ id: UUID) throws {
            guard groups[kind, default: []].insert(id).inserted else { throw SharedMediaStorageFailure.conflict }
        }
        switch witness.action {
        case .reserve:
            for input in [intent.ai, intent.display] { try add(.allocation, input.assetID); try add(.work, input.leaseID); try add(.lease, input.leaseID) }
        case .partial: break
        case .complete(let proof):
            let (_, input) = try witness.state.selected(proof.workID)
            try add(.asset, input.assetID); try add(.reference, input.referenceID); try add(.edge, input.referenceID)
        case .publish:
            for input in [intent.ai, intent.display] {
                guard groups[.work, default: []].remove(input.leaseID) != nil,
                      groups[.lease, default: []].remove(input.leaseID) != nil else { throw SharedMediaStorageFailure.conflict }
            }
        }
        return try SharedMediaMembership(groups: groups.filter { !$0.value.isEmpty }.map { kind, ids in
            .init(kind: kind, ids: ids.sorted { $0.uuidString < $1.uuidString })
        }.sorted { $0.kind.rawValue < $1.kind.rawValue }).encoded()
    }
    private static func work(_ old: SharedMediaNativePairFileState.Work, action: SharedMediaNativeAppPairAction) throws -> SharedMediaNativePairFileState.Work {
        var phase = old.phase, writer = old.writerState, device = old.device, inode = old.inode, final = old.finalIdentity
        switch action {
        case .reserve: phase = "reserved"; writer = "open"
        case .partial(let proof) where proof.workID == old.id: phase = "writing"; device = proof.identity.device; inode = proof.identity.inode
        case .complete(let proof) where proof.workID == old.id: phase = "completed"; writer = "closed"; final = proof.identity.exact
        default: break
        }
        return .init(id: old.id, writerEpoch: old.writerEpoch, phase: phase, writerState: writer, device: device,
            inode: inode, finalIdentity: final, retirementID: old.retirementID, retirementPartial: old.retirementPartial,
            retirementFinal: old.retirementFinal, retirementParent: old.retirementParent,
            retirementNamespace: old.retirementNamespace, closure: old.closure)
    }
    func validate(context: ModelContext, inventory: SharedMediaInventoryRecord) throws {
        guard ObjectIdentifier(context) == contextID, inventory.persistentModelID == inventoryID,
              try SharedMediaNativeAppEligibility.profile(inventory) == profile,
              inventory.revision == expected.plan.inventoryRevision,
              context.insertedModelsArray.count == inserts.count, Set(context.insertedModelsArray.map(\.persistentModelID)) == inserts,
              context.deletedModelsArray.count == deletes.count, Set(context.deletedModelsArray.map(\.persistentModelID)) == deletes,
              Set(context.changedModelsArray.map(\.persistentModelID)).subtracting(inserts).subtracting(deletes) == updates else { throw SharedMediaStorageFailure.conflict }
        try validateSaved(context)
    }
    fileprivate func validateSaved(_ context: ModelContext) throws {
        try witness.preparation.facts.validatePairPlan(context, package: package, member: member)
        let inventoryID = expected.plan.inventoryID, packageID = expected.plan.packageID
        let inventory = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let row = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        let membership = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        guard try SharedMediaNativePairFileGraph.state(context: context, inventory: inventory, package: row,
            member: membership, pairID: expected.intent().pairID) == expected else { throw SharedMediaStorageFailure.conflict }
    }
    func receivingBytes(_ consumer: SharedMediaConsumerRecord) throws -> Int64 { try witness.preparation.facts.receivingBytes(consumer) }
}
