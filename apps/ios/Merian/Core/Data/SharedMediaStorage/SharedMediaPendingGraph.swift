import Foundation
import SwiftData

/// Bounded logical package discovery, not a complete physical namespace inventory.
/// This read-only value grants no file, mutation, admission or cleanup authority.
/// Runtime callers must retain the shared owner's store fence for the transaction.
/// This is a joined projection, not a phase validator or whole-store orphan audit.
/// The typed ledgers, reverse accounting and complete native audit remain required.
@MainActor
struct SharedMediaPendingGraph {
    let packages: [PhotoPreparationRecord]
    let assets: [PhotoPreparationAsset]
    let references: [PhotoPreparationReference]
    let work: [PhotoPreparationLease]
    let allocations: [SharedMediaAllocationRecord]
    let edges: [SharedMediaReferenceRecord]
    let leases: [SharedMediaLeaseRecord]
    let sources: [SharedMediaInboxSourceRecord]
    let handoffs: [SharedMediaInboxHandoffRecord]
    let pairs: [SharedMediaDerivativePairRecord]
    let derivatives: [SharedMediaDerivativeWorkRecord]
    private let inventoryID: UUID
    private let inventoryGeneration: UUID
    private let assertions: [UUID: SharedMediaMembership]

    /// Rebuild from authoritative foreign keys, never from a saved ID assertion.
    /// A post-transition rebuild is not permission to repair missing old metadata.
    static func derive(in context: ModelContext, inventory: SharedMediaInventoryRecord) throws -> Self {
        let packages = try SharedMediaConsumerLookup.pendingPackages(context)
        var builder = Builder(context: context, inventory: inventory)
        for package in packages { try builder.include(package) }
        // Accountless sources remain independently owned, including after a detach.
        let sources = try fetch(context, FetchDescriptor<SharedMediaInboxSourceRecord>(), maximum: 8)
        for source in sources { try builder.includeSource(source) }
        return try builder.finish(packages: packages, sources: sources)
    }

    func membership(packageID: UUID) throws -> SharedMediaMembership {
        guard let value = assertions[packageID] else { throw SharedMediaStorageFailure.conflict }
        return value
    }

    /// Exact old-state precondition. Does not synthesize a receipt or membership.
    func validateMembership(in context: ModelContext, inventory: SharedMediaInventoryRecord) throws {
        guard inventory.id == inventoryID, inventory.generation == inventoryGeneration else {
            throw SharedMediaStorageFailure.conflict
        }
        let fresh = try Self.derive(in: context, inventory: inventory)
        guard fresh.assertions == assertions else { throw SharedMediaStorageFailure.conflict }
        let receipts = try Self.fetch(context, FetchDescriptor<SharedMediaMembershipBootstrapRecord>(), maximum: 1)
        guard let receipt = receipts.first, receipt.id == inventory.id,
              receipt.inventoryGeneration == inventory.generation, receipt.contractVersion == 1,
              receipt.revision >= 0 else { throw SharedMediaStorageFailure.conflict }
        let members = try Self.fetch(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(),
            maximum: PhotoPreparationPolicy.maximumPackages)
        guard Set(members.map(\.id)) == Set(packages.map(\.id)),
              members.count == packages.count else { throw SharedMediaStorageFailure.conflict }
        for package in packages {
            guard let member = members.first(where: { $0.id == package.id }),
                  member.inventoryID == inventory.id, member.inventoryGeneration == inventory.generation,
                  member.ownerID == package.ownerID, member.draftGeneration == package.draftGeneration,
                  member.revision >= 0, package.revision >= 0,
                  package.draftID == package.id, package.contractVersion == PhotoPreparationPolicy.contract,
                  try SharedMediaMembership.decode(member.membersData) == membership(packageID: package.id) else {
                throw SharedMediaStorageFailure.conflict
            }
            let consumer = try SharedMediaConsumerLookup.one(context, packageID: package.id)
            try SharedMediaMembership.requireMetadataBudget(context: package.supportingContextData,
                membership: member.membersData, cohort: consumer?.cohortData ?? Data())
        }
    }

