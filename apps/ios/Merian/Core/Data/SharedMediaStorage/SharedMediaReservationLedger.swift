import Foundation
import SwiftData

/// Validates the original observation/reservation graph. Photo and inbox modes
/// have their own typed joins; this owner grants no write or release authority.
@MainActor
struct SharedMediaReservationLedger {
    let context: ModelContext
    let inventoryID: UUID
    let mode: SharedMediaStorageMode
    let sources: Set<String>

    func validate() throws -> SharedMediaStoragePolicy.Totals {
        var totals = SharedMediaStoragePolicy.Totals()
        var packageAccounts: [UUID: UUID] = [:]
        try visit(context, SharedMediaAllocationRecord.self) { row in
            guard row.inventoryID == inventoryID, let pool = SharedMediaStoragePool(rawValue: row.poolRaw),
                  ["legacyObserved", "reserved", "retiring"].contains(row.stateRaw),
                  (pool == .observed) == (row.stateRaw == "legacyObserved"),
                  pool == .observed || row.accountID != nil else { throw SharedMediaStorageFailure.conflict }
            try SharedMediaStoragePolicy.token(row.namespaceRaw)
            try SharedMediaStoragePolicy.token(row.fileToken)
            if pool == .observed {
                guard mode == .observation, row.accountID == nil, sources.contains(row.namespaceRaw),
                      let identity = row.physicalIdentity, !identity.isEmpty, identity.utf8.count <= 256 else { throw SharedMediaStorageFailure.conflict }
            } else {
                guard mode == .qualification, row.namespaceRaw == "qualification",
                      row.fileToken == row.id.uuidString.lowercased(), row.physicalIdentity == nil,
                      row.materializedBytes == 0, row.reservedBytes > 0 else { throw SharedMediaStorageFailure.conflict }
            }
            if let package = row.packageID, let account = row.accountID {
                guard packageAccounts[package].map({ $0 == account }) ?? true else { throw SharedMediaStorageFailure.conflict }
                packageAccounts[package] = account
            }
            try totals.include(.init(packageID: row.packageID, pool: pool, materialized: row.materializedBytes, reserved: row.reservedBytes))
        }
        try visit(context, SharedMediaReferenceRecord.self) { row in
            try SharedMediaStoragePolicy.token(row.ownerID)
            try SharedMediaStoragePolicy.token(row.roleRaw)
            guard let parent: SharedMediaAllocationRecord = try one(context, id: row.allocationID),
                  parent.inventoryID == inventoryID, parent.accountID == row.accountID, row.revision >= 0,
                  ["live", "retired", "observed"].contains(row.stateRaw),
                  (parent.poolRaw == "observed") == (row.stateRaw == "observed"),
                  parent.stateRaw != "retiring" || row.stateRaw == "retired" else { throw SharedMediaStorageFailure.conflict }
        }
        try visit(context, SharedMediaLeaseRecord.self) { row in
            guard let parent: SharedMediaAllocationRecord = try one(context, id: row.allocationID),
                  parent.inventoryID == inventoryID, parent.poolRaw != "observed", row.purposeRaw == "localQualification",
                  ["open", "closed", "unknown"].contains(row.stateRaw),
                  parent.stateRaw != "retiring" || row.stateRaw == "closed" else { throw SharedMediaStorageFailure.conflict }
        }
        return totals
    }

    func observe(_ items: [SharedMediaStorageObservation]) throws {
        guard mode == .observation else { throw SharedMediaStorageFailure.closed }
        for item in items {
            try SharedMediaStoragePolicy.token(item.namespace)
            try SharedMediaStoragePolicy.token(item.token)
            guard item.bytes >= 0, !item.physicalIdentity.isEmpty,
                  item.physicalIdentity.utf8.count <= 256 else { throw SharedMediaStorageFailure.invalid }
            if let prior: SharedMediaAllocationRecord = try one(context, id: item.id) {
                guard prior.inventoryID == inventoryID, prior.poolRaw == "observed",
                      prior.namespaceRaw == item.namespace, prior.fileToken == item.token,
                      prior.materializedBytes == item.bytes, prior.physicalIdentity == item.physicalIdentity else {
                    throw SharedMediaStorageFailure.conflict
                }
            } else {
                var duplicate = false
                try visit(context, SharedMediaAllocationRecord.self) {
                    if $0.namespaceRaw == item.namespace && $0.fileToken == item.token { duplicate = true }
                }
                guard !duplicate else { throw SharedMediaStorageFailure.conflict }
                context.insert(SharedMediaAllocationRecord(id: item.id, inventoryID: inventoryID,
                    accountID: nil, packageID: nil, namespaceRaw: item.namespace, fileToken: item.token,
                    poolRaw: "observed", stateRaw: "legacyObserved", materializedBytes: item.bytes,
                    reservedBytes: 0, physicalIdentity: item.physicalIdentity))
            }
        }
    }

