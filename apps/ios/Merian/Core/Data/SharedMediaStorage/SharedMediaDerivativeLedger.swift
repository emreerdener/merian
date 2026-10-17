import Foundation
import SwiftData

/// Pair transitions occur in the inbox owner's one fenced transaction. No save,
/// file operation, provider callback or account acquisition occurs in this ledger.
@MainActor
final class SharedMediaDerivativeLedger {
    private let joint: SharedMediaPhotoTransaction
    private let inventory: SharedMediaInventoryRecord
    private let binding: SharedMediaPhotoBinding
    private var context: ModelContext { joint.context }
    init(joint: SharedMediaPhotoTransaction, inventory: SharedMediaInventoryRecord, binding: SharedMediaPhotoBinding) {
        self.joint = joint; self.inventory = inventory; self.binding = binding
    }

    private var purging: Bool { inventory.phaseRaw == "purgingP1" }

    func all() throws -> [SharedMediaDerivativePair] { try fetch(SharedMediaDerivativePairRecord.self, 9).map(value) }
    func saved(_ request: SharedMediaDerivativeRequest) throws -> SharedMediaDerivativePair? {
        try request.validate()
        guard request.inventoryID == inventory.id, request.inventoryGeneration == inventory.generation else { throw SharedMediaStorageFailure.stale }
        guard let row = try fetch(SharedMediaDerivativePairRecord.self, 9).first(where: { $0.id == request.id }) else { return nil }
        let result = try value(row)
        guard result.request == request else { throw SharedMediaStorageFailure.conflict }; return result
    }

    func prepare(_ original: PhotoOriginalReference, ai: SharedMediaDerivativeInput,
                 display: SharedMediaDerivativeInput) throws -> SharedMediaDerivativeRequest {
        let (package, edge) = try originalRows(original)
        let pairs = try all()
        guard pairs.allSatisfy({ $0.phase == "ready" }), ["draftOwned", "needsAttention"].contains(package.phaseRaw),
              try fetch(SharedMediaInboxHandoffRecord.self, 8).allSatisfy({ $0.packageID != package.id }),
              try fetch(PhotoPreparationLease.self, 96).allSatisfy({ $0.packageID != package.id }) else { throw SharedMediaStorageFailure.inUse }
        let previous = pairs.filter { $0.request.original.referenceID == original.referenceID }
        guard previous.count <= 1 else { throw SharedMediaStorageFailure.conflict }
        let result = SharedMediaDerivativeRequest(id: UUID(), nonce: UUID(), inventoryID: inventory.id,
            inventoryGeneration: inventory.generation, expectedInventoryRevision: inventory.revision,
            original: original, ordinal: edge.ordinal, expectedPackageRevision: package.revision,
            previousPairID: previous.first?.request.id, ai: ai, display: display)
        try result.validate(); return result
    }

    func plan(_ request: SharedMediaDerivativeRequest, old: [SharedMediaDerivativeInspection]) throws -> SharedMediaDerivativePair {
        if let saved = try saved(request) { return saved }
        let (package, edge) = try originalRows(request.original), pairs = try all()
        guard request.expectedInventoryRevision == inventory.revision, request.expectedPackageRevision == package.revision,
              edge.ordinal == request.ordinal, pairs.allSatisfy({ $0.phase == "ready" }), pairs.count < 9,
              ["draftOwned", "needsAttention"].contains(package.phaseRaw),
              try fetch(SharedMediaInboxHandoffRecord.self, 8).allSatisfy({ $0.packageID != package.id }),
              try fetch(PhotoPreparationLease.self, 96).allSatisfy({ $0.packageID != package.id }) else { throw SharedMediaStorageFailure.stale }
        let previous = pairs.filter { $0.request.original.referenceID == request.original.referenceID }
        guard previous.count <= 1, previous.first?.request.id == request.previousPairID else { throw SharedMediaStorageFailure.stale }
        if let previous = previous.first { _ = try retire(previous.request, inspections: old) }
        else { guard old.isEmpty else { throw SharedMediaStorageFailure.conflict } }
        let original = request.original
        let row = SharedMediaDerivativePairRecord(id: request.id, nonce: request.nonce, inventoryID: inventory.id,
            inventoryGeneration: inventory.generation, expectedInventoryRevision: request.expectedInventoryRevision,
            ownerID: original.ownerID, packageID: original.packageID, draftGeneration: original.draftGeneration,
            originalReferenceID: original.referenceID, originalReferenceRevision: original.referenceRevision,
            originalAssetID: original.assetID, originalAssetGeneration: original.assetGeneration, ordinal: request.ordinal,
            expectedPackageRevision: request.expectedPackageRevision, aiWorkID: request.ai.id,
            displayWorkID: request.display.id, previousPairID: request.previousPairID)
        context.insert(row)
        for input in request.inputs {
            context.insert(SharedMediaDerivativeWorkRecord(id: input.id, pairID: row.id, roleRaw: input.role,
                assetID: input.assetID, assetGeneration: input.assetGeneration, referenceID: input.referenceID,
                leaseID: input.leaseID, writerEpoch: binding.epoch, byteCount: input.byteCount,
                sha256: input.sha256, contentType: input.contentType))
        }
        package.revision = try plus(package.revision, 1); package.phaseRaw = "needsAttention"
        return try value(row)
    }