    private static func fetch<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>,
                                                   maximum: Int) throws -> [T] {
        var query = descriptor; query.fetchLimit = maximum + 1
        let rows = try context.fetch(query)
        guard rows.count <= maximum else { throw SharedMediaStorageFailure.capacity }
        return rows
    }

    @MainActor
    private struct Builder {
        let context: ModelContext
        let inventory: SharedMediaInventoryRecord
        var assets: [UUID: PhotoPreparationAsset] = [:]
        var references: [UUID: PhotoPreparationReference] = [:]
        var work: [UUID: PhotoPreparationLease] = [:]
        var allocations: [UUID: SharedMediaAllocationRecord] = [:]
        var edges: [UUID: SharedMediaReferenceRecord] = [:]
        var leases: [UUID: SharedMediaLeaseRecord] = [:]
        var handoffs: [UUID: SharedMediaInboxHandoffRecord] = [:]
        var pairs: [UUID: SharedMediaDerivativePairRecord] = [:]
        var derivatives: [UUID: SharedMediaDerivativeWorkRecord] = [:]
        var assertions: [UUID: SharedMediaMembership] = [:]

        mutating func include(_ package: PhotoPreparationRecord) throws {
            guard package.draftID == package.id, package.contractVersion == PhotoPreparationPolicy.contract,
                  package.revision >= 0 else { throw SharedMediaStorageFailure.conflict }
            let packageID = package.id
            let refs = try fetch(context, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.packageID == packageID }), maximum: 128)
            let jobs = try fetch(context, FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.packageID == packageID }), maximum: 96)
            let transfers = try fetch(context, FetchDescriptor<SharedMediaInboxHandoffRecord>(predicate: #Predicate { $0.packageID == packageID }), maximum: 8)
            let derivativePairs = try fetch(context, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.packageID == packageID }), maximum: 9)
            var groups: [SharedMediaMembership.Kind: Set<UUID>] = [:]
            var allocationIDs = Set(jobs.map(\.assetID)).union(refs.map(\.assetID))
            var requiredAssets = Set(refs.map(\.assetID))
            for row in refs { references[row.id] = row; groups[.reference, default: []].insert(row.id) }
            for row in jobs {
                guard row.ownerID == package.ownerID else { throw SharedMediaStorageFailure.conflict }
                work[row.id] = row; groups[.work, default: []].insert(row.id)
            }
            for pair in derivativePairs {
                guard pair.inventoryID == inventory.id, pair.inventoryGeneration == inventory.generation,
                      pair.ownerID == package.ownerID, pair.draftGeneration == package.draftGeneration,
                      pair.aiWorkID != pair.displayWorkID else { throw SharedMediaStorageFailure.conflict }
                pairs[pair.id] = pair; groups[.pair, default: []].insert(pair.id)
                let pairID = pair.id
                let children = try fetch(context, FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.pairID == pairID }), maximum: 2)
                guard children.count == 2, Set(children.map(\.id)) == Set([pair.aiWorkID, pair.displayWorkID]) else {
                    throw SharedMediaStorageFailure.conflict
                }
                for child in children {
                    guard child.roleRaw == (child.id == pair.aiWorkID ? "aiInput" : "display"),
                          ["absent", "open", "closed"].contains(child.writerStateRaw),
                          child.writerStateRaw != "absent" || child.finalIdentity == nil else {
                        throw SharedMediaStorageFailure.conflict
                    }
                    derivatives[child.id] = child; groups[.derivative, default: []].insert(child.id)
                    // Planning owns work but has not yet reserved physical storage.
                    if child.writerStateRaw != "absent" { allocationIDs.insert(child.assetID) }
                    if child.finalIdentity != nil { requiredAssets.insert(child.assetID) }
                }
            }
            for transfer in transfers {
                guard transfer.inventoryGeneration == inventory.generation,
                      transfer.ownerID == package.ownerID, transfer.draftGeneration == package.draftGeneration,
                      ["reserved", "writing", "completed", "sourceRetiring", "detached", "detachedRetiring"].contains(transfer.phaseRaw) else {
                    throw SharedMediaStorageFailure.conflict
                }
                handoffs[transfer.id] = transfer; groups[.handoff, default: []].insert(transfer.id)
                allocationIDs.insert(transfer.assetID)
                if !["detached", "detachedRetiring"].contains(transfer.phaseRaw) {
                    let sourceID = transfer.sourceID
                    let source = try required(FetchDescriptor<SharedMediaInboxSourceRecord>(predicate: #Predicate { $0.id == sourceID }))
                    guard source.generation == transfer.sourceGeneration else { throw SharedMediaStorageFailure.conflict }
                    groups[.source, default: []].insert(source.id)
                    groups[.allocation, default: []].insert(source.id)
                    groups[.lease, default: []].insert(source.workID)
                    if source.finalIdentity != nil { groups[.edge, default: []].insert(source.id) }
                    try includeSource(source)
                    let holdID = transfer.sourceHoldID
                    let hold = try required(FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == holdID }))
                    guard hold.allocationID == source.id, hold.roleRaw == SharedMediaInboxHandoffLedger.holdRole,
                          hold.accountID == nil, hold.ownerID == transfer.id.uuidString.lowercased(),
                          hold.stateRaw == "held", hold.revision == 0 else { throw SharedMediaStorageFailure.conflict }
                    edges[hold.id] = hold; groups[.edge, default: []].insert(hold.id)
                } else {
                    let holdID = transfer.sourceHoldID
                    guard try fetch(context, FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == holdID }), maximum: 1).isEmpty else {
                        throw SharedMediaStorageFailure.conflict
                    }
                }
            }
            for id in allocationIDs {
                let allocation = try required(FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == id }))
                let lease = try required(FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.allocationID == id }))
                guard allocation.inventoryID == inventory.id, allocation.accountID == package.ownerID, allocation.namespaceRaw == SharedMediaPhotoLedger.namespace else {
                    throw SharedMediaStorageFailure.conflict
                }
                // allocation.packageID is the physical origin, not this logical owner.
                allocations[id] = allocation; leases[lease.id] = lease
                groups[.allocation, default: []].insert(id); groups[.lease, default: []].insert(lease.id)
                let found = try fetch(context, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == id }), maximum: 1)
                if let asset = found.first {
                    guard asset.ownerID == package.ownerID else { throw SharedMediaStorageFailure.conflict }
                    assets[id] = asset; groups[.asset, default: []].insert(id)
                } else if requiredAssets.contains(id) { throw SharedMediaStorageFailure.conflict }
            }
            for reference in refs {
                let referenceID = reference.id
                let edge = try required(FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == referenceID }))
                guard edge.allocationID == reference.assetID, edge.accountID == package.ownerID,
                      reference.ownerID == package.ownerID, edge.roleRaw == SharedMediaPhotoLedger.namespace,
                      edge.ownerID == referenceID.uuidString.lowercased(), edge.revision == reference.revision,
                      edge.stateRaw == (reference.isLive ? "live" : "retired") else { throw SharedMediaStorageFailure.conflict }
                edges[edge.id] = edge; groups[.edge, default: []].insert(edge.id)
            }
            assertions[packageID] = try SharedMediaMembership(groups: groups.map { kind, ids in
                .init(kind: kind, ids: ids.sorted { $0.uuidString < $1.uuidString })
            }.sorted { $0.kind.rawValue < $1.kind.rawValue })
        }

        mutating func includeSource(_ source: SharedMediaInboxSourceRecord) throws {
            let id = source.id, workID = source.workID
            let allocation = try required(FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == id }))
            let lease = try required(FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.allocationID == id }))
            guard source.inventoryID == inventory.id, allocation.inventoryID == inventory.id,
                  allocation.accountID == nil, allocation.packageID == nil,
                  allocation.namespaceRaw == SharedMediaInboxFiles.namespace,
                  lease.id == workID, lease.allocationID == id, lease.processEpoch == source.writerEpoch, lease.purposeRaw == SharedMediaInboxFiles.namespace else {
                throw SharedMediaStorageFailure.conflict
            }
            allocations[id] = allocation; leases[lease.id] = lease
            let refs = try fetch(context, FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == id }), maximum: 1)
            guard (refs.first != nil) == (source.finalIdentity != nil) else { throw SharedMediaStorageFailure.conflict }
            if let edge = refs.first {
                guard edge.allocationID == id, edge.accountID == nil, edge.roleRaw == SharedMediaInboxFiles.namespace,
                      edge.ownerID == id.uuidString.lowercased(),
                      edge.stateRaw == (source.phaseRaw == "retiring" ? "retired" : "unassigned"),
                      edge.revision == (source.phaseRaw == "retiring" ? 1 : 0) else {
                    throw SharedMediaStorageFailure.conflict
                }
                edges[edge.id] = edge
            }
        }

        func required<T: PersistentModel>(_ query: FetchDescriptor<T>) throws -> T {
            let rows = try fetch(context, query, maximum: 1)
            guard let row = rows.first else { throw SharedMediaStorageFailure.conflict }; return row
        }

        func finish(packages: [PhotoPreparationRecord], sources: [SharedMediaInboxSourceRecord]) throws -> SharedMediaPendingGraph {
            guard assets.count <= 96, references.count <= 128, work.count <= 96,
                  allocations.count <= 104, edges.count <= 144, leases.count <= 104,
                  handoffs.count <= 8, pairs.count <= 9, derivatives.count <= 18 else {
                throw SharedMediaStorageFailure.capacity
            }
            return .init(packages: packages, assets: Array(assets.values), references: Array(references.values),
                work: Array(work.values), allocations: Array(allocations.values), edges: Array(edges.values),
                leases: Array(leases.values), sources: sources, handoffs: Array(handoffs.values),
                pairs: Array(pairs.values), derivatives: Array(derivatives.values),
                inventoryID: inventory.id, inventoryGeneration: inventory.generation, assertions: assertions)
        }
    }
}
