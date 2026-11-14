import Foundation
import SwiftData

/// Complete clean database evidence for one held release. This is not a whole
/// store audit, physical-absence capability, dirty poststate or mutation owner.
/// The caller must hold the native store fence. Production dispatch stays closed.
@MainActor
// The full domain name distinguishes this state or capability from adjacent storage boundaries.
// swiftlint:disable:next type_name
enum SharedMediaNativeReceivingReleaseLiveAudit {
    typealias Values = SharedMediaNativeReceivingReleaseValues
    typealias Origin = SharedMediaNativeReleaseOrigin
    typealias Facts = SharedMediaNativeAppMetadataFacts

    struct Witness {
        let progress: Values.Progress
        let origin: Origin.Snapshot
        let state: SharedMediaNativeReceivingReleaseState.Expected
        let slot: SharedMediaNativeReceivingIntentGraph.Row
    }

    /// Only this reader can construct the slot/origin/current-state binding.
    /// It is still partial evidence, never a complete-audit or cleanup witness.
    @MainActor
    struct PairContext {
        let progress: Values.Progress
        let origin: Origin.Snapshot
        fileprivate let state: SharedMediaNativeReceivingReleaseState.Expected
        fileprivate let contextID: ObjectIdentifier
        fileprivate let inventoryRevision: Int64
        fileprivate init(progress: Values.Progress, origin: Origin.Snapshot,
                         state: SharedMediaNativeReceivingReleaseState.Expected, context: ModelContext,
                         inventoryRevision: Int64) {
            self.progress = progress; self.origin = origin; self.state = state
            contextID = ObjectIdentifier(context); self.inventoryRevision = inventoryRevision
        }
        func require(_ context: ModelContext, inventory: SharedMediaInventoryRecord,
                     package: PhotoPreparationRecord, member: SharedMediaPendingMembershipRecord) throws {
            guard !context.hasChanges, contextID == ObjectIdentifier(context),
                  inventory.id == progress.plan.profile.inventoryID,
                  inventory.generation == progress.plan.profile.generation,
                  inventory.revision == inventoryRevision,
                  Facts.Package(package) == state.package, Facts.Member(member) == state.member else {
                throw SharedMediaStorageFailure.stale
            }
        }
    }