    func reserve(_ request: SharedMediaDerivativeRequest) throws -> SharedMediaDerivativePair {
        let row = try exact(request), pair = try value(row)
        guard pair.phase == "planned", try all().allSatisfy({ $0.request.id != request.previousPairID }) else { throw SharedMediaStorageFailure.inUse }
        let (package, _) = try originalRows(request.original)
        guard package.revision == (try plus(request.expectedPackageRevision, 1)), package.phaseRaw == "needsAttention" else { throw SharedMediaStorageFailure.stale }
        for state in pair.work {
            let work = try exact(state)
            guard work.phaseRaw == "planned", work.writerStateRaw == "absent", work.writerEpoch == binding.epoch else { throw SharedMediaStorageFailure.stale }
            work.phaseRaw = "reserved"; work.writerStateRaw = "open"
            context.insert(PhotoPreparationLease(id: work.leaseID, packageID: row.packageID, assetID: work.assetID,
                ownerID: row.ownerID, processEpoch: work.writerEpoch, purposeRaw: "derivative",
                partialFileToken: state.token + ".partial", finalFileToken: state.token,
                reservedByteCount: work.byteCount, allocatedByteCount: 0, writerStateRaw: "open", terminalProof: nil))
            context.insert(SharedMediaAllocationRecord(id: work.assetID, inventoryID: inventory.id,
                accountID: row.ownerID, packageID: row.packageID, namespaceRaw: SharedMediaPhotoLedger.namespace,
                fileToken: state.token, poolRaw: "durable", stateRaw: "p1DerivativeReserved",
                materializedBytes: 0, reservedBytes: work.byteCount, physicalIdentity: nil))
            context.insert(SharedMediaLeaseRecord(id: work.leaseID, allocationID: work.assetID,
                processEpoch: work.writerEpoch, purposeRaw: "p1DerivativeV1", stateRaw: "open"))
        }
        row.phaseRaw = "writing"; return try value(row)
    }

    func partial(_ proof: SharedMediaDerivativePartial) throws -> SharedMediaDerivativePair {
        let work = try exact(proof.work), row = try exact(proof.work.request)
        try proofBinding(proof.binding, proof.epoch)
        guard row.phaseRaw == "writing", work.phaseRaw == "reserved", work.writerStateRaw == "open",
              work.writerEpoch == binding.epoch, proof.identity.bytes == 0 else { throw SharedMediaStorageFailure.conflict }
        work.partialDevice = proof.identity.device; work.partialInode = proof.identity.inode; work.phaseRaw = "writing"
        return try value(row)
    }

