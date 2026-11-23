import Foundation
import SwiftData

/// Read-only reverse links required exclusively by whole-library erasure.
/// The scoped auditor retains paging, exact headers and the exception to normal
/// inspection. These synchronous leaves cannot mint mutation or file authority.
@MainActor
struct SharedMediaNativeErasureReverseAudit {
    typealias Memo = SharedMediaNativeReleaseSurvivorProjection.Memo
    let scope: SharedMediaNativeScopeIdentity
    let ordinary: SharedMediaOrdinaryInspection?
    let package: (UUID, ModelContext, SharedMediaInventoryRecord, Memo) throws -> PhotoPreparationRecord
    let asset: (UUID, ModelContext, SharedMediaInventoryRecord, Memo) throws -> Void
    let pair: (SharedMediaDerivativePairRecord, ModelContext, SharedMediaInventoryRecord, Memo) throws -> Void
    static func requirePartition(container: ModelContainer, scope: SharedMediaNativeScopeIdentity) throws {
        let context = ModelContext(container); context.autosaveEnabled = false
        let id = scope.inventoryID
        guard try context.fetchCount(FetchDescriptor<SharedMediaInventoryRecord>()) == 1,
              try context.fetchCount(FetchDescriptor<SharedMediaMembershipBootstrapRecord>()) == 1,
              try context.fetchCount(FetchDescriptor<SharedMediaNativeErasurePageRecord>()) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaInboxSourceRecord>()) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaInboxHandoffRecord>()) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaDerivativePairRecord>(
                predicate: #Predicate { $0.contractVersion != "nativeDerivativeV2" })) == 0 else {
            throw SharedMediaStorageFailure.conflict
        }
        func all<T: PersistentModel>(_ type: T.Type, _ predicate: Predicate<T>) throws {
            guard try context.fetchCount(FetchDescriptor<T>()) == context.fetchCount(FetchDescriptor<T>(predicate: predicate)) else {
                throw SharedMediaStorageFailure.conflict
            }
        }
        try all(SharedMediaAcquisitionReceiptRecord.self, #Predicate { $0.inventoryID == id })
        try all(SharedMediaAllocationRecord.self, #Predicate { $0.inventoryID == id })
        try all(SharedMediaAssetReferenceCountRecord.self, #Predicate { $0.inventoryID == id })
        try all(SharedMediaCaptureDraftJournalRecord.self, #Predicate { $0.inventoryID == id })
        try all(SharedMediaConsumerRecord.self, #Predicate { $0.inventoryID == id })
        try all(SharedMediaDerivativePairRecord.self, #Predicate { $0.inventoryID == id })
        try all(SharedMediaPendingMembershipRecord.self, #Predicate { $0.inventoryID == id })
        try all(SharedMediaReceivingIntentRecord.self, #Predicate { $0.inventoryID == id })
    }

    func audit(_ row: PhotoPreparationRecord, _ context: ModelContext, _ inventory: SharedMediaInventoryRecord, _ memo: Memo) throws {
        _ = try package(row.id, context, inventory, memo)
        }
    func audit(_ row: PhotoPreparationAsset, _ context: ModelContext, _ inventory: SharedMediaInventoryRecord, _ memo: Memo) throws {
        try asset(row.id, context, inventory, memo)
        }
    func audit(_ row: PhotoPreparationLease, _ context: ModelContext, _ inventory: SharedMediaInventoryRecord, _ memo: Memo) throws {
        let id = row.id
        let shared = try one(context, FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == id }))
        guard row.ownerID == scope.ownerID, shared.allocationID == row.assetID else { throw SharedMediaStorageFailure.conflict }
        try asset(row.assetID, context, inventory, memo)
        }
    func audit(_ row: PhotoPreparationReference, _ context: ModelContext, _ inventory: SharedMediaInventoryRecord, _ memo: Memo) throws {
        let id = row.id
        let shared = try one(context, FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == id }))
        guard row.ownerID == scope.ownerID, shared.allocationID == row.assetID else { throw SharedMediaStorageFailure.conflict }
        try asset(row.assetID, context, inventory, memo)
        _ = try package(row.packageID, context, inventory, memo)
        }
    func audit(_ row: SharedMediaDerivativeWorkRecord, _ context: ModelContext, _ inventory: SharedMediaInventoryRecord, _ memo: Memo) throws {
        guard try SharedMediaNativePairFileGraph.nativeWork(assetID: row.assetID, context: context)?.id == row.id else {
            throw SharedMediaStorageFailure.conflict
        }
        let id = row.pairID
        try pair(one(context, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == id })),
            context, inventory, memo)
        }
    func audit(_ row: SharedMediaLeaseRecord, _ context: ModelContext, _ inventory: SharedMediaInventoryRecord, _ memo: Memo) throws {
        try allocation(row.allocationID, context, inventory, memo)
        }
    func audit(_ row: SharedMediaReferenceRecord, _ context: ModelContext, _ inventory: SharedMediaInventoryRecord, _ memo: Memo) throws {
        try allocation(row.allocationID, context, inventory, memo)
        }
    private func allocation(_ id: UUID, _ context: ModelContext, _ inventory: SharedMediaInventoryRecord, _ memo: Memo) throws {
        let row = try one(context, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == id }))
        guard row.inventoryID == scope.inventoryID, row.accountID == scope.ownerID else { throw SharedMediaStorageFailure.conflict }
        if row.namespaceRaw == SharedMediaCaptureRootJournal.namespace {
            guard let ordinary else { throw SharedMediaStorageFailure.closed }
            try ordinary.captureAllocation(id, context: context)
        } else { try asset(id, context, inventory, memo) }
    }
    private func one<T: PersistentModel>(_ context: ModelContext, _ query: FetchDescriptor<T>) throws -> T {
        try SharedMediaNativePairPlanGraph.one(context, query)
    }
}
