import Foundation
import SwiftData

/// Clean, asset-owned accounting inputs under the native store fence. This is
/// not a whole-store audit, capacity admission, reservation or cleanup right.
/// Ordinary app Budget owns enforcement; held-release integration is separate.
@MainActor
enum SharedMediaNativeOriginalLiability {
    struct Entry: Equatable, Sendable {
        let assetID: UUID
        let acquisitionID: UUID
        let physicalOriginID: UUID
        let currentBytes: Int64
        let reservedBytes: Int64
        let retiring: Bool
    }
    struct Snapshot: Equatable, Sendable {
        let inventoryID: UUID
        let generation: UUID
        let revision: Int64
        let entries: [UUID: Entry]
        /// Foreign targets proven fully retained-only, outside pending liability.
        let retainedTargets: Set<UUID>
        var currentBytes: Int64 { get throws { try PhotoPreparationPolicy.add(entries.values.map(\.currentBytes)) } }
        var reservedBytes: Int64 { get throws { try PhotoPreparationPolicy.add(entries.values.map(\.reservedBytes)) } }
    }

    static func read(context: ModelContext, inventoryID: UUID, checkpoint: () throws -> Void = {}) throws -> Snapshot {
        try Task.checkCancellation(); try checkpoint()
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        let inventory = try one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let profile = try SharedMediaNativeAppEligibility.profile(inventory), revision = inventory.revision
        let graph = try SharedMediaPendingGraph.deriveScoped(in: context, inventory: inventory, ownerID: profile.ownerID, format: .appV2)
        let witnesses = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory, checkpoint: checkpoint)
        let releases = witnesses.values.compactMap { witness -> SharedMediaNativeReleaseMetadataSnapshot.Snapshot? in
            if case .releasing(let snapshot) = witness { return snapshot }; return nil
        }
        var selected = Set(graph.allocations.map(\.id)), required = Set<UUID>()
        for release in releases {
            required.formUnion(release.ownedOriginals.map(\.assetID))
        }
        selected.formUnion(required)
        var entries: [UUID: Entry] = [:]
        for id in selected.sorted(by: { $0.uuidString < $1.uuidString }) {
            try Task.checkCancellation(); try checkpoint()
            if try SharedMediaNativePairFileGraph.nativeWork(assetID: id, context: context) != nil {
                guard !required.contains(id) else { throw SharedMediaStorageFailure.conflict }
                continue // Derivative accounting retains its existing owner.
            }
            let receipt = try one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == id }))
            let value = try SharedMediaNativeAcquisitionGraph.scopedReceipt(receipt, inventory: inventory,
                context: context, format: .appV2, checkpoint: checkpoint)
            switch value {
            case .completed(let request, _):
                let entry = try completed(request, inventory: inventory, context: context, checkpoint: checkpoint)
                guard entry.assetID == id, entries.updateValue(entry, forKey: id) == nil else { throw SharedMediaStorageFailure.conflict }
            case .reserved, .held:
                guard !required.contains(id) else { throw SharedMediaStorageFailure.conflict }
                // Unmaterialized acquisition reservations are not originals.
            case .released: throw SharedMediaStorageFailure.conflict
            }
        }
        var retainedTargets = Set<UUID>()
        for release in releases {
            for original in release.ownedOriginals {
                guard let entry = entries[original.assetID], entry.physicalOriginID == original.physicalOriginID,
                      entry.currentBytes == original.identityBytes, entry.retiring == original.retiring else {
                    throw SharedMediaStorageFailure.conflict
                }
            }
            for (index, target) in release.targetOrigins.enumerated() {
                switch target.location {
                case .released:
                    guard entries[target.assetID] == nil else { throw SharedMediaStorageFailure.conflict }
                case .present(let origin):
                    if let entry = entries[target.assetID] {
                        guard entry.acquisitionID == target.acquisitionID, entry.physicalOriginID == origin else {
                            throw SharedMediaStorageFailure.conflict
                        }
                    } else {
                        let progress = release.release.progress.targets[index]
                        guard progress.stage == .removed, progress.original?.disposition == .shared else {
                            throw SharedMediaStorageFailure.conflict
                        }
                        try retained(target.assetID, acquisitionID: target.acquisitionID, origin: origin,
                            inventory: inventory, context: context, checkpoint: checkpoint)
                        retainedTargets.insert(target.assetID)
                    }
                }
            }
        }
        let result = Snapshot(inventoryID: inventoryID, generation: profile.generation, revision: revision,
            entries: entries, retainedTargets: retainedTargets)
        _ = try PhotoPreparationPolicy.add([result.currentBytes, result.reservedBytes])
        try Task.checkCancellation(); try checkpoint()
        guard !context.hasChanges, inventory.revision == revision,
              try SharedMediaNativeAppEligibility.profile(inventory) == profile else { throw SharedMediaStorageFailure.stale }
        return result
    }

    private static func completed(_ request: SharedMediaAcquisitionIntent, inventory: SharedMediaInventoryRecord,
                                  context: ModelContext, checkpoint: () throws -> Void) throws -> Entry {
        let original = try SharedMediaNativeOriginalAccounting.audit(assetID: request.assetID,
            inventoryID: inventory.id, context: context, checkpoint: checkpoint)
        let bytes = Int64(original.physicalIdentity.utf8.count)
        guard original.ownerID == request.ownerID, original.assetGeneration == request.assetGeneration,
              original.leaseID == request.operationID, bytes > 0, bytes <= 512 else { throw SharedMediaStorageFailure.conflict }
        return .init(assetID: request.assetID, acquisitionID: request.operationID, physicalOriginID: request.packageID,
            currentBytes: bytes, reservedBytes: 512 - bytes, retiring: original.retirement != nil)
    }

    private static func retained(_ assetID: UUID, acquisitionID: UUID, origin: UUID, inventory: SharedMediaInventoryRecord,
                                 context: ModelContext, checkpoint: () throws -> Void) throws {
        let receipt = try one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == assetID }))
        guard case .completed(let request, _) = try SharedMediaNativeAcquisitionGraph.scopedReceipt(receipt,
            inventory: inventory, context: context, format: .appV2, checkpoint: checkpoint),
              request.operationID == acquisitionID, request.packageID == origin else { throw SharedMediaStorageFailure.conflict }
        let original = try SharedMediaNativeOriginalAccounting.audit(assetID: assetID,
            inventoryID: inventory.id, context: context, checkpoint: checkpoint)
        guard original.liveCount > 0, original.retirement == nil else { throw SharedMediaStorageFailure.conflict }
        var query = FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.assetID == assetID }, sortBy: [SortDescriptor(\.id)])
        query.fetchLimit = SharedMediaStoragePolicy.pageSize
        var offset = 0, total: Int64 = 0
        while true {
            try Task.checkCancellation(); try checkpoint(); query.fetchOffset = offset
            let refs = try context.fetch(query)
            for ref in refs {
                try Task.checkCancellation(); try checkpoint()
                let packageID = ref.packageID
                let package = try one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
                guard ref.isLive, package.accountingTierRaw == "retained", !package.retirementRequested,
                      try context.fetchCount(FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID })) == 0,
                      let consumer = try SharedMediaConsumerLookup.one(context, packageID: packageID), consumer.kindRaw != "queue" else {
                    throw SharedMediaStorageFailure.conflict
                }
                // Includes exact retained freeze/membership and original joins;
                // a terminal slot or an unbound retained row is not sufficient.
                _ = try SharedMediaNativeConsumerGraph.validateScoped(consumer, context: context, format: .appV2, checkpoint: checkpoint)
            }
            total = try SharedMediaStoragePolicy.add(total, Int64(refs.count))
            if refs.count < SharedMediaStoragePolicy.pageSize { break }
            let (next, overflow) = offset.addingReportingOverflow(refs.count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }; offset = next
        }
        guard total == original.liveCount else { throw SharedMediaStorageFailure.conflict }
    }
    private static func one<T: PersistentModel>(_ context: ModelContext, _ query: FetchDescriptor<T>) throws -> T {
        try SharedMediaNativePairPlanGraph.one(context, query)
    }
}
