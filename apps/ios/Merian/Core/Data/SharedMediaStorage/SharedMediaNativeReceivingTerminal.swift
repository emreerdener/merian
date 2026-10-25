import Foundation
import SwiftData

/// Clean historical database evidence only. No filesystem claim, deletion,
/// execution authority, or reconstruction of the deleted receiving quartet.
@MainActor
enum SharedMediaNativeReceivingTerminal {
    typealias Values = SharedMediaNativeReceivingReleaseValues
    typealias Row = SharedMediaNativeReceivingIntentGraph.Row
    struct Snapshot: Equatable {
        let row: Row
        let persistentID: PersistentIdentifier
        let value: Values.Released
        var bytes: Int64 { Int64(row.resultData!.count) }
    }

    static func revision(_ value: Values.Released) throws -> Int64 {
        try PhotoPreparationPolicy.add([value.plan.releasingRevision, 1]
            + value.outcomes.map { $0.original == .shared ? Int64(3) : Int64(4) })
    }

    static func read(_ row: SharedMediaReceivingIntentRecord, context: ModelContext,
                     inventory: SharedMediaInventoryRecord, checkpoint: () throws -> Void = {}) throws -> Snapshot {
        try Task.checkCancellation(); try checkpoint()
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        let saved = Row(row), profile = try SharedMediaNativeAppEligibility.profile(inventory)
        let scope = SharedMediaNativeScopeIdentity(inventoryID: profile.inventoryID, generation: profile.generation,
            ownerID: profile.ownerID, storeIdentity: profile.storeIdentity, rootBinding: try profile.rootIdentity)
        let header = try SharedMediaNativeAppEligibility.snapshot(context: context, scope: scope)
        guard saved.phase == "released", saved.version == 2, saved.preparedData == nil,
              saved.releaseStartData == nil, saved.releaseStartSHA256 == nil,
              let bytes = saved.resultData, bytes.count <= Int(PhotoPreparationPolicy.metadata),
              saved.resultSHA256 == SharedMediaAcquisitionEncoding.digest(bytes) else { throw SharedMediaStorageFailure.conflict }
        let value = try Values.Released.decode(bytes), plan = value.plan, id = plan.package.id
        guard saved.id == id, saved.cursor == id.uuidString.lowercased(),
              saved.inventoryID == profile.inventoryID, saved.inventoryGeneration == profile.generation,
              saved.ownerID == profile.ownerID, plan.profile == profile,
              saved.draftGeneration == plan.package.generation, saved.operationID == plan.operationID,
              saved.preparedSHA256 == plan.preparedSHA256, saved.revision == (try revision(value)),
              header.inventory.revision >= value.inventoryRevision,
              value.inventoryRevision >= (try PhotoPreparationPolicy.add([plan.preHeader.inventory.revision, 2]
                + value.outcomes.map { $0.original == .shared ? Int64(3) : Int64(4) })),
              header.inventory.generation == plan.preHeader.inventory.generation,
              header.inventory.phase == plan.preHeader.inventory.phase, header.inventory.cursor == plan.preHeader.inventory.cursor,
              header.bootstrapID == plan.preHeader.bootstrapID, header.bootstrapGeneration == plan.preHeader.bootstrapGeneration,
              header.bootstrapContract == plan.preHeader.bootstrapContract, header.bootstrapRevision == plan.preHeader.bootstrapRevision else {
            throw SharedMediaStorageFailure.stale
        }
        let operationID = plan.operationID
        guard try context.fetchCount(FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.operationID == operationID })) == 1,
              try context.fetchCount(FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id })) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id })) == 0,
              try context.fetchCount(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.packageID == id })) == 0,
              try context.fetchCount(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.packageID == id })) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.packageID == id })) == 0 else {
            throw SharedMediaStorageFailure.conflict
        }
        try SharedMediaNativeReceivingRows.requireAbsent(.init(plan), in: context)
        for (target, outcome) in zip(plan.targets, value.outcomes) {
            try checkpoint()
            try SharedMediaNativeReceivingReleaseLiveAudit.absentPair(target, context: context)
            try SharedMediaNativeAppOriginalRows.absentReference(context, target.original.referenceID)
            if outcome.original == .removed {
                try SharedMediaNativeReceivingReleaseLiveAudit.absentOriginal(target, profile: profile, inventory: inventory, context: context)
            } else {
                try sharedOriginal(target, inventory: inventory, context: context, checkpoint: checkpoint)
            }
        }
        try Task.checkCancellation(); try checkpoint()
        guard !context.hasChanges, Row(row) == saved,
              header == (try SharedMediaNativeAppEligibility.snapshot(context: context, scope: scope)) else { throw SharedMediaStorageFailure.stale }
        return .init(row: saved, persistentID: row.persistentModelID, value: value)
    }

    private static func sharedOriginal(_ target: Values.Target, inventory: SharedMediaInventoryRecord,
                                       context: ModelContext, checkpoint: () throws -> Void) throws {
        let id = target.acquisitionID, source = target.original
        let receipt = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id }))
        switch try SharedMediaNativeAcquisitionGraph.scopedReceipt(receipt, inventory: inventory, context: context, format: .appV2, checkpoint: checkpoint) {
        case .completed(let request, let result):
            guard request.assetID == source.assetID, request.assetGeneration == source.assetGeneration,
                  request.ownerID == source.ownerID,
                  SharedMediaAcquisitionEncoding.digest(Data(try result.descriptor.encoded().utf8)) == target.originalIdentitySHA256 else {
                throw SharedMediaStorageFailure.conflict
            }
            let original = try SharedMediaNativeOriginalAccounting.audit(assetID: source.assetID,
                inventoryID: inventory.id, context: context, checkpoint: checkpoint)
            if original.retirement != nil {
                try retiringSurvivor(target, original: original, inventory: inventory, context: context, checkpoint: checkpoint)
                return
            }
            guard original.liveCount > 0, original.retirement == nil else { throw SharedMediaStorageFailure.conflict }
            // Audit validates every current reference. Retained-only ownership
            // additionally proves the receiving handoff of every survivor.
            let assetID = source.assetID
            var q = FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.assetID == assetID }, sortBy: [SortDescriptor(\.id)])
            q.fetchLimit = SharedMediaStoragePolicy.pageSize
            var offset = 0
            while true {
                try checkpoint(); q.fetchOffset = offset
                let refs = try context.fetch(q)
                for ref in refs {
                    let packageID = ref.packageID
                    let package = try SharedMediaNativePairPlanGraph.one(context,
                        FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
                    if package.accountingTierRaw == "retained" {
                        try SharedMediaNativeOriginalLiability.requireRetainedReference(ref, context: context, checkpoint: checkpoint)
                    } else {
                        guard package.accountingTierRaw == "pending",
                              try context.fetchCount(FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID })) == 1 else {
                            throw SharedMediaStorageFailure.conflict
                        }
                    }
                }
                if refs.count < SharedMediaStoragePolicy.pageSize { break }
                let (next, overflow) = offset.addingReportingOverflow(refs.count)
                guard !overflow else { throw SharedMediaStorageFailure.capacity }; offset = next
            }
        case .released:
            try SharedMediaNativeReceivingReleaseLiveAudit.absentOriginal(target,
                profile: SharedMediaNativeAppEligibility.profile(inventory), inventory: inventory, context: context)
        default: throw SharedMediaStorageFailure.conflict
        }
    }

    /// Historical shared ownership may subsequently enter a recipient's own
    /// retirement. Validate that existing lifecycle without granting cleanup.
    /// Keep this call graph below TerminalScan/Budget/ScopedAudit: LiveAudit and
    /// the ordinary row reader are pure leaves and must never call those roots.
    private static func retiringSurvivor(_ target: Values.Target,
                                        original: SharedMediaNativeOriginalAccounting.Snapshot,
                                        inventory: SharedMediaInventoryRecord, context: ModelContext,
                                        checkpoint: () throws -> Void) throws {
        try Task.checkCancellation(); try checkpoint()
        guard original.liveCount == 0, let retirement = original.retirement else {
            throw SharedMediaStorageFailure.conflict
        }
        let assetID = target.original.assetID
        let ref = try SharedMediaNativeAppOriginalRows.one(context,
            FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.assetID == assetID }))
        let packageID = ref.packageID
        guard packageID != target.original.packageID, ref.id != target.original.referenceID,
              !ref.isLive, ref.ownerID == target.original.ownerID else { throw SharedMediaStorageFailure.conflict }
        let slots = try context.fetchCount(FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == packageID }))
        if slots == 0 {
            let profile = try SharedMediaNativeAppEligibility.profile(inventory)
            let facts = try SharedMediaNativeAppMetadataFacts.capture(context, profile: profile)
            try facts.requireNoIntent(packageID)
            let state = try SharedMediaNativeAppOriginalRows.retirementState(context, id: assetID,
                facts: facts, inventoryRevision: inventory.revision)
            let graph = try SharedMediaPendingGraph.deriveScoped(in: context, inventory: inventory,
                ownerID: profile.ownerID, format: .appV2)
            guard state.reference.referenceID == ref.id, state.reference.packageID == packageID,
                  state.identity == retirement, state.request.operationID == target.acquisitionID,
                  try graph.membership(packageID: packageID).encoded() == state.membershipBytes else {
                throw SharedMediaStorageFailure.conflict
            }
        } else {
            try Task.checkCancellation(); try checkpoint()
            let witness = try SharedMediaNativeReceivingReleaseLiveAudit.read(packageID: packageID,
                inventoryID: inventory.id, context: context)
            let matches = witness.progress.plan.targets.enumerated().filter { $0.element.original.referenceID == ref.id }
            guard matches.count == 1, let match = matches.first else { throw SharedMediaStorageFailure.conflict }
            let recipient = match.element, progress = witness.progress.targets[match.offset]
            guard recipient.original.assetID == assetID,
                  recipient.original.assetGeneration == target.original.assetGeneration,
                  recipient.original.ownerID == target.original.ownerID,
                  recipient.acquisitionID == target.acquisitionID,
                  recipient.originalIdentitySHA256 == target.originalIdentitySHA256,
                  progress.stage == .originalRetiring, progress.original?.disposition == .removed,
                  progress.original?.retirementID == retirement.retirementID,
                  progress.original?.closureSHA256 == SharedMediaAcquisitionEncoding.digest(Data(try retirement.encoded().utf8)) else {
                throw SharedMediaStorageFailure.conflict
            }
        }
        try Task.checkCancellation(); try checkpoint()
    }

}
