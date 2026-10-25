import Foundation
import SwiftData

/// Independently derived raw deletion/update seal for one held pair removal.
/// Construct while clean; no insertion, original mutation or unrelated write fits.
@MainActor
struct SharedMediaNativeReleasePairRemovalPoststate {
    private typealias Raw = SharedMediaNativeReleasePairRaw
    private struct Row {
        let before: (PersistentIdentifier, Raw.Fields)
        let after: Raw.Fields?
        let read: (ModelContext) throws -> (PersistentIdentifier, Raw.Fields)?
        let deletedFields: () throws -> Raw.Fields
    }
    private var rows: [Row] = []
    private let contextID: ObjectIdentifier

    init(state: SharedMediaNativePairFileState, before: SharedMediaNativeReceivingReleaseValues.Progress,
         after: SharedMediaNativeReceivingReleaseValues.Progress,
         successor: SharedMediaNativeReceivingReleaseState.Expected, context: ModelContext) throws {
        let first = before.targets[try before.selectedIndex(.retiringPair)]
        guard !context.hasChanges, state.phase == "retiring",
              after == (try before.advancing(.init(pairID: first.pairID, stage: .pairGoneOriginalLive,
                pair: first.pair, original: nil))), first.pairID == (try state.intent().pairID) else {
            throw SharedMediaStorageFailure.conflict
        }
        contextID = ObjectIdentifier(context)
        let inventoryID = before.plan.profile.inventoryID, packageID = before.plan.package.id, pairID = first.pairID
        try update(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }), Raw.fields,
            ["revision": Raw.value(SharedMediaStoragePolicy.add(state.plan.inventoryRevision, 1))])
        try update(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }), Raw.fields,
            ["revision": Raw.value(successor.package.revision), "allocatedByteCount": Raw.value(successor.package.allocated)])
        try update(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }), Raw.fields,
            ["revision": Raw.value(successor.member.revision), "membersData": Raw.value(successor.member.bytes)])
        let bytes = try after.encoded()
        try update(context, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == packageID }), Raw.fields,
            ["revision": Raw.value(successor.slotRevision), "resultData": Raw.value(Optional(bytes)),
             "resultSHA256": Raw.value(Optional(SharedMediaAcquisitionEncoding.digest(bytes)))])
        try remove(context, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == pairID }), Raw.fields)
        for work in state.work {
            guard work.phase == "retiring", work.writerState == "closed", work.finalIdentity != nil else {
                throw SharedMediaStorageFailure.conflict
            }
            let (_, input) = try state.selected(work.id)
            let id = input.id, assetID = input.assetID, referenceID = input.referenceID, leaseID = input.leaseID
            try remove(context, FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == id }), Raw.fields)
            try remove(context, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == assetID }), Raw.fields)
            try remove(context, FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == leaseID }), Raw.fields)
            try remove(context, FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == leaseID }), Raw.fields)
            try remove(context, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID }), Raw.fields)
            try remove(context, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == referenceID }), Raw.fields)
            try remove(context, FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == referenceID }), Raw.fields)
            try remove(context, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID }), Raw.fields)
        }
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
    }
    func requirePredecessor(_ context: ModelContext) throws {
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        for row in rows {
            guard let current = try row.read(context), current.0 == row.before.0, current.1 == row.before.1 else {
                throw SharedMediaStorageFailure.stale
            }
        }
    }
    func requireSavedSuccessor(_ context: ModelContext) throws {
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        for row in rows {
            let current = try row.read(context)
            if let after = row.after {
                guard let current, current.0 == row.before.0, current.1 == after else { throw SharedMediaStorageFailure.stale }
            } else if current != nil { throw SharedMediaStorageFailure.conflict }
        }
    }
    func validate(_ context: ModelContext) throws {
        guard ObjectIdentifier(context) == contextID, context.insertedModelsArray.isEmpty else {
            throw SharedMediaStorageFailure.conflict
        }
        var updated = Set<PersistentIdentifier>(), deleted = Set<PersistentIdentifier>()
        for row in rows {
            if let after = row.after {
                guard let current = try row.read(context), current.0 == row.before.0, current.1 == after,
                      updated.insert(current.0).inserted else { throw SharedMediaStorageFailure.conflict }
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
