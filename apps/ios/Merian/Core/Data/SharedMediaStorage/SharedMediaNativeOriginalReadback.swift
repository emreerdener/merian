import Foundation
import SwiftData

/// Value-only native queries under repository-minted authority. Contexts and
/// models remain private; this reader has no save or file access operation.
@MainActor
struct SharedMediaNativeOriginalReadback {
    private let container: ModelContainer
    private let inventoryID: UUID
    private let authority: SharedMediaNativeMutationAuthority
    init(container: ModelContainer, inventoryID: UUID, authority: SharedMediaNativeMutationAuthority) {
        self.container = container; self.inventoryID = inventoryID; self.authority = authority
    }
    private func freshContext() -> ModelContext {
        let context = ModelContext(container); context.autosaveEnabled = false
        return context
    }
    private func inventory(_ context: ModelContext) throws -> SharedMediaInventoryRecord {
        let id = inventoryID
        var query = FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }); query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first,
              authority.binding.bytes == (try JSONEncoder().encode(["nativeQualificationV1", row.id.uuidString, row.storeIdentity, row.rootIdentity])) else {
            throw SharedMediaStorageFailure.conflict
        }
        return row
    }
    private func snapshot() throws -> SharedMediaStorageSnapshot {
        try authority.validate()
        let row = try inventory(freshContext())
        return .init(generation: row.generation, revision: row.revision, phase: row.phaseRaw, cursor: row.cursor)
    }

    func request(packageID: UUID, draftGeneration: UUID, ordinal: Int64,
                 kind: SharedMediaAcquisitionIntent.Kind, epoch: UUID) throws -> SharedMediaAcquisitionIntent {
        let snapshot = try snapshot()
        let ownerID = authority.ownerID
        guard epoch == authority.writerEpoch else { throw SharedMediaStorageFailure.conflict }
        let context = freshContext()
        var query = FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }); query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
        if let row = rows.first {
            guard row.ownerID == ownerID, row.draftGeneration == draftGeneration, row.accountingTierRaw == "pending",
                  row.phaseRaw == "draftOwned", !row.retirementRequested else { throw SharedMediaStorageFailure.stale }
        }
        let request = SharedMediaAcquisitionIntent(operationID: UUID(), inventoryID: inventoryID, inventoryGeneration: snapshot.generation,
            ownerID: ownerID, expectedInventoryRevision: snapshot.revision, packageID: packageID, draftGeneration: draftGeneration,
            packageExpectation: rows.first.map { .revision($0.revision) } ?? .absent, assetID: UUID(), assetGeneration: UUID(),
            referenceID: UUID(), ordinal: ordinal, kind: kind, writerEpoch: epoch, maximumBytes: PhotoPreparationPolicy.original)
        try request.validate(); return request
    }

    func receipt(_ request: SharedMediaAcquisitionIntent) throws -> SharedMediaAcquisitionReceipt? {
        let snapshot = try snapshot()
        guard request.inventoryID == inventoryID, request.inventoryGeneration == snapshot.generation,
              request.ownerID == authority.ownerID else { throw SharedMediaStorageFailure.conflict }
        let context = freshContext()
        let id = request.operationID
        var query = FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id }); query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
        return try rows.first.map { try SharedMediaAcquisitionReceipt.read($0, expected: request) }
    }

    func reservedState(_ request: SharedMediaAcquisitionIntent) throws -> SharedMediaNativeReservedState {
        guard case .reserved = try receipt(request) else { throw SharedMediaStorageFailure.conflict }
        return try .init(inventory: snapshot(), context: freshContext(), request: request)
    }

    struct Entry: Sendable {
        let receipt: SharedMediaAcquisitionReceipt
        let retirement: SharedMediaNativeRetirementIdentity?
    }

    func page(offset: Int, inspection: SharedMediaNativeInspectionAuthority) throws -> [Entry] {
        guard offset >= 0 else { throw SharedMediaStorageFailure.invalid }
        try inspection.validate()
        let context = freshContext()
        let inventory = try inventory(context)
        var query = FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(sortBy: [SortDescriptor(\.id)])
        query.fetchLimit = SharedMediaStoragePolicy.pageSize; query.fetchOffset = offset
        return try context.fetch(query).map { row in
            guard row.ownerID == inspection.ownerID else { throw PhotoPreparationFailure.accountChanged }
            let receipt = try SharedMediaNativeAcquisitionGraph.receipt(row, inventory: inventory, context: context)
            let retirement: SharedMediaNativeRetirementIdentity?
            if case .completed(let request, _) = receipt {
                retirement = try SharedMediaNativeOriginalAccounting.audit(assetID: request.assetID, inventoryID: inventoryID, context: context).retirement
            } else { retirement = nil }
            return .init(receipt: receipt, retirement: retirement)
        }
    }

}

struct SharedMediaNativeOriginalSnapshot: Equatable, Sendable {
    let inventory: SharedMediaStorageSnapshot
    let requiresRecovery: Bool
}
