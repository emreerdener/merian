import Foundation
import SwiftData

/// Exact terminal transaction: two updates and six deletions. No other row
/// may change, including submitted media, historical analyses or selections.
@MainActor
struct SharedMediaNativeReceivingTerminalPoststate {
    private typealias Raw = SharedMediaNativeReleasePairRaw
    private struct Row {
        let before: (PersistentIdentifier, Raw.Fields)
        let after: Raw.Fields?
        let read: (ModelContext) throws -> (PersistentIdentifier, Raw.Fields)?
        let deletedFields: () throws -> Raw.Fields
    }
    private var rows: [Row] = []
    private let contextID: ObjectIdentifier

    init(before: SharedMediaNativeReleaseMetadataSnapshot.Snapshot,
         after: SharedMediaNativeReceivingReleaseValues.Released, context: ModelContext) throws {
        guard !context.hasChanges, before.release.progress.targets.allSatisfy({ $0.stage == .removed }),
              after == (try .init(progress: before.release.progress, inventoryRevision: SharedMediaStoragePolicy.add(before.inventoryRevision, 1))) else {
            throw SharedMediaStorageFailure.conflict
        }
        try before.release.slot.requireNoAllocation()
        contextID = ObjectIdentifier(context)
        let plan = after.plan, inventoryID = plan.profile.inventoryID, packageID = plan.package.id
        let bindingID = plan.bindingID, queueID = plan.queueID.uuidString.lowercased(), jobID = plan.jobID, eventID = plan.eventID.uuidString.lowercased()
        let bytes = try after.encoded()
        guard before.release.slot.revision == (try SharedMediaNativeReceivingTerminal.revision(after)) - 1 else { throw SharedMediaStorageFailure.conflict }
        try update(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }), Raw.fields,
            ["revision": Raw.value(after.inventoryRevision)])
        try update(context, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == packageID }), Raw.fields,
            ["revision": Raw.value(SharedMediaNativeReceivingTerminal.revision(after)), "phaseRaw": Raw.value("released"),
             "preparedData": Raw.value(Optional<Data>.none), "releaseStartData": Raw.value(Optional<Data>.none),
             "releaseStartSHA256": Raw.value(Optional<String>.none), "resultData": Raw.value(Optional(bytes)),
             "resultSHA256": Raw.value(Optional(SharedMediaAcquisitionEncoding.digest(bytes)))])
        try remove(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }), Raw.fields)
        try remove(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }), Raw.fields)
        try remove(context, FetchDescriptor<SharedMediaConsumerRecord>(predicate: #Predicate { $0.id == bindingID }), SharedMediaNativeReceivingTerminalRaw.fields)
        try remove(context, FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == queueID }), SharedMediaNativeReceivingTerminalRaw.fields)
        try remove(context, FetchDescriptor<OfflineJobRecord>(predicate: #Predicate { $0.id == jobID }), SharedMediaNativeReceivingTerminalRaw.fields)
        try remove(context, FetchDescriptor<OfflineQueueEvent>(predicate: #Predicate { $0.id == eventID }), SharedMediaNativeReceivingTerminalRaw.fields)
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
