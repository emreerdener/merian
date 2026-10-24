import Foundation
import SwiftData

/// Held-only physical removal seal. The separate filesystem proof must establish
/// current absence before this exact six-row deletion can be saved.
@MainActor
struct SharedMediaNativeOriginalRemovalPoststate {
    private typealias Raw = SharedMediaNativeReleasePairRaw
    private struct Row {
        let before: (PersistentIdentifier, Raw.Fields)
        let after: Raw.Fields?
        let read: (ModelContext) throws -> (PersistentIdentifier, Raw.Fields)?
        let deletedFields: () throws -> Raw.Fields
    }
    private var rows: [Row] = []
    private let contextID: ObjectIdentifier

    private let assetID: UUID, leaseID: UUID
    init(before: SharedMediaNativeReceivingReleaseValues.Progress,
         after: SharedMediaNativeReceivingReleaseValues.Progress,
         successor: SharedMediaNativeReceivingReleaseState.Expected,
         original: SharedMediaNativeOriginalAccounting.Snapshot, context: ModelContext) throws {
        guard !context.hasChanges, let target = before.plan.targets.first,
              before.targets.first?.stage == .originalRetiring,
              original.liveCount == 0, original.retirement != nil else { throw SharedMediaStorageFailure.conflict }
        contextID = ObjectIdentifier(context)
        let inventoryID = before.plan.profile.inventoryID, packageID = before.plan.package.id
        let assetID = target.original.assetID, referenceID = target.original.referenceID, leaseID = original.leaseID
        self.assetID = assetID; self.leaseID = leaseID
        try requireNoPhotoLease(context)
        try update(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }), Raw.fields,
            ["revision": Raw.value(SharedMediaStoragePolicy.add(original.inventoryRevision, 1))])
        try update(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }), Raw.fields,
            ["revision": Raw.value(successor.package.revision), "allocatedByteCount": Raw.value(successor.package.allocated)])
        try update(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }), Raw.fields,
            ["revision": Raw.value(successor.member.revision), "membersData": Raw.value(successor.member.bytes)])
        let bytes = try after.encoded()
        try update(context, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == packageID }), Raw.fields,
            ["revision": Raw.value(successor.slotRevision), "resultData": Raw.value(Optional(bytes)),
             "resultSHA256": Raw.value(Optional(SharedMediaAcquisitionEncoding.digest(bytes)))])
        try remove(context, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == referenceID }), Raw.fields)
        try remove(context, FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == referenceID }), Raw.fields)
        try remove(context, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID }), Raw.fields)
        try remove(context, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == assetID }), Raw.fields)
        try remove(context, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID }), Raw.fields)
        try remove(context, FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == leaseID }), Raw.fields)
        try update(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == leaseID }),
            SharedMediaNativeOriginalDispositionAttestation.fields,
            ["phaseRaw": Raw.value("terminal"), "revision": Raw.value(Int64(2)), "terminalOutcomeRaw": Raw.value(Optional("released")),
             "requestData": Raw.value(Optional<Data>.none), "resultData": Raw.value(Optional<Data>.none),
             "packageID": Raw.value(Optional<UUID>.none), "assetID": Raw.value(Optional<UUID>.none)])
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
    }
    private func requireNoPhotoLease(_ context: ModelContext) throws {
        let assetID = assetID, leaseID = leaseID
        guard try context.fetchCount(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate {
            $0.id == leaseID || $0.assetID == assetID
        })) == 0 else { throw SharedMediaStorageFailure.conflict }
    }
    func requirePredecessor(_ context: ModelContext) throws {
        try requireNoPhotoLease(context)
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        for row in rows {
            guard let current = try row.read(context), current.0 == row.before.0, current.1 == row.before.1 else {
                throw SharedMediaStorageFailure.stale
            }
        }
    }
    func requireSavedSuccessor(_ context: ModelContext) throws {
        try requireNoPhotoLease(context)
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        for row in rows {
            let current = try row.read(context)
            if let after = row.after {
                guard let current, current.0 == row.before.0, current.1 == after else { throw SharedMediaStorageFailure.stale }
            } else if current != nil { throw SharedMediaStorageFailure.conflict }
        }
    }
    func validate(_ context: ModelContext) throws {
        try requireNoPhotoLease(context)
        guard ObjectIdentifier(context) == contextID, context.insertedModelsArray.isEmpty else {
            throw SharedMediaStorageFailure.conflict
        }
        var updated = Set<PersistentIdentifier>(), deleted = Set<PersistentIdentifier>()
        for row in rows {
            if let after = row.after {
                guard let current = try row.read(context), current.0 == row.before.0, current.1 == after,
                      (after == row.before.1 || updated.insert(current.0).inserted) else { throw SharedMediaStorageFailure.conflict }
            } else {
                guard deleted.insert(row.before.0).inserted, try row.deletedFields() == row.before.1 else {
                    throw SharedMediaStorageFailure.conflict
                }
            }
        }
        guard updated.isDisjoint(with: deleted), context.deletedModelsArray.count == deleted.count,
              Set(context.deletedModelsArray.map(\.persistentModelID)) == deleted,
              Set(context.changedModelsArray.map(\.persistentModelID)).subtracting(deleted) == updated else {
            throw SharedMediaStorageFailure.conflict
        }
    }
    private mutating func update<T: PersistentModel>(_ context: ModelContext, _ query: FetchDescriptor<T>,
            _ fields: @escaping (T) throws -> Raw.Fields, _ changes: Raw.Fields) throws {
        let row = try SharedMediaNativePairPlanGraph.one(context, query), before = try fields(row)
        guard Set(changes.keys).isSubset(of: Set(before.keys)) else { throw SharedMediaStorageFailure.conflict }
        var after = before; after.merge(changes) { _, next in next }
        rows.append(.init(before: (row.persistentModelID, before), after: after,
            read: reader(query, fields), deletedFields: { try fields(row) }))
    }
    private mutating func remove<T: PersistentModel>(_ context: ModelContext, _ query: FetchDescriptor<T>,
            _ fields: @escaping (T) throws -> Raw.Fields) throws {
        let row = try SharedMediaNativePairPlanGraph.one(context, query)
        rows.append(.init(before: (row.persistentModelID, try fields(row)), after: nil,
            read: reader(query, fields), deletedFields: { try fields(row) }))
    }
    private func reader<T: PersistentModel>(_ descriptor: FetchDescriptor<T>, _ fields: @escaping (T) throws -> Raw.Fields)
            -> (ModelContext) throws -> (PersistentIdentifier, Raw.Fields)? {
        { context in
            var query = descriptor; query.fetchLimit = 2; query.includePendingChanges = true
            let found = try context.fetch(query)
            guard found.count <= 1 else { throw SharedMediaStorageFailure.conflict }
            guard let row = found.first else { return nil }
            return (row.persistentModelID, try fields(row))
        }
    }
}
