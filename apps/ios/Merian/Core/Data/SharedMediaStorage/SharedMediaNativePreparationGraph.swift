import Foundation
import SwiftData

/// Strict native V2 graph. Only attempts and no-file plans are admitted;
/// file-writing, ready and frozen stages remain closed.
@MainActor
enum SharedMediaNativePreparationGraph {
    static func validate(_ envelope: SharedMediaNativeDraftEnvelope, package: PhotoPreparationRecord, context: ModelContext) throws {
        guard case .preparation(let value) = envelope else { return }
        guard value.frozen == nil else { throw SharedMediaStorageFailure.closed }
        if !value.intents.isEmpty {
            let inventory = try one(context, FetchDescriptor<SharedMediaInventoryRecord>())
            try SharedMediaNativePairPlanGraph.validate(value, package: package, inventory: inventory, context: context)
            return
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
        let previous = try SharedMediaNativeDraftEnvelope.decode(attempt.previousEnvelope)
        guard previous.attempt == nil, try SharedMediaStoragePolicy.add(previous.sequence, 1) == attempt.sequence,
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
              case .completed(_, let result) = try SharedMediaAcquisitionReceipt.read(receipt), result.descriptor == attempt.original.descriptor,
              try context.fetchCount(FetchDescriptor<PhotoPreparationLease>()) == 0,
              try context.fetchCount(FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.cleanupStateRaw != "ready" })) == 0 else {
            throw SharedMediaStorageFailure.conflict
        }
        if case .preparation(let old) = previous {
            guard old.intents.isEmpty, old.frozen == nil else { throw SharedMediaStorageFailure.closed }
        }
        // One attempt across the inventory, not merely one per package.
        guard try context.fetchCount(FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.phaseRaw == "preparing" })) == 1 else {
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
                guard value.attempt == nil, value.intents.isEmpty, value.frozen == nil else { throw SharedMediaStorageFailure.closed }
            }
        }
        guard try context.fetchCount(FetchDescriptor<SharedMediaDerivativePairRecord>()) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaDerivativeWorkRecord>()) == 0 else { throw SharedMediaStorageFailure.closed }
    }
    private static func one<T: PersistentModel>(_ context: ModelContext, _ query: FetchDescriptor<T>) throws -> T {
        var query = query; query.fetchLimit = 2; let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first else { throw SharedMediaStorageFailure.conflict }; return row
    }
}
