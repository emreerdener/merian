import Foundation
import SwiftData

/// Strict native V2 graph. Attempts and typed paired-file stages are admitted;
/// freeze requires its exact terminal graph; receiving consumers remain closed.
@MainActor
enum SharedMediaNativePreparationGraph {
    static func validate(_ envelope: SharedMediaNativeDraftEnvelope, package: PhotoPreparationRecord, context: ModelContext, scopedInventory: SharedMediaInventoryRecord? = nil) throws {
        guard case .preparation(let value) = envelope else { return }
        if !value.intents.isEmpty || value.frozen != nil {
            let inventory = try scopedInventory ?? one(context, FetchDescriptor<SharedMediaInventoryRecord>())
            try SharedMediaNativePairPlanGraph.validate(value, package: package, inventory: inventory, context: context)
        }
        guard let blob = value.attempt else { return }
        let attempt = try SharedMediaNativePreparationAttempt.decode(blob.bytes)
        let original = attempt.original.reference, refID = original.referenceID, assetID = original.assetID, packageID = package.id
        let member = try one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        let ref = try one(context, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == refID }))
        let asset = try one(context, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID }))
        let receipt = try one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == assetID }))
        let inventoryID = attempt.inventoryID
        let inventory = try one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        if let scopedInventory {
            guard inventory.id == scopedInventory.id, inventory.generation == scopedInventory.generation else { throw SharedMediaStorageFailure.conflict }
        }
        try requireIdleFiles(context, scopedInventory: scopedInventory)
        let previous = try SharedMediaNativeDraftEnvelope.decode(attempt.previousEnvelope)
        guard previous.attempt == nil, previous.intents == value.intents,
              try SharedMediaStoragePolicy.add(previous.sequence, 1) == attempt.sequence,
              try SharedMediaNativeDraftEnvelope.bytes(previous.contexts) == SharedMediaNativeDraftEnvelope.bytes(value.contexts),
              try SharedMediaNativeDraftEnvelope.bytes(previous.presentation) == SharedMediaNativeDraftEnvelope.bytes(value.presentation),
              package.accountingTierRaw == "pending", !package.retirementRequested, package.phaseRaw == "preparing",
              package.revision == attempt.packageRevision + 1, package.ownerID == original.ownerID,
              package.id == original.packageID, package.draftGeneration == original.draftGeneration,
              inventory.generation == attempt.inventoryGeneration, inventory.revision == attempt.inventoryRevision + 1,
              member.revision == attempt.membershipRevision, member.membersData == attempt.membershipBytes,
              ref.packageID == package.id, ref.ownerID == original.ownerID, ref.assetID == assetID, ref.isLive,
              ref.revision == original.referenceRevision, ref.ordinal == attempt.original.ordinal, ref.roleRaw == "original",
              asset.generation == original.assetGeneration, asset.cleanupStateRaw == "ready",
              asset.fileToken == attempt.original.token, asset.byteCount == attempt.original.byteCount,
              asset.sha256 == attempt.original.sha256, asset.contentType == attempt.original.contentType,
              case .completed(_, let result) = try SharedMediaAcquisitionReceipt.read(receipt), result.descriptor == attempt.original.descriptor else {
            throw SharedMediaStorageFailure.conflict
        }
        if case .preparation(let old) = previous {
            guard old.frozen == nil else { throw SharedMediaStorageFailure.closed }
        }
        // One attempt across the inventory, not merely one per package.
        let preparing: Int
        if let scopedInventory { preparing = try pendingRows(context, inventory: scopedInventory).filter { $0.phaseRaw == "preparing" }.count } else { preparing = try context.fetchCount(FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.phaseRaw == "preparing" })) }
        guard preparing == 1 else {
            throw SharedMediaStorageFailure.conflict
        }
    }
    /// Global fresh-admission guard, also used by the sealed reservation owner.
    /// A plan in another package still owns the sole processing reservation.
    static func requireNoUnfinished(_ context: ModelContext) throws {
        var query = FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.accountingTierRaw == "pending" })
        query.fetchLimit = PhotoPreparationPolicy.maximumPackages + 1
        let rows = try context.fetch(query)
        guard rows.count <= PhotoPreparationPolicy.maximumPackages else { throw SharedMediaStorageFailure.capacity }
        for row in rows {
            let envelope = try SharedMediaNativeDraftEnvelope.decode(row.supportingContextData)
            if case .preparation(let value) = envelope {
                guard value.attempt == nil else { throw SharedMediaStorageFailure.closed }
                if value.frozen != nil {
                    let inventory = try one(context, FetchDescriptor<SharedMediaInventoryRecord>())
                    try SharedMediaNativeFreezeGraph.validate(value, package: row, inventory: inventory, context: context)
                }
                for blob in value.intents {
                    let id = try SharedMediaNativeDerivativeIntent.decode(blob.bytes).pairID
                    let pair = try one(context, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == id }))
                    guard pair.phaseRaw == "ready" else { throw SharedMediaStorageFailure.closed }
                }
            }
        }
        guard try context.fetchCount(FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.phaseRaw != "ready" })) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.phaseRaw != "completed" })) == 0 else { throw SharedMediaStorageFailure.closed }
    }
    /// Fresh V2 admission checks only inventory-anchored native work.
    static func requireNoUnfinished(_ context: ModelContext, inventory: SharedMediaInventoryRecord, targetPackageID: UUID,
                                    allowing attempt: SharedMediaNativePreparationAttempt? = nil) throws {
        let inventoryID = inventory.id
        var unfinished = FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.inventoryID == inventoryID && $0.phaseRaw != "ready" })
        unfinished.fetchLimit = 1
        guard try context.fetch(unfinished).isEmpty else { throw SharedMediaStorageFailure.closed }
        for package in try pendingRows(context, inventory: inventory) {
            let envelope = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData)
            guard !package.retirementRequested else { throw SharedMediaStorageFailure.closed }
            if let blob = envelope.attempt {
                guard package.id == targetPackageID, let attempt,
                      try SharedMediaNativePreparationAttempt.decode(blob.bytes) == attempt else { throw SharedMediaStorageFailure.closed }
            }
            let id = package.id
            var pairs = FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.packageID == id })
            pairs.fetchLimit = 10
            let rows = try context.fetch(pairs)
            guard rows.count <= 9 else { throw SharedMediaStorageFailure.capacity }
            for pair in rows {
                let pairID = pair.id
                guard pair.phaseRaw == "ready", pair.inventoryID == inventory.id, pair.inventoryGeneration == inventory.generation,
                      try context.fetchCount(FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.pairID == pairID && $0.phaseRaw != "completed" })) == 0 else { throw SharedMediaStorageFailure.closed }
            }
            if id == targetPackageID {
                guard try SharedMediaConsumerLookup.one(context, packageID: id) == nil else { throw SharedMediaStorageFailure.closed }
                if case .preparation(let value) = envelope, value.frozen != nil { throw SharedMediaStorageFailure.closed }
            }
        }
    }
    static func pendingRows(_ context: ModelContext, inventory: SharedMediaInventoryRecord) throws -> [PhotoPreparationRecord] {
        let id = inventory.id
        var query = FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.inventoryID == id })
        query.fetchLimit = PhotoPreparationPolicy.maximumPackages + 1
        let members = try context.fetch(query)
        guard members.count <= PhotoPreparationPolicy.maximumPackages else { throw SharedMediaStorageFailure.capacity }
        return try members.map { member in
            let packageID = member.id
            let package = try one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
            guard member.inventoryGeneration == inventory.generation, member.ownerID == package.ownerID,
                  member.draftGeneration == package.draftGeneration, package.accountingTierRaw == "pending" else { throw SharedMediaStorageFailure.conflict }
            return package
        }
    }
    static func requireIdleFiles(_ context: ModelContext, scopedInventory: SharedMediaInventoryRecord?, allowSavedOriginalRetirements: Bool = false) throws {
        guard let inventory = scopedInventory else {
            guard try context.fetchCount(FetchDescriptor<PhotoPreparationLease>()) == 0,
                  try context.fetchCount(FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.cleanupStateRaw != "ready" })) == 0 else { throw SharedMediaStorageFailure.conflict }
            return
        }
        for package in try pendingRows(context, inventory: inventory) {
            let id = package.id
            guard try context.fetchCount(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.packageID == id })) == 0 else { throw SharedMediaStorageFailure.conflict }
            var query = FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.packageID == id }); query.fetchLimit = 7
            let refs = try context.fetch(query)
            guard refs.count <= 6 else { throw SharedMediaStorageFailure.conflict }
            for ref in refs {
                let assetID = ref.assetID
                let asset = try one(context, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID }))
                guard asset.ownerID == package.ownerID else { throw SharedMediaStorageFailure.conflict }
                if asset.cleanupStateRaw == "ready" { continue }
                // Only fresh app acquisition may coexist with a saved original
                // retirement. Preparation/poststate callers remain strict.
                guard allowSavedOriginalRetirements, !context.hasChanges,
                      !ref.isLive, ref.roleRaw == "original", asset.cleanupStateRaw == "retiring" else {
                    throw SharedMediaStorageFailure.conflict
                }
                let original = try SharedMediaNativeOriginalAccounting.audit(assetID: assetID, inventoryID: inventory.id, context: context)
                let referenceID = ref.id
                guard original.liveCount == 0, original.retirement != nil,
                      try context.fetchCount(FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate {
                          $0.originalReferenceID == referenceID || $0.originalAssetID == assetID
                      })) == 0,
                      try context.fetchCount(FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.assetID == assetID })) == 0 else {
                    throw SharedMediaStorageFailure.conflict
                }
            }
        }
    }
    private static func one<T: PersistentModel>(_ context: ModelContext, _ query: FetchDescriptor<T>) throws -> T {
        var query = query; query.fetchLimit = 2; let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first else { throw SharedMediaStorageFailure.conflict }; return row
    }
}