    private func one(_ context: ModelContext, id: UUID) throws -> SharedMediaAllocationRecord? {
        var query = FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == id })
        query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
        return rows.first
    }

    private func visit<T: SharedMediaReservationRow>(_ context: ModelContext, _ type: T.Type, body: (T) throws -> Void) throws {
        var offset = 0
        while true {
            var query = FetchDescriptor<T>(sortBy: [SortDescriptor(\.id)])
            query.fetchLimit = SharedMediaStoragePolicy.pageSize; query.fetchOffset = offset
            let page = try context.fetch(query)
            for row in page { try body(row) }
            if page.count < SharedMediaStoragePolicy.pageSize { break }
            offset += page.count
        }
    }
}
private protocol SharedMediaReservationRow: PersistentModel { var id: UUID { get } }
extension SharedMediaAllocationRecord: SharedMediaReservationRow {}
extension SharedMediaReferenceRecord: SharedMediaReservationRow {}
extension SharedMediaLeaseRecord: SharedMediaReservationRow {}

/// Held-context mutations for the original non-file qualification graph. The
/// repository retains identity checks, exclusive fences and every save.
@MainActor
struct SharedMediaQualificationLedger {
    let context: ModelContext
    let inventory: SharedMediaInventoryRecord
    let mode: SharedMediaStorageMode
    let processEpoch: UUID
    private var inventoryID: UUID { inventory.id }

    func reserve(_ request: SharedMediaStorageReservation, expected: SharedMediaStorageSnapshot, availableBytes: () throws -> Int64) throws -> Bool {
        try requireQualification(inventory)
        guard inventory.generation == expected.generation else { throw SharedMediaStorageFailure.stale }
        guard request.pool != .observed, request.bytes > 0 else { throw SharedMediaStorageFailure.invalid }
        if let prior: SharedMediaAllocationRecord = try SharedMediaStorageLookup.one(context, id: request.id) {
            guard prior.stateRaw == "reserved", prior.accountID == request.accountID,
                  prior.packageID == request.packageID, prior.poolRaw == request.pool.rawValue,
                  prior.reservedBytes == request.bytes else { throw SharedMediaStorageFailure.conflict }
            return false // Exact saved reservation, never a renewed identity/allowance.
        }
        try revision(inventory, expected)
        try SharedMediaStorageLookup.visit(context, SharedMediaAllocationRecord.self) {
            if $0.packageID == request.packageID && $0.accountID != request.accountID { throw SharedMediaStorageFailure.conflict }
        }
        var totals = try SharedMediaReservationLedger(context: context, inventoryID: inventoryID, mode: mode, sources: []).validate()
        try totals.include(.init(packageID: request.packageID, pool: request.pool, materialized: 0, reserved: request.bytes))
        try totals.checkAvailable(availableBytes())
        context.insert(SharedMediaAllocationRecord(id: request.id, inventoryID: inventoryID,
            accountID: request.accountID, packageID: request.packageID, namespaceRaw: "qualification",
            fileToken: request.id.uuidString.lowercased(), poolRaw: request.pool.rawValue,
            stateRaw: "reserved", materializedBytes: 0, reservedBytes: request.bytes, physicalIdentity: nil))
        return true
    }

    func acquireReference(id: UUID, allocationID: UUID, accountID: UUID, ownerID: String,
                          role: String, expected: SharedMediaStorageSnapshot) throws -> Bool {
        try requireQualification(inventory)
        try SharedMediaStoragePolicy.token(ownerID)
        try SharedMediaStoragePolicy.token(role)
        let allocation = try mutableAllocation(context, allocationID)
        guard allocation.accountID == accountID else { throw SharedMediaStorageFailure.conflict }
        guard inventory.generation == expected.generation else { throw SharedMediaStorageFailure.stale }
        if let prior: SharedMediaReferenceRecord = try SharedMediaStorageLookup.one(context, id: id) {
            guard prior.allocationID == allocationID, prior.accountID == accountID,
                  prior.ownerID == ownerID, prior.roleRaw == role, prior.stateRaw == "live" else {
                throw SharedMediaStorageFailure.conflict
            }
            return false
        }
        try revision(inventory, expected)
        context.insert(SharedMediaReferenceRecord(id: id, allocationID: allocationID,
            accountID: accountID, ownerID: ownerID, roleRaw: role, stateRaw: "live", revision: 0))
        return true
    }

    func releaseReference(id: UUID, expected: SharedMediaStorageSnapshot) throws -> Bool {
        guard !mode.includesPhotoStorage else { throw SharedMediaStorageFailure.closed }
        guard let edge: SharedMediaReferenceRecord = try SharedMediaStorageLookup.one(context, id: id) else { throw SharedMediaStorageFailure.invalid }
        guard inventory.generation == expected.generation else { throw SharedMediaStorageFailure.stale }
        if edge.stateRaw == "retired" { return false }
        try revision(inventory, expected)
        guard edge.stateRaw == "live" else { throw SharedMediaStorageFailure.conflict }
        edge.stateRaw = "retired"
        edge.revision = try SharedMediaStoragePolicy.add(edge.revision, 1)
        return true
    }