    func complete(_ proof: SharedMediaDerivativeCompletion) throws -> SharedMediaDerivativePair {
        let work = try exact(proof.work), row = try exact(proof.work.request)
        try proofBinding(proof.binding, proof.epoch)
        guard ["writing", "ready"].contains(row.phaseRaw), ["writing", "completed"].contains(work.phaseRaw),
              proof.file == proof.work.file, proof.identity.bytes == work.byteCount,
              proof.identity.device == work.partialDevice, proof.identity.inode == work.partialInode else { throw SharedMediaStorageFailure.conflict }
        if work.phaseRaw == "completed" {
            guard work.finalIdentity == proof.identity.exact else { throw SharedMediaStorageFailure.conflict }; return try value(row)
        }
        let (package, _) = try originalRows(proof.work.request.original)
        let allocation = try allocation(work), lease = try p1(work), shared = try shared(work)
        context.insert(PhotoPreparationAsset(id: work.assetID, ownerID: row.ownerID, generation: work.assetGeneration,
            fileToken: proof.work.token, contentType: work.contentType, byteCount: work.byteCount, sha256: work.sha256,
            acquisitionKindRaw: "sharedDerivative", cleanupStateRaw: "ready"))
        context.insert(PhotoPreparationReference(id: work.referenceID, packageID: row.packageID, assetID: work.assetID,
            ownerID: row.ownerID, roleRaw: work.roleRaw, ordinal: row.ordinal, revision: 0, isLive: true))
        context.insert(SharedMediaReferenceRecord(id: work.referenceID, allocationID: work.assetID, accountID: row.ownerID,
            ownerID: work.referenceID.uuidString.lowercased(), roleRaw: SharedMediaPhotoLedger.namespace, stateRaw: "live", revision: 0))
        work.phaseRaw = "completed"; work.writerStateRaw = "closed"; work.finalIdentity = proof.identity.exact
        allocation.stateRaw = "p1DerivativeMaterialized"; allocation.materializedBytes = work.byteCount
        allocation.reservedBytes = 0; allocation.physicalIdentity = proof.identity.exact
        lease.reservedByteCount = 0; lease.writerStateRaw = "closedPairWaiting"; shared.stateRaw = "closed"
        package.allocatedByteCount = try plus(package.allocatedByteCount, work.byteCount)
        return try value(row)
    }

    func close(_ proof: SharedMediaDerivativeClosure) throws -> SharedMediaDerivativePair {
        let work = try exact(proof.work), row = try exact(proof.work.request)
        try proofBinding(proof.binding, proof.epoch)
        guard row.phaseRaw != "retiring", work.retirementID == nil, proof.occupied >= 0,
              proof.occupied <= work.byteCount else { throw SharedMediaStorageFailure.conflict }
        if work.phaseRaw == "planned" || work.phaseRaw == "completed" { return try value(row) }
        work.writerStateRaw = "closed"
        let a = try allocation(work), lease = try p1(work)
        a.stateRaw = "p1DerivativeHeld"; a.materializedBytes = proof.occupied; a.reservedBytes = work.byteCount - proof.occupied
        lease.writerStateRaw = "closedDerivativeHeld"; try shared(work).stateRaw = "closed"
        return try value(row)
    }

    func publish(_ request: SharedMediaDerivativeRequest) throws -> SharedMediaDerivativePair {
        let row = try exact(request), pair = try value(row)
        if row.phaseRaw == "ready" { return pair }
        let (package, _) = try originalRows(request.original)
        guard row.phaseRaw == "writing", package.revision == (try plus(request.expectedPackageRevision, 1)),
              pair.work.allSatisfy({ $0.phase == "completed" && $0.writerState == "closed" && $0.finalIdentity != nil }) else { throw SharedMediaStorageFailure.inUse }
        for state in pair.work { context.delete(try p1(exact(state))) }
        package.revision = try plus(package.revision, 1); package.phaseRaw = "draftOwned"
        row.phaseRaw = "ready"; row.publishedRevision = package.revision
        return try value(row)
    }