    static func read(packageID: UUID, inventoryID: UUID, context: ModelContext) throws -> Witness {
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        let inventory = try one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let profile = try SharedMediaNativeAppEligibility.profile(inventory)
        let scope = SharedMediaNativeScopeIdentity(inventoryID: inventoryID, generation: profile.generation,
            ownerID: profile.ownerID, storeIdentity: profile.storeIdentity, rootBinding: try profile.rootIdentity)
        let header = try SharedMediaNativeAppEligibility.snapshot(context: context, scope: scope)
        let saved = try one(context, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == packageID }))
        let slot = SharedMediaNativeReceivingIntentGraph.Row(saved)
        try slot.requireNoReleaseStart()
        try slot.requireNoAllocation()
        guard slot.version == 2, slot.phase == "releasing", slot.preparedData == nil,
              slot.cursor == packageID.uuidString.lowercased(), slot.inventoryID == inventoryID,
              slot.inventoryGeneration == profile.generation, slot.ownerID == profile.ownerID,
              let bytes = slot.resultData, slot.resultSHA256 == SharedMediaAcquisitionEncoding.digest(bytes) else {
            throw SharedMediaStorageFailure.conflict
        }
        let progress = try Values.Progress.decode(bytes), plan = progress.plan
        guard plan.profile == profile, plan.package.id == packageID, slot.draftGeneration == plan.package.generation,
              slot.operationID == plan.operationID, slot.preparedSHA256 == plan.preparedSHA256,
              header.bootstrapID == plan.preHeader.bootstrapID,
              header.bootstrapGeneration == plan.preHeader.bootstrapGeneration,
              header.bootstrapContract == plan.preHeader.bootstrapContract,
              header.bootstrapRevision == plan.preHeader.bootstrapRevision else { throw SharedMediaStorageFailure.conflict }
        let operationID = plan.operationID
        guard try context.fetchCount(FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.operationID == operationID })) == 1 else {
            throw SharedMediaStorageFailure.conflict
        }
        let origin = try Origin.read(plan, in: context).snapshot
        let expected = try SharedMediaNativeReceivingReleaseState.expected(progress,
            prepared: origin.prepared, received: origin.received)
        let package = try one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        let member = try one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        try expected.require(package: Facts.Package(package), member: Facts.Member(member),
            slotRevision: slot.revision, inventoryRevision: inventory.revision)
        // Derive from foreign keys, not saved membership IDs. This also rejects
        // unexpected package-owned references, pairs, work and transfers.
        let graph = try SharedMediaPendingGraph.deriveScoped(in: context, inventory: inventory,
            ownerID: profile.ownerID, format: .appV2)
        guard try graph.membership(packageID: packageID).encoded() == expected.member.bytes else {
            throw SharedMediaStorageFailure.conflict
        }
        let pairContext = PairContext(progress: progress, origin: origin, state: expected,
            context: context, inventoryRevision: inventory.revision)
        let cohort = try SharedMediaNativeFrozenCohort.decode(origin.prepared.cohort.bytes)
        for (index, target) in plan.targets.enumerated() {
            let state = progress.targets[index], entry = cohort.entries[index]
            let intent = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes)
            switch state.stage {
            case .readyPair, .retiringPair:
                try pair(target, state: state, entry: entry, release: pairContext,
                    package: package, member: member, inventory: inventory, context: context)
            case .pairGoneOriginalLive, .originalRetiring, .removed:
                try absentPair(target, context: context)
            }
            switch state.stage {
            case .readyPair, .retiringPair, .pairGoneOriginalLive, .originalRetiring:
                try original(target, state: state, intent: intent, inventory: inventory, context: context)
            case .removed:
                try SharedMediaNativeAppOriginalRows.absentReference(context, target.original.referenceID)
                if state.original?.disposition == .removed {
                    try absentOriginal(target, profile: profile, inventory: inventory, context: context)
                } else {
                    try sharedOriginal(target, selectedPackageID: packageID, intent: intent, profile: profile, inventory: inventory, context: context)
                }
                // Deleted closure bodies cannot be independently re-proven.
                // These branches consume the future sealed writer's atomic
                // Progress attestation plus current ownership/absence evidence.
            }
        }
        guard !context.hasChanges, header == (try SharedMediaNativeAppEligibility.snapshot(context: context, scope: scope)) else {
            throw SharedMediaStorageFailure.stale
        }
        return .init(progress: progress, origin: origin, state: expected, slot: slot)
    }

    private static func pair(_ target: Values.Target, state: Values.TargetProgress,
                             entry: SharedMediaNativeFrozenEntry, release: PairContext,
                             package: PhotoPreparationRecord, member: SharedMediaPendingMembershipRecord,
                             inventory: SharedMediaInventoryRecord, context: ModelContext) throws {
        let intent = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes), id = target.pairID
        let identity = intent.preparation, original = target.original
        let row = try one(context, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == id }))
        let retiring = state.stage == .retiringPair
        guard row.contractVersion == SharedMediaNativePairPlanGraph.contract,
              row.phaseRaw == (retiring ? "retiring" : "ready"), row.nonce == intent.nonce,
              row.previousPairID == nil, intent.previousPairID == nil,
              row.inventoryID == inventory.id, row.inventoryGeneration == inventory.generation,
              row.expectedInventoryRevision == (try SharedMediaStoragePolicy.add(identity.inventoryRevision, 1)),
              inventory.revision >= (try SharedMediaStoragePolicy.add(identity.inventoryRevision, 2)),
              row.packageID == package.id, row.ownerID == package.ownerID, row.draftGeneration == package.draftGeneration,
              row.expectedPackageRevision == (try SharedMediaStoragePolicy.add(identity.packageRevision, 1)),
              package.revision >= (try SharedMediaStoragePolicy.add(identity.packageRevision, 2)),
              member.revision >= (try SharedMediaStoragePolicy.add(identity.membershipRevision, 1)),
              row.originalReferenceID == original.referenceID, row.originalReferenceRevision == original.referenceRevision,
              row.originalAssetID == original.assetID, row.originalAssetGeneration == original.assetGeneration,
              row.ordinal == identity.original.ordinal, row.aiWorkID == target.ai.workID,
              row.displayWorkID == target.display.workID,
              try context.fetchCount(FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.pairID == id })) == 2 else {
            throw SharedMediaStorageFailure.conflict
        }
        if retiring {
            guard row.publishedRevision == nil else { throw SharedMediaStorageFailure.conflict }
        } else {
            guard case .preparation(let envelope) = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData) else {
                throw SharedMediaStorageFailure.conflict
            }
            try SharedMediaNativePairPlanGraph.validateReadyForMembership(envelope, pairID: id,
                package: package, inventory: inventory, context: context)
        }
        var epoch: UUID?
        for (input, descriptor) in [(intent.ai, entry.aiDescriptor), (intent.display, entry.displayDescriptor)] {
            let workID = input.id, assetID = input.assetID, referenceID = input.referenceID, leaseID = input.leaseID
            let work = try one(context, FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == workID }))
            guard work.pairID == id, work.roleRaw == input.role, work.assetID == assetID,
                  work.assetGeneration == input.assetGeneration, work.referenceID == referenceID, work.leaseID == leaseID,
                  work.byteCount == input.byteCount, work.sha256 == input.sha256, work.contentType == input.contentType,
                  work.finalIdentity == descriptor.file, epoch == nil || epoch == work.writerEpoch,
                  try context.fetchCount(FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.assetID == assetID })) == 1,
                  try context.fetchCount(FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.referenceID == referenceID })) == 1,
                  try context.fetchCount(FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.leaseID == leaseID })) == 1,
                  try context.fetchCount(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == assetID })) == 0 else {
                throw SharedMediaStorageFailure.conflict
            }
            epoch = work.writerEpoch
            if retiring {
                try SharedMediaNativePairFileGraph.validateHeld(work, input: input, pair: row, package: package,
                    member: member, inventory: inventory, release: release, context: context)
            }
        }
    }

    private static func original(_ target: Values.Target, state: Values.TargetProgress,
                                 intent: SharedMediaNativeDerivativeIntent, inventory: SharedMediaInventoryRecord,
                                 context: ModelContext) throws {
        let id = target.acquisitionID, source = target.original, expected = intent.preparation.original
        let receipt = try one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id }))
        guard case .completed(let request, let result) = try SharedMediaNativeAcquisitionGraph.scopedReceipt(receipt,
            inventory: inventory, context: context, format: .appV2),
              request.assetID == source.assetID, request.assetGeneration == source.assetGeneration,
              request.ownerID == source.ownerID, request.finalToken == expected.token,
              result.byteCount == expected.byteCount, result.sha256 == expected.sha256,
              result.contentType == expected.contentType, result.descriptor == expected.descriptor else {
            throw SharedMediaStorageFailure.conflict
        }
        let retiring = state.stage == .originalRetiring
        _ = try SharedMediaNativeAppOriginalRows.reference(context, source: source, live: !retiring, ordinal: expected.ordinal)
        let snapshot = try SharedMediaNativeOriginalAccounting.audit(assetID: source.assetID, inventoryID: inventory.id, context: context)
        if retiring {
            guard let proof = snapshot.retirement, let assertion = state.original,
                  assertion.disposition == .removed, assertion.retirementID == proof.retirementID,
                  assertion.closureSHA256 == SharedMediaAcquisitionEncoding.digest(Data(try proof.encoded().utf8)) else {
                throw SharedMediaStorageFailure.conflict
            }
        } else {
            guard snapshot.retirement == nil, snapshot.liveCount > 0 else { throw SharedMediaStorageFailure.conflict }
        }
    }

    private static func sharedOriginal(_ target: Values.Target, selectedPackageID: UUID, intent: SharedMediaNativeDerivativeIntent,
                                       profile: SharedMediaNativeAppProfile, inventory: SharedMediaInventoryRecord,
                                       context: ModelContext) throws {
        let id = target.acquisitionID, source = target.original, expected = intent.preparation.original
        let receipt = try one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id }))
        switch try SharedMediaNativeAcquisitionGraph.scopedReceipt(receipt, inventory: inventory, context: context, format: .appV2) {
        case .completed(let request, let result):
            guard request.assetID == source.assetID, request.assetGeneration == source.assetGeneration,
                  request.ownerID == source.ownerID, request.finalToken == expected.token,
                  result.byteCount == expected.byteCount, result.sha256 == expected.sha256,
                  result.contentType == expected.contentType, result.descriptor == expected.descriptor else {
                throw SharedMediaStorageFailure.conflict
            }
            // Saved shared disposition still requires a surviving logical owner.
            // Receipt identity alone cannot prove count/reference integrity.
            let original = try SharedMediaNativeOriginalAccounting.audit(assetID: source.assetID,
                inventoryID: inventory.id, context: context)
            guard original.liveCount > 0, original.retirement == nil else { throw SharedMediaStorageFailure.conflict }
            if request.packageID != selectedPackageID {
                try SharedMediaNativeOriginalLiability.requireRetainedSurvivors(assetID: source.assetID,
                    expectedCount: original.liveCount, context: context)
            }
        case .released:
            try absentOriginal(target, profile: profile, inventory: inventory, context: context)
        default: throw SharedMediaStorageFailure.conflict
        }
    }

    static func absentPair(_ target: Values.Target, context: ModelContext) throws {
        let id = target.pairID, original = target.original.referenceID
        guard try context.fetchCount(FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate {
            $0.id == id || $0.originalReferenceID == original
        })) == 0,
        try context.fetchCount(FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.pairID == id })) == 0 else {
            throw SharedMediaStorageFailure.conflict
        }
        for output in [target.ai, target.display] {
            let work = output.workID, asset = output.assetID, ref = output.referenceID, lease = output.leaseID
            guard try context.fetchCount(FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate {
                $0.id == work || $0.assetID == asset || $0.referenceID == ref || $0.leaseID == lease
            })) == 0,
            try context.fetchCount(FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == asset })) == 0,
            try context.fetchCount(FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == asset })) == 0,
            try context.fetchCount(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == ref || $0.assetID == asset })) == 0,
            try context.fetchCount(FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == ref || $0.allocationID == asset })) == 0,
            try context.fetchCount(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == lease || $0.assetID == asset })) == 0,
            try context.fetchCount(FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == lease || $0.allocationID == asset })) == 0,
            try context.fetchCount(FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == asset })) == 0,
            try context.fetchCount(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == asset })) == 0 else {
                throw SharedMediaStorageFailure.conflict
            }
        }
    }

    static func absentOriginal(_ target: Values.Target, profile: SharedMediaNativeAppProfile,
                               inventory: SharedMediaInventoryRecord, context: ModelContext) throws {
        let asset = target.original.assetID, id = target.acquisitionID
        let receipt = try one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id }))
        guard case .released(let terminal) = try SharedMediaNativeAcquisitionGraph.scopedReceipt(receipt,
            inventory: inventory, context: context, format: .appV2),
              terminal.operationID == id, terminal.inventoryID == profile.inventoryID,
              terminal.inventoryGeneration == profile.generation, terminal.ownerID == profile.ownerID,
              try context.fetchCount(FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == asset })) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == asset })) == 0,
              try context.fetchCount(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.assetID == asset })) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.allocationID == asset })) == 0,
              try context.fetchCount(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == id || $0.assetID == asset })) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == id || $0.allocationID == asset })) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == asset })) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == asset })) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.originalAssetID == asset })) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.assetID == asset })) == 0 else {
            throw SharedMediaStorageFailure.conflict
        }
    }

    private static func one<T: PersistentModel>(_ context: ModelContext, _ query: FetchDescriptor<T>) throws -> T {
        try SharedMediaNativePairPlanGraph.one(context, query)
    }
}