    func startLocalLease(id: UUID, allocationID: UUID, expected: SharedMediaStorageSnapshot) throws -> Bool {
        try requireQualification(inventory)
        _ = try mutableAllocation(context, allocationID)
        guard inventory.generation == expected.generation else { throw SharedMediaStorageFailure.stale }
        if let old: SharedMediaLeaseRecord = try SharedMediaStorageLookup.one(context, id: id) {
            guard old.allocationID == allocationID, old.processEpoch == processEpoch,
                  old.stateRaw == "open" else { throw SharedMediaStorageFailure.conflict }
            return false
        }
        try revision(inventory, expected)
        context.insert(SharedMediaLeaseRecord(id: id, allocationID: allocationID, processEpoch: processEpoch,
            purposeRaw: "localQualification", stateRaw: "open"))
        return true
    }

    func finishLocalLease(id: UUID, expected: SharedMediaStorageSnapshot) throws -> Bool {
        guard !mode.includesPhotoStorage else { throw SharedMediaStorageFailure.closed }
        guard let lease: SharedMediaLeaseRecord = try SharedMediaStorageLookup.one(context, id: id),
              lease.processEpoch == processEpoch, lease.purposeRaw == "localQualification" else {
            throw SharedMediaStorageFailure.conflict
        }
        guard inventory.generation == expected.generation else { throw SharedMediaStorageFailure.stale }
        if lease.stateRaw == "closed" { return false }
        try revision(inventory, expected)
        guard lease.stateRaw == "open" else { throw SharedMediaStorageFailure.inUse }
        lease.stateRaw = "closed"
        return true
    }

    func retire(allocationID: UUID, expected: SharedMediaStorageSnapshot) throws -> Bool {
        guard mode == .qualification else { throw SharedMediaStorageFailure.closed }
        guard let allocation: SharedMediaAllocationRecord = try SharedMediaStorageLookup.one(context, id: allocationID),
              allocation.poolRaw != "observed" else { throw SharedMediaStorageFailure.invalid }
        guard inventory.generation == expected.generation else { throw SharedMediaStorageFailure.stale }
        if allocation.stateRaw == "retiring" { return false }
        try revision(inventory, expected)
        _ = try mutableAllocation(context, allocationID)
        var held = false
        try SharedMediaStorageLookup.visit(context, SharedMediaReferenceRecord.self) { if $0.allocationID == allocationID && $0.stateRaw != "retired" { held = true } }
        try SharedMediaStorageLookup.visit(context, SharedMediaLeaseRecord.self) { if $0.allocationID == allocationID && $0.stateRaw != "closed" { held = true } }
        guard !held else { throw SharedMediaStorageFailure.inUse }
        allocation.stateRaw = "retiring" // Irreversible; bytes remain charged, no physical-release API.
        return true
    }

    func closeAdmission(expected: SharedMediaStorageSnapshot) throws -> Bool {
        guard !mode.includesPhotoStorage else { throw SharedMediaStorageFailure.closed }
        guard inventory.generation == expected.generation else { throw SharedMediaStorageFailure.stale }
        if inventory.phaseRaw == "retiring" { return false }
        try revision(inventory, expected)
        inventory.phaseRaw = "retiring"
        return true
    }

    func retireAccountReferences(_ accountID: UUID, expected: SharedMediaStorageSnapshot) throws -> Bool {
        guard !mode.includesPhotoStorage else { throw SharedMediaStorageFailure.closed }
        try revision(inventory, expected)
        try SharedMediaStorageLookup.visit(context, SharedMediaReferenceRecord.self) {
            if $0.accountID == accountID && $0.stateRaw == "live" {
                $0.stateRaw = "retired"
                $0.revision = try SharedMediaStoragePolicy.add($0.revision, 1)
            }
        }
        return true
    }

    private func mutableAllocation(_ context: ModelContext, _ id: UUID) throws -> SharedMediaAllocationRecord {
        guard let item: SharedMediaAllocationRecord = try SharedMediaStorageLookup.one(context, id: id), item.stateRaw == "reserved" else {
            throw SharedMediaStorageFailure.closed
        }
        return item
    }

    private func requireQualification(_ inventory: SharedMediaInventoryRecord) throws {
        guard mode == .qualification, inventory.phaseRaw == "readyQualification" else { throw SharedMediaStorageFailure.closed }
    }

    private func revision(_ inventory: SharedMediaInventoryRecord, _ expected: SharedMediaStorageSnapshot) throws {
        guard inventory.generation == expected.generation, inventory.revision == expected.revision else { throw SharedMediaStorageFailure.stale }
    }
}