    func retire(_ request: SharedMediaDerivativeRequest, inspections: [SharedMediaDerivativeInspection]) throws -> SharedMediaDerivativePair {
        let row = try exact(request), pair = try value(row)
        guard row.phaseRaw != "retiring", inspections.count == 2,
              Set(inspections.map { $0.work.input.id }) == Set(pair.work.map { $0.input.id }) else { throw SharedMediaStorageFailure.inUse }
        let (package, _) = try originalRows(request.original)
        guard purging || ["draftOwned", "needsAttention"].contains(package.phaseRaw) else { throw PhotoPreparationFailure.immutablePackage }
        for inspection in inspections {
            try proofBinding(inspection.binding, inspection.epoch)
            let work = try exact(inspection.work)
            guard work.pairID == row.id, ["absent", "closed"].contains(work.writerStateRaw) else { throw SharedMediaStorageFailure.inUse }
            let refs = try fetch(PhotoPreparationReference.self, 128).filter { $0.assetID == work.assetID }
            guard refs.count == (work.finalIdentity == nil ? 0 : 1), refs.allSatisfy({ $0.id == work.referenceID }) else { throw SharedMediaStorageFailure.inUse }
            work.retirementID = UUID(); work.retirementPartialIdentity = inspection.identity.partial
            work.retirementFinalIdentity = inspection.identity.final; work.retirementParentIdentity = inspection.identity.parent
            work.retirementNamespaceIdentity = inspection.identity.namespace; work.phaseRaw = "retiring"
            if work.writerStateRaw != "absent" { try allocation(work).stateRaw = "p1DerivativeRetiring" }
            if let edge = refs.first {
                edge.isLive = false; edge.revision = 1
                let sharedEdge = try one(SharedMediaReferenceRecord.self, id: edge.id, maximum: 144)
                sharedEdge.stateRaw = "retired"; sharedEdge.revision = 1
                try one(PhotoPreparationAsset.self, id: work.assetID, maximum: 96).cleanupStateRaw = "retiring"
            }
        }
        row.phaseRaw = "retiring"; try originalRows(request.original).0.phaseRaw = purging ? "purging" : "needsAttention"
        return try value(row)
    }

    func release(_ request: SharedMediaDerivativeRequest, proofs: [SharedMediaDerivativeRelease]) throws {
        let row = try exact(request), pair = try value(row)
        guard row.phaseRaw == "retiring", proofs.count == 2,
              Set(proofs.map { $0.retirement.work.input.id }) == Set(pair.work.map { $0.input.id }) else { throw SharedMediaStorageFailure.conflict }
        let (package, _) = try originalRows(request.original)
        let replacing = try all().contains { $0.request.id != row.id && $0.request.previousPairID == row.id && $0.phase == "planned" }
        let works = try proofs.map { proof -> SharedMediaDerivativeWorkRecord in
            try proofBinding(proof.retirement.binding, proof.retirement.epoch)
            let work = try exact(proof.retirement.work)
            guard work.pairID == row.id, proof.retirement.identity == (try retirementIdentity(proof.retirement.work)) else { throw SharedMediaStorageFailure.conflict }
            return work
        }
        var removed: Int64 = 0
        for (proof, work) in zip(proofs, works) {
            let intent = proof.retirement
            try proofBinding(intent.binding, intent.epoch)
            let refs = try fetch(PhotoPreparationReference.self, 128).filter { $0.assetID == work.assetID }
            guard refs.count == (work.finalIdentity == nil ? 0 : 1), refs.allSatisfy({ $0.id == work.referenceID && !$0.isLive }) else { throw SharedMediaStorageFailure.inUse }
            if work.finalIdentity != nil {
                context.delete(try one(PhotoPreparationAsset.self, id: work.assetID, maximum: 96))
                context.delete(try one(PhotoPreparationReference.self, id: work.referenceID, maximum: 128))
                context.delete(try one(SharedMediaReferenceRecord.self, id: work.referenceID, maximum: 144))
                removed = try plus(removed, work.byteCount)
            }
            if work.writerStateRaw != "absent" {
                context.delete(try allocation(work)); context.delete(try shared(work))
                if let lease = try fetch(PhotoPreparationLease.self, 96).first(where: { $0.id == work.leaseID }) { context.delete(lease) }
            }
            context.delete(work)
        }
        guard package.allocatedByteCount >= removed else { throw SharedMediaStorageFailure.conflict }
        package.allocatedByteCount -= removed
        context.delete(row)
        if !replacing { package.revision = try plus(package.revision, 1) }
        package.phaseRaw = purging ? "purging" : "needsAttention"
    }

