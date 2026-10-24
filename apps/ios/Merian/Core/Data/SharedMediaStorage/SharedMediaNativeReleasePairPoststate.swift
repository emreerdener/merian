import Foundation
import SwiftData

/// One exact write set across receiving Progress and the retiring pair rows.
/// Constructed while clean; independently derives successors before mutation.
@MainActor
struct SharedMediaNativeReleasePairPoststate {
    private typealias Raw = SharedMediaNativeReleasePairRaw
    private struct Row {
        let before: (PersistentIdentifier, Raw.Fields)?
        let after: Raw.Fields
        let read: (ModelContext) throws -> (PersistentIdentifier, Raw.Fields)?
    }
    private var rows: [Row] = []
    private let contextID: ObjectIdentifier

    init(_ attempt: SharedMediaNativeReleasePairAttempt, context: ModelContext) throws {
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        contextID = ObjectIdentifier(context)
        let state = attempt.state, next = attempt.successor, plan = attempt.before.plan
        let inventoryID = plan.profile.inventoryID, packageID = plan.package.id, pairID = attempt.closure.pairID
        try update(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }), Raw.fields,
            ["revision": Raw.value(SharedMediaStoragePolicy.add(state.plan.inventoryRevision, 1))])
        try update(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }), Raw.fields,
            ["revision": Raw.value(next.package.revision)])
        try update(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }), Raw.fields,
            ["revision": Raw.value(next.member.revision), "membersData": Raw.value(next.member.bytes)])
        let bytes = try attempt.after.encoded()
        try update(context, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == packageID }), Raw.fields,
            ["revision": Raw.value(next.slotRevision), "resultData": Raw.value(Optional(bytes)),
             "resultSHA256": Raw.value(Optional(SharedMediaAcquisitionEncoding.digest(bytes)))])
        try update(context, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == pairID }), Raw.fields,
            ["phaseRaw": Raw.value("retiring"), "publishedRevision": Raw.value(Optional<Int64>.none)])
        let intent = try state.intent(), retirement = attempt.closure.retirementID
        for entry in attempt.closure.entries {
            let (_, input) = try state.selected(entry.work.id)
            let id = input.id, assetID = input.assetID, referenceID = input.referenceID, leaseID = input.leaseID
            try update(context, FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == id }), Raw.fields,
                ["phaseRaw": Raw.value("retiring"), "writerStateRaw": Raw.value("closed"),
                 "retirementID": Raw.value(Optional(retirement)),
                 "retirementPartialIdentity": Raw.value(Optional(entry.identity.partial)),
                 "retirementFinalIdentity": Raw.value(Optional(entry.identity.final)),
                 "retirementParentIdentity": Raw.value(Optional(entry.identity.parent)),
                 "retirementNamespaceIdentity": Raw.value(Optional(entry.identity.namespace))])
            try update(context, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == assetID }), Raw.fields,
                ["stateRaw": Raw.value("nativePairRetiringV2")])
            let token = try state.file(id).token
            let local = PhotoPreparationLease(id: leaseID, packageID: packageID, assetID: assetID,
                ownerID: plan.profile.ownerID, processEpoch: entry.work.writerEpoch,
                purposeRaw: SharedMediaNativePairPlanGraph.contract, partialFileToken: token + ".partial", finalFileToken: token,
                reservedByteCount: 0, allocatedByteCount: input.byteCount, writerStateRaw: "closedNativePairRetirementV2",
                terminalProof: id == intent.ai.id ? try attempt.closure.encoded() : try attempt.closure.siblingMarker())
            let shared = SharedMediaLeaseRecord(id: leaseID, allocationID: assetID, processEpoch: entry.work.writerEpoch,
                purposeRaw: SharedMediaNativePairPlanGraph.contract, stateRaw: "closed")
            try insert(context, FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == leaseID }), Raw.fields, Raw.fields(local))
            try insert(context, FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == leaseID }), Raw.fields, Raw.fields(shared))
            guard entry.work.finalIdentity != nil else { throw SharedMediaStorageFailure.conflict }
            try update(context, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID }), Raw.fields,
                ["cleanupStateRaw": Raw.value("retiring")])
            try update(context, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == referenceID }), Raw.fields,
                ["isLive": Raw.value(false), "revision": Raw.value(Int64(1))])
            try update(context, FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == referenceID }), Raw.fields,
                ["stateRaw": Raw.value("retired"), "revision": Raw.value(Int64(1))])
            try update(context, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID }), Raw.fields,
                ["liveCount": Raw.value(Int64(0)), "revision": Raw.value(Int64(1)), "retirementID": Raw.value(Optional(retirement))])
        }
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
    }

    func requirePredecessor(_ context: ModelContext) throws {
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        for row in rows {
            let actual = try row.read(context)
            if let before = row.before {
                guard let actual, actual.0 == before.0, actual.1 == before.1 else { throw SharedMediaStorageFailure.stale }
            } else if actual != nil { throw SharedMediaStorageFailure.conflict }
        }
    }
    func validate(_ context: ModelContext) throws {
        guard ObjectIdentifier(context) == contextID, context.deletedModelsArray.isEmpty else { throw SharedMediaStorageFailure.conflict }
        var updated = Set<PersistentIdentifier>(), inserted = Set<PersistentIdentifier>()
        for row in rows {
            guard let current = try row.read(context), current.1 == row.after else { throw SharedMediaStorageFailure.conflict }
            if let before = row.before {
                guard current.0 == before.0, updated.insert(current.0).inserted else { throw SharedMediaStorageFailure.conflict }
            } else {
                guard inserted.insert(current.0).inserted else { throw SharedMediaStorageFailure.conflict }
            }
        }
        guard updated.isDisjoint(with: inserted),
              context.insertedModelsArray.count == inserted.count,
              Set(context.insertedModelsArray.map(\.persistentModelID)) == inserted,
              Set(context.changedModelsArray.map(\.persistentModelID)).subtracting(inserted) == updated else {
            throw SharedMediaStorageFailure.conflict
        }
    }
    private mutating func update<T: PersistentModel>(_ context: ModelContext, _ query: FetchDescriptor<T>,
            _ fields: @escaping (T) throws -> Raw.Fields, _ changes: Raw.Fields) throws {
        let read = reader(query, fields)
        guard let before = try read(context), Set(changes.keys).isSubset(of: Set(before.1.keys)) else { throw SharedMediaStorageFailure.conflict }
        var after = before.1; after.merge(changes) { _, new in new }
        rows.append(.init(before: before, after: after, read: read))
    }
    private mutating func insert<T: PersistentModel>(_ context: ModelContext, _ query: FetchDescriptor<T>,
            _ fields: @escaping (T) throws -> Raw.Fields, _ after: Raw.Fields) throws {
        let read = reader(query, fields)
        guard try read(context) == nil else { throw SharedMediaStorageFailure.conflict }
        rows.append(.init(before: nil, after: after, read: read))
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
