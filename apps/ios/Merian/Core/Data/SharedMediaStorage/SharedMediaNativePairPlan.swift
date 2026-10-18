import Foundation
import SwiftData

/// Exact current assertion for a durable plan, never file or mutation authority.
struct SharedMediaNativePairPlan: Codable, Equatable, Sendable {
    let intent: SharedMediaNativePreparationBlob
    let writerEpoch: UUID
    let inventoryID: UUID
    let inventoryGeneration: UUID
    let inventoryRevision: Int64
    let packageID: UUID
    let draftGeneration: UUID
    let packageRevision: Int64
    let envelope: Data
    let membershipRevision: Int64
    let membership: Data
}

/// Audit both directions globally. Planned rows have no physical ownership;
/// later stages require the typed file graph. Pending bounds are not library caps.
@MainActor
enum SharedMediaNativePairPlanGraph {
    static let contract = "nativeDerivativeV2"

    static func audit(context: ModelContext, inventory: SharedMediaInventoryRecord) throws {
        try page(context, FetchDescriptor<SharedMediaDerivativePairRecord>(sortBy: [SortDescriptor(\.id)])) { pair in
            let id = pair.packageID
            let package = try one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id }))
            guard case .preparation(let envelope) = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData) else {
                throw SharedMediaStorageFailure.conflict
            }
            try validate(envelope, package: package, inventory: inventory, context: context)
        }
        try page(context, FetchDescriptor<SharedMediaDerivativeWorkRecord>(sortBy: [SortDescriptor(\.id)])) { work in
            let id = work.pairID
            let pair = try one(context, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == id }))
            guard work.id == pair.aiWorkID || work.id == pair.displayWorkID else { throw SharedMediaStorageFailure.conflict }
        }
        // There is one actual processing lifetime across this inventory. Other
        // packages may retain originals, but no second incomplete plan/attempt.
        let active = try context.fetchCount(FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.phaseRaw != "ready" }))
        let attempts = try context.fetchCount(FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.phaseRaw == "preparing" }))
        guard active <= 1, attempts <= 1, active == 0 || attempts == 0 else { throw SharedMediaStorageFailure.conflict }
    }

    static func validate(_ envelope: SharedMediaNativeDraftEnvelope.V2, package: PhotoPreparationRecord,
                         inventory: SharedMediaInventoryRecord, context: ModelContext) throws {
        guard envelope.intents.count <= 2,
              package.accountingTierRaw == "pending", !package.retirementRequested else { throw SharedMediaStorageFailure.closed }
        let packageID = package.id
        var query = FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.packageID == packageID }); query.fetchLimit = 3
        let pairs = try context.fetch(query)
        guard pairs.count == envelope.intents.count else { throw SharedMediaStorageFailure.conflict }
        let active = pairs.filter { $0.phaseRaw != "ready" }.count
        guard active <= 1, envelope.attempt == nil || active == 0 else { throw SharedMediaStorageFailure.conflict }
        if envelope.frozen != nil {
            guard active == 0 else { throw SharedMediaStorageFailure.conflict }
            try SharedMediaNativeFreezeGraph.validate(envelope, package: package, inventory: inventory, context: context)
        } else if envelope.attempt != nil {
            guard package.phaseRaw == "preparing" else { throw SharedMediaStorageFailure.conflict }
        } else if active > 0 {
            guard package.phaseRaw == "needsAttention" else { throw SharedMediaStorageFailure.conflict }
        } else {
            // Ready survivors coexist with original acquisition. The complete
            // acquisition auditor derives the exact package phase from its jobs.
            guard ["draftOwned", "acquiring", "needsAttention"].contains(package.phaseRaw) else { throw SharedMediaStorageFailure.conflict }
        }
        for blob in envelope.intents {
            try validate(blob, sequence: envelope.sequence, package: package, inventory: inventory, context: context)
        }
    }

    /// Membership rebuilding observes a dirty transition before its member row
    /// advances. Prove only this ready pair's lease-free physical joins here;
    /// the complete envelope/active-unit audit remains mandatory after rebuild.
    static func validateReadyForMembership(_ envelope: SharedMediaNativeDraftEnvelope.V2, pairID: UUID,
                                          package: PhotoPreparationRecord, inventory: SharedMediaInventoryRecord, context: ModelContext) throws {
        guard let blob = try select(envelope, pairID: pairID) else { throw SharedMediaStorageFailure.conflict }
        let pair = try one(context, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == pairID }))
        guard pair.phaseRaw == "ready" else { throw SharedMediaStorageFailure.conflict }
        try validate(blob, sequence: envelope.sequence, package: package, inventory: inventory, context: context)
    }

    static func select(_ envelope: SharedMediaNativeDraftEnvelope.V2, pairID: UUID?) throws -> SharedMediaNativePreparationBlob? {
        if let pairID { return try envelope.intents.first { try SharedMediaNativeDerivativeIntent.decode($0.bytes).pairID == pairID } }
        guard envelope.intents.count <= 1 else { throw SharedMediaStorageFailure.invalid }
        return envelope.intents.first
    }

    private static func validate(_ blob: SharedMediaNativePreparationBlob, sequence: Int64, package: PhotoPreparationRecord,
                                 inventory: SharedMediaInventoryRecord, context: ModelContext) throws {
        let intent = try SharedMediaNativeDerivativeIntent.decode(blob.bytes), identity = intent.preparation
        let original = identity.original.reference, id = intent.pairID, packageID = package.id
        let member = try one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        let pair = try one(context, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == id }))
        guard intent.previousPairID == nil, sequence >= identity.sequence,
              pair.contractVersion == contract, ["planned", "writing", "ready", "retiring"].contains(pair.phaseRaw),
              (pair.phaseRaw == "ready" ? pair.publishedRevision.map { $0 >= identity.packageRevision + 2 && $0 <= package.revision } == true : pair.publishedRevision == nil),
              pair.id == intent.pairID, pair.nonce == intent.nonce, pair.previousPairID == nil,
              pair.inventoryID == inventory.id, pair.inventoryGeneration == inventory.generation,
              pair.expectedInventoryRevision == identity.inventoryRevision + 1,
              inventory.id == identity.inventoryID, inventory.generation == identity.inventoryGeneration,
              inventory.revision >= identity.inventoryRevision + 2,
              pair.packageID == packageID, pair.ownerID == package.ownerID,
              pair.draftGeneration == package.draftGeneration, pair.expectedPackageRevision == identity.packageRevision + 1,
              package.revision >= identity.packageRevision + 2, member.revision >= identity.membershipRevision + 1,
              original.packageID == packageID, original.ownerID == package.ownerID, original.draftGeneration == package.draftGeneration,
              pair.originalReferenceID == original.referenceID, pair.originalReferenceRevision == original.referenceRevision,
              pair.originalAssetID == original.assetID, pair.originalAssetGeneration == original.assetGeneration,
              pair.ordinal == identity.original.ordinal, pair.aiWorkID == intent.ai.id, pair.displayWorkID == intent.display.id,
              try context.fetchCount(FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.pairID == id })) == 2 else {
            throw SharedMediaStorageFailure.conflict
        }
        if pair.phaseRaw == "planned" {
            guard inventory.revision == identity.inventoryRevision + 2, package.revision == identity.packageRevision + 2,
                  member.revision == identity.membershipRevision + 1 else { throw SharedMediaStorageFailure.conflict }
        }
        let referenceID = original.referenceID, assetID = original.assetID
        let ref = try one(context, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == referenceID }))
        let asset = try one(context, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID }))
        let receipt = try one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == assetID }))
        guard ref.isLive, ref.roleRaw == "original", ref.packageID == packageID, ref.ownerID == package.ownerID,
              ref.assetID == assetID, ref.revision == original.referenceRevision, ref.ordinal == identity.original.ordinal,
              asset.generation == original.assetGeneration, asset.cleanupStateRaw == "ready",
              asset.fileToken == identity.original.token, asset.byteCount == identity.original.byteCount,
              asset.sha256 == identity.original.sha256, asset.contentType == identity.original.contentType,
              case .completed(_, let result) = try SharedMediaAcquisitionReceipt.read(receipt),
              result.descriptor == identity.original.descriptor else { throw SharedMediaStorageFailure.conflict }
        var epoch: UUID?
        for input in [intent.ai, intent.display] {
            let workID = input.id
            let work = try one(context, FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == workID }))
            try validate(work, input: input, pair: pair, package: package, inventory: inventory, context: context)
            guard epoch == nil || epoch == work.writerEpoch else { throw SharedMediaStorageFailure.conflict }
            epoch = work.writerEpoch
        }
    }

    static func state(context: ModelContext, inventory: SharedMediaInventoryRecord,
                      package: PhotoPreparationRecord, member: SharedMediaPendingMembershipRecord, pairID: UUID? = nil) throws -> SharedMediaNativePairPlan {
        guard case .preparation(let value) = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData),
              let blob = try select(value, pairID: pairID) else { throw SharedMediaStorageFailure.closed }
        try validate(value, package: package, inventory: inventory, context: context)
        let id = try SharedMediaNativeDerivativeIntent.decode(blob.bytes).ai.id
        let work = try one(context, FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == id }))
        return .init(intent: blob, writerEpoch: work.writerEpoch, inventoryID: inventory.id,
            inventoryGeneration: inventory.generation, inventoryRevision: inventory.revision,
            packageID: package.id, draftGeneration: package.draftGeneration, packageRevision: package.revision,
            envelope: package.supportingContextData, membershipRevision: member.revision, membership: member.membersData)
    }

    private static func validate(_ work: SharedMediaDerivativeWorkRecord, input: SharedMediaDerivativeInput,
                                 pair: SharedMediaDerivativePairRecord, package: PhotoPreparationRecord, inventory: SharedMediaInventoryRecord, context: ModelContext) throws {
        let assetID = input.assetID, referenceID = input.referenceID, leaseID = input.leaseID
        guard work.pairID == pair.id, work.roleRaw == input.role, work.assetID == assetID,
              work.assetGeneration == input.assetGeneration, work.referenceID == referenceID, work.leaseID == leaseID,
              work.byteCount == input.byteCount, work.sha256 == input.sha256, work.contentType == input.contentType,
              try context.fetchCount(FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.assetID == assetID })) == 1,
              try context.fetchCount(FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.referenceID == referenceID })) == 1,
              try context.fetchCount(FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.leaseID == leaseID })) == 1,
              try context.fetchCount(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == assetID })) == 0 else {
            throw SharedMediaStorageFailure.conflict
        }
        if pair.phaseRaw != "planned" {
            try SharedMediaNativePairFileGraph.validate(work, input: input, pair: pair, package: package, inventory: inventory, context: context)
            return
        }
        guard work.phaseRaw == "planned", work.writerStateRaw == "absent", work.partialDevice == nil, work.partialInode == nil,
              work.finalIdentity == nil, work.retirementID == nil, work.retirementPartialIdentity == nil,
              work.retirementFinalIdentity == nil, work.retirementParentIdentity == nil, work.retirementNamespaceIdentity == nil,
              try context.fetchCount(FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID })) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == assetID })) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == assetID })) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID })) == 0,
              try context.fetchCount(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == referenceID || $0.assetID == assetID })) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == referenceID || $0.allocationID == assetID })) == 0,
              try context.fetchCount(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == leaseID || $0.assetID == assetID })) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == leaseID || $0.allocationID == assetID })) == 0 else {
            throw SharedMediaStorageFailure.conflict
        }
    }

    static func one<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>) throws -> T {
        var query = descriptor; query.fetchLimit = 2; let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first else { throw SharedMediaStorageFailure.conflict }; return row
    }
    private static func page<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>, body: (T) throws -> Void) throws {
        var query = descriptor, offset = 0; query.fetchLimit = SharedMediaStoragePolicy.pageSize
        while true {
            try Task.checkCancellation(); query.fetchOffset = offset
            let rows = try context.fetch(query)
            for row in rows { try body(row) }
            if rows.count < SharedMediaStoragePolicy.pageSize { return }
            let (next, overflow) = offset.addingReportingOverflow(rows.count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }; offset = next
        }
    }
}