    func retirementIdentity(_ state: SharedMediaDerivativeWork) throws -> SharedMediaInboxDestinationRetirementIdentity {
        let work = try exact(state)
        guard work.phaseRaw == "retiring", work.retirementID != nil,
              let partial = work.retirementPartialIdentity, let final = work.retirementFinalIdentity,
              let parent = work.retirementParentIdentity, let namespace = work.retirementNamespaceIdentity else { throw SharedMediaStorageFailure.inUse }
        return .init(partial: partial, final: final, parent: parent, namespace: namespace)
    }

    /// Returns only the exactly joined derivative P1 leases that the original
    /// handoff validator must exclude. Purpose strings alone grant no exclusion.
    func validate() throws -> Set<UUID> {
        let rows = try fetch(SharedMediaDerivativePairRecord.self, 9), pairs = try all()
        let works = try fetch(SharedMediaDerivativeWorkRecord.self, 18)
        let allocations = try fetch(SharedMediaAllocationRecord.self, 104)
        let assets = try fetch(PhotoPreparationAsset.self, 96), refs = try fetch(PhotoPreparationReference.self, 128)
        let leases = try fetch(PhotoPreparationLease.self, 96), sharedLeases = try fetch(SharedMediaLeaseRecord.self, 104)
        guard works.count == rows.count * 2, Set(rows.map(\.id)).count == rows.count,
              Set(rows.map(\.nonce)).count == rows.count, Set(works.map(\.id)).count == works.count,
              Set(works.map(\.assetID)).count == works.count, Set(works.map(\.referenceID)).count == works.count,
              Set(works.map(\.leaseID)).count == works.count else { throw SharedMediaStorageFailure.conflict }
        let unfinished = pairs.filter { $0.phase != "ready" }
        guard unfinished.count <= 2 else { throw SharedMediaStorageFailure.inUse }
        if unfinished.count == 2 {
            guard let planned = unfinished.first(where: { $0.phase == "planned" }),
                  unfinished.contains(where: { $0.phase == "retiring" && $0.request.id == planned.request.previousPairID }) else { throw SharedMediaStorageFailure.conflict }
        }
        let current = pairs.filter { $0.phase != "retiring" }
        guard Set(current.map { $0.request.original.referenceID }).count == current.count else { throw SharedMediaStorageFailure.conflict }
        var expectedP1 = Set<UUID>(), expectedAllocations = Set<UUID>(), expectedReferences = Set<UUID>()
        for row in rows {
            let pair = try value(row), request = pair.request
            try request.validate()
            let (package, original) = try originalRows(request.original)
            guard row.contractVersion == "sharedDerivativeV1", row.inventoryID == inventory.id,
                  row.inventoryGeneration == inventory.generation, row.expectedInventoryRevision <= inventory.revision,
                  request.ordinal == original.ordinal, ["planned", "writing", "ready", "retiring"].contains(pair.phase),
                  pair.work.count == 2 else { throw SharedMediaStorageFailure.conflict }
            if ["planned", "writing"].contains(pair.phase) {
                guard row.publishedRevision == nil, (package.phaseRaw == "needsAttention" || (purging && package.phaseRaw == "purging")),
                      package.revision == (try plus(request.expectedPackageRevision, 1)) else { throw SharedMediaStorageFailure.conflict }
            }
            if pair.phase == "ready" {
                guard row.publishedRevision == (try plus(request.expectedPackageRevision, 2)),
                      package.revision >= (row.publishedRevision ?? Int64.max) else { throw SharedMediaStorageFailure.conflict }
            }
            if pair.phase == "retiring" { guard package.phaseRaw == "needsAttention" || (purging && package.phaseRaw == "purging") else { throw SharedMediaStorageFailure.conflict } }
            for state in pair.work {
                let input = state.input, retiring = pair.phase == "retiring", completed = state.finalIdentity != nil
                let allocated = state.writerState != "absent"
                let expectedPhases: [String] = pair.phase == "planned" ? ["planned"] : (retiring ? ["retiring"] : (pair.phase == "ready" ? ["completed"] : ["reserved", "writing", "completed"]))
                guard expectedPhases.contains(state.phase), ["absent", "open", "closed"].contains(state.writerState),
                      (state.device == nil) == (state.inode == nil),
                      (state.retirementID != nil) == retiring,
                      !completed || (state.inode != nil && state.writerState == "closed"),
                      state.phase != "completed" || completed,
                      state.phase != "writing" || state.inode != nil,
                      state.phase != "reserved" || state.inode == nil,
                      state.phase != "planned" || (state.writerState == "absent" && state.inode == nil && !completed),
                      state.writerState != "absent" || (state.inode == nil && !completed),
                      input.assetID != request.original.assetID else { throw SharedMediaStorageFailure.conflict }
                let retirementFields = [state.retirementPartial, state.retirementFinal, state.retirementParent, state.retirementNamespace]
                if retiring {
                    guard ["absent", "closed"].contains(state.writerState),
                          retirementFields.allSatisfy({ $0.map { !$0.isEmpty && $0.utf8.count <= 512 } ?? false }),
                          state.retirementNamespace != "absent" else { throw SharedMediaStorageFailure.conflict }
                } else { guard retirementFields.allSatisfy({ $0 == nil }) else { throw SharedMediaStorageFailure.conflict } }
                let asset = assets.first { $0.id == input.assetID }, reference = refs.first { $0.id == input.referenceID }
                guard (asset != nil) == completed, (reference != nil) == completed else { throw SharedMediaStorageFailure.conflict }
                if completed {
                    expectedReferences.insert(input.referenceID)
                    guard let asset, let reference, asset.ownerID == request.original.ownerID, asset.generation == input.assetGeneration,
                          asset.fileToken == state.token, asset.byteCount == input.byteCount, asset.sha256 == input.sha256,
                          asset.contentType == input.contentType, asset.acquisitionKindRaw == "sharedDerivative",
                          asset.cleanupStateRaw == (retiring ? "retiring" : "ready"),
                          reference.ownerID == request.original.ownerID, reference.packageID == package.id,
                          reference.assetID == input.assetID, reference.roleRaw == input.role, reference.ordinal == request.ordinal,
                          reference.isLive == !retiring, reference.revision == (retiring ? 1 : 0),
                          refs.filter({ $0.assetID == input.assetID }).count == 1 else { throw SharedMediaStorageFailure.conflict }
                }
                let a = allocations.first { $0.id == input.assetID }, shared = sharedLeases.first { $0.id == input.leaseID }
                guard (a != nil) == allocated, (shared != nil) == allocated else { throw SharedMediaStorageFailure.conflict }
                if allocated {
                    expectedAllocations.insert(input.assetID)
                    let stateName = retiring ? "p1DerivativeRetiring" : (completed ? "p1DerivativeMaterialized" : (state.writerState == "open" ? "p1DerivativeReserved" : "p1DerivativeHeld"))
                    guard let a, let shared, a.inventoryID == inventory.id, a.accountID == request.original.ownerID,
                          a.packageID == package.id, a.namespaceRaw == SharedMediaPhotoLedger.namespace,
                          a.fileToken == state.token, a.poolRaw == "durable", a.stateRaw == stateName,
                          a.materializedBytes >= 0, a.reservedBytes >= 0,
                          try plus(a.materializedBytes, a.reservedBytes) == input.byteCount,
                          !completed || (a.materializedBytes == input.byteCount && a.reservedBytes == 0),
                          a.physicalIdentity == state.finalIdentity,
                          shared.allocationID == input.assetID, shared.processEpoch == state.writerEpoch,
                          shared.purposeRaw == "p1DerivativeV1", shared.stateRaw == state.writerState else { throw SharedMediaStorageFailure.conflict }
                }
                let needsLease = allocated && pair.phase != "ready" && !(retiring && pair.publishedRevision != nil)
                let lease = leases.first { $0.id == input.leaseID }
                guard (lease != nil) == needsLease else { throw SharedMediaStorageFailure.conflict }
                if needsLease {
                    expectedP1.insert(input.leaseID)
                    guard let lease, lease.packageID == package.id, lease.assetID == input.assetID,
                          lease.ownerID == request.original.ownerID, lease.processEpoch == state.writerEpoch,
                          lease.purposeRaw == "derivative", lease.sourceIdentity == nil, lease.terminalProof == nil,
                          lease.allocatedByteCount == 0, lease.reservedByteCount == (completed ? 0 : input.byteCount),
                          lease.finalFileToken == state.token, lease.partialFileToken == state.token + ".partial",
                          lease.writerStateRaw == (completed ? "closedPairWaiting" : (state.writerState == "open" ? "open" : "closedDerivativeHeld")) else { throw SharedMediaStorageFailure.conflict }
                }
            }
        }
        guard Set(allocations.filter { $0.stateRaw.hasPrefix("p1Derivative") }.map(\.id)) == expectedAllocations,
              Set(sharedLeases.filter { $0.purposeRaw == "p1DerivativeV1" }.map(\.allocationID)) == expectedAllocations,
              Set(leases.filter { $0.purposeRaw == "derivative" }.map(\.id)) == expectedP1,
              Set(refs.filter { $0.roleRaw != "original" }.map(\.id)) == expectedReferences else { throw SharedMediaStorageFailure.conflict }
        // Live cohorts include prospective planned/reserved inputs before old
        // retirement. Retiring bytes still count in package/physical budgets.
        for package in try fetch(PhotoPreparationRecord.self, 4) {
            for role in [PhotoPreparationRole.aiInput, .display] {
                let live = refs.filter { $0.packageID == package.id && $0.roleRaw == role.rawValue && $0.isLive }
                let pending = pairs.filter { $0.request.original.packageID == package.id && $0.phase != "retiring" }
                    .flatMap(\.work).filter { $0.input.role == role.rawValue && $0.finalIdentity == nil }
                let ordinals = live.map(\.ordinal) + pending.map { $0.request.ordinal }
                let amount = try PhotoPreparationPolicy.add(live.compactMap { ref in assets.first { $0.id == ref.assetID }?.byteCount } + pending.map { $0.input.byteCount })
                guard ordinals.count <= 2, Set(ordinals).count == ordinals.count,
                      amount <= (role == .aiInput ? PhotoPreparationPolicy.aiCohort : PhotoPreparationPolicy.displayCohort) else { throw SharedMediaStorageFailure.capacity }
            }
        }
        return expectedP1
    }

