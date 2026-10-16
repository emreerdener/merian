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