    private func fetch<T: PersistentModel>(_ type: T.Type, _ maximum: Int) throws -> [T] {
        var query = FetchDescriptor<T>(); query.fetchLimit = maximum + 1
        let rows = try context.fetch(query)
        guard rows.count <= maximum else { throw SharedMediaStorageFailure.conflict }; return rows
    }
    private func one<T: PersistentModel>(_ type: T.Type, id: UUID, maximum: Int) throws -> T {
        // These typed records share no mutable generic protocol surface.
        let matches = try fetch(type, maximum).filter { row in
            if let row = row as? PhotoPreparationAsset { return row.id == id }
            if let row = row as? PhotoPreparationReference { return row.id == id }
            if let row = row as? SharedMediaReferenceRecord { return row.id == id }
            return false
        }
        guard matches.count == 1, let row = matches.first else { throw SharedMediaStorageFailure.conflict }; return row
    }
    private func originalRows(_ handle: PhotoOriginalReference) throws -> (PhotoPreparationRecord, PhotoPreparationReference) {
        try handle.validate()
        guard let package = try fetch(PhotoPreparationRecord.self, 4).first(where: { $0.id == handle.packageID }),
              package.ownerID == handle.ownerID, package.draftGeneration == handle.draftGeneration, !package.retirementRequested,
              let edge = try fetch(PhotoPreparationReference.self, 128).first(where: { $0.id == handle.referenceID }),
              edge.ownerID == handle.ownerID, edge.packageID == handle.packageID, edge.assetID == handle.assetID,
              edge.roleRaw == "original", edge.isLive, edge.revision == handle.referenceRevision,
              let asset = try fetch(PhotoPreparationAsset.self, 96).first(where: { $0.id == handle.assetID }),
              asset.ownerID == handle.ownerID, asset.generation == handle.assetGeneration, asset.cleanupStateRaw == "ready" else { throw SharedMediaStorageFailure.stale }
        return (package, edge)
    }
    private func exact(_ request: SharedMediaDerivativeRequest) throws -> SharedMediaDerivativePairRecord {
        guard try saved(request) != nil,
              let row = try fetch(SharedMediaDerivativePairRecord.self, 9).first(where: { $0.id == request.id }) else { throw SharedMediaStorageFailure.stale }; return row
    }
    private func exact(_ state: SharedMediaDerivativeWork) throws -> SharedMediaDerivativeWorkRecord {
        guard let pair = try saved(state.request), pair.work.contains(state),
              let work = try fetch(SharedMediaDerivativeWorkRecord.self, 18).first(where: { $0.id == state.input.id }) else { throw SharedMediaStorageFailure.stale }; return work
    }
    private func allocation(_ w: SharedMediaDerivativeWorkRecord) throws -> SharedMediaAllocationRecord {
        guard let row = try fetch(SharedMediaAllocationRecord.self, 104).first(where: { $0.id == w.assetID }) else { throw SharedMediaStorageFailure.conflict }; return row
    }
    private func p1(_ w: SharedMediaDerivativeWorkRecord) throws -> PhotoPreparationLease {
        guard let row = try fetch(PhotoPreparationLease.self, 96).first(where: { $0.id == w.leaseID }) else { throw SharedMediaStorageFailure.conflict }; return row
    }
    private func shared(_ w: SharedMediaDerivativeWorkRecord) throws -> SharedMediaLeaseRecord {
        guard let row = try fetch(SharedMediaLeaseRecord.self, 104).first(where: { $0.id == w.leaseID }) else { throw SharedMediaStorageFailure.conflict }; return row
    }
    private func proofBinding(_ bytes: Data, _ epoch: UUID) throws {
        guard bytes == binding.bytes, epoch == binding.epoch else { throw SharedMediaStorageFailure.stale }
    }
    private func plus(_ a: Int64, _ b: Int64) throws -> Int64 { try SharedMediaStoragePolicy.add(a, b) }
    private func value(_ r: SharedMediaDerivativePairRecord) throws -> SharedMediaDerivativePair {
        let work = try fetch(SharedMediaDerivativeWorkRecord.self, 18)
        guard let ai = work.first(where: { $0.id == r.aiWorkID && $0.pairID == r.id }),
              let display = work.first(where: { $0.id == r.displayWorkID && $0.pairID == r.id }) else { throw SharedMediaStorageFailure.conflict }
        func input(_ w: SharedMediaDerivativeWorkRecord) -> SharedMediaDerivativeInput {
            .init(id: w.id, role: w.roleRaw, assetID: w.assetID, assetGeneration: w.assetGeneration,
                referenceID: w.referenceID, leaseID: w.leaseID, byteCount: w.byteCount, sha256: w.sha256, contentType: w.contentType)
        }
        let request = SharedMediaDerivativeRequest(id: r.id, nonce: r.nonce, inventoryID: r.inventoryID,
            inventoryGeneration: r.inventoryGeneration, expectedInventoryRevision: r.expectedInventoryRevision,
            original: .init(ownerID: r.ownerID, packageID: r.packageID, referenceID: r.originalReferenceID,
                assetID: r.originalAssetID, assetGeneration: r.originalAssetGeneration,
                draftGeneration: r.draftGeneration, referenceRevision: r.originalReferenceRevision),
            ordinal: r.ordinal, expectedPackageRevision: r.expectedPackageRevision, previousPairID: r.previousPairID,
            ai: input(ai), display: input(display))
        return .init(request: request, phase: r.phaseRaw, publishedRevision: r.publishedRevision, work: [ai, display].map { w in
            .init(request: request, input: input(w), writerEpoch: w.writerEpoch, phase: w.phaseRaw, writerState: w.writerStateRaw,
                device: w.partialDevice, inode: w.partialInode, finalIdentity: w.finalIdentity,
                retirementID: w.retirementID, retirementPartial: w.retirementPartialIdentity,
                retirementFinal: w.retirementFinalIdentity, retirementParent: w.retirementParentIdentity,
                retirementNamespace: w.retirementNamespaceIdentity)
        })
    }
}
