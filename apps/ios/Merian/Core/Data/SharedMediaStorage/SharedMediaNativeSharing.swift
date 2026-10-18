import Foundation
import SwiftData

/// One closed sharing transaction. It never copies media or mutates the source
/// membership. Private contexts are discarded after the single save attempt.
@MainActor
final class SharedMediaNativeSharing {
    private let container: ModelContainer, context: ModelContext
    private let inventory: SharedMediaInventoryRecord
    private let authority: SharedMediaNativeMutationAuthority
    init(container: ModelContainer, inventoryID: UUID, authority: SharedMediaNativeMutationAuthority) throws {
        try authority.validate()
        self.container = container; self.authority = authority
        context = ModelContext(container); context.autosaveEnabled = false
        inventory = try Self.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        guard authority.binding.bytes == (try JSONEncoder().encode(["nativeQualificationV1", inventory.id.uuidString, inventory.storeIdentity, inventory.rootIdentity])) else { throw SharedMediaStorageFailure.conflict }
        try SharedMediaNativeAcquisitionGraph.audit(context: context, inventoryID: inventoryID)
    }
    func prepare(_ source: PhotoOriginalReference, packageID: UUID, draftGeneration: UUID) throws -> SharedMediaNativeShareRequest {
        let (package, count) = try sourceState(source)
        try requireNoRecovery()
        guard try optionalPackage(packageID) == nil else { throw SharedMediaStorageFailure.stale }
        return .init(source: source, inventoryID: inventory.id, inventoryGeneration: inventory.generation,
            inventoryRevision: inventory.revision, sourcePackageRevision: package.revision, liveCount: count.liveCount,
            countRevision: count.revision, packageID: packageID, draftGeneration: draftGeneration, nonce: UUID(),
            envelope: try PhotoPreparationPolicy.encodeDraft(contexts: []))
    }
    func result(_ request: SharedMediaNativeShareRequest) throws -> PhotoOriginalReference {
        try validate(request)
        let destination = try request.destination(), id = destination.referenceID, assetID = destination.assetID
        let package = try Self.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == request.packageID }))
        let member = try Self.one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == request.packageID }))
        let ref = try Self.one(context, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == id }))
        let edge = try Self.one(context, FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == id }))
        let count = try Self.one(context, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID }))
        guard inventory.revision == request.inventoryRevision + 1,
              package.ownerID == destination.ownerID, package.draftGeneration == destination.draftGeneration,
              package.revision == 0, package.phaseRaw == "draftOwned", package.accountingTierRaw == "pending", !package.retirementRequested,
              package.supportingContextData == request.envelope, member.revision == 0,
              ref.assetID == destination.assetID, ref.packageID == destination.packageID, ref.isLive, ref.ordinal == 0, ref.revision == 0,
              edge.allocationID == destination.assetID, edge.stateRaw == "live", edge.revision == 0,
              count.liveCount == request.liveCount + 1, count.revision == request.countRevision + 1, count.retirementID == nil else {
            throw SharedMediaStorageFailure.stale
        }
        return destination
    }
    func apply(_ request: SharedMediaNativeShareRequest, availableBytes: Int64, beforeSave: () throws -> Void, afterSave: () throws -> Void) throws {
        try validate(request)
        if (try? result(request)) != nil { return }
        try requireBefore(request)
        let destination = try request.destination(), sourceID = request.source.assetID
        let asset = try Self.one(context, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == sourceID }))
        let count = try Self.one(context, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == sourceID }))
        let package = PhotoPreparationRecord(id: destination.packageID, ownerID: destination.ownerID, contractVersion: PhotoPreparationPolicy.contract,
            draftID: destination.packageID, draftGeneration: destination.draftGeneration, revision: 0, phaseRaw: "draftOwned",
            supportingContextData: request.envelope, allocatedByteCount: asset.byteCount, retirementRequested: false)
        context.insert(package)
        context.insert(PhotoPreparationReference(id: destination.referenceID, packageID: destination.packageID, assetID: destination.assetID,
            ownerID: destination.ownerID, roleRaw: "original", ordinal: 0, revision: 0, isLive: true))
        context.insert(SharedMediaReferenceRecord(id: destination.referenceID, allocationID: destination.assetID, accountID: destination.ownerID,
            ownerID: destination.referenceID.uuidString.lowercased(), roleRaw: SharedMediaPhotoLedger.namespace, stateRaw: "live", revision: 0))
        count.liveCount = try SharedMediaStoragePolicy.add(count.liveCount, 1)
        count.revision = try SharedMediaStoragePolicy.add(count.revision, 1)
        inventory.revision = try SharedMediaStoragePolicy.add(inventory.revision, 1)
        let graph = try SharedMediaPendingGraph.derive(in: context, inventory: inventory)
        context.insert(try SharedMediaPendingMembershipRecord(packageID: package.id, inventoryID: inventory.id, inventoryGeneration: inventory.generation,
            ownerID: package.ownerID, draftGeneration: package.draftGeneration, membersData: graph.membership(packageID: package.id).encoded()))
        try graph.validateMembership(in: context, inventory: inventory)
        let budget = try SharedMediaNativeAcquisitionBudget.evaluate(context: context, inventory: inventory)
        try budget.totals.checkAvailable(availableBytes, additionalReservation: budget.metadataByPackage[package.id] ?? 0)
        _ = try result(request)
        try beforeSave()
        try Self(container: container, inventoryID: inventory.id, authority: authority).requireBefore(request)
        do { try context.save() } catch { context.rollback(); throw error }
        try afterSave()
    }
    private func requireBefore(_ request: SharedMediaNativeShareRequest) throws {
        try validate(request); try requireNoRecovery()
        let (package, count) = try sourceState(request.source)
        let id = try request.destination().referenceID
        guard inventory.revision == request.inventoryRevision, package.revision == request.sourcePackageRevision,
              count.liveCount == request.liveCount, count.revision == request.countRevision,
              try optionalPackage(request.packageID) == nil,
              try context.fetchCount(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == id })) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == id })) == 0 else { throw SharedMediaStorageFailure.stale }
    }
    private func validate(_ request: SharedMediaNativeShareRequest) throws {
        try authority.validate(); try request.source.validate()
        let envelope = try PhotoPreparationPolicy.decodeDraft(request.envelope)
        guard request.inventoryID == inventory.id, request.inventoryGeneration == inventory.generation,
              request.source.ownerID == authority.ownerID, request.source.packageID != request.packageID,
              request.inventoryRevision >= 0, request.inventoryRevision < Int64.max,
              request.sourcePackageRevision >= 0, request.liveCount > 0, request.liveCount < Int64.max,
              request.countRevision >= 0, request.countRevision < Int64.max,
              envelope.contexts.isEmpty, envelope.presentation.isEmpty else { throw SharedMediaStorageFailure.stale }
    }
    private func sourceState(_ handle: PhotoOriginalReference) throws -> (PhotoPreparationRecord, SharedMediaAssetReferenceCountRecord) {
        try handle.validate()
        let id = handle.referenceID, assetID = handle.assetID
        let package = try Self.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == handle.packageID }))
        let ref = try Self.one(context, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == id }))
        let count = try Self.one(context, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID }))
        guard handle.ownerID == authority.ownerID, ref.ownerID == handle.ownerID, ref.packageID == handle.packageID,
              ref.assetID == assetID, ref.isLive, ref.revision == handle.referenceRevision,
              count.assetGeneration == handle.assetGeneration, count.liveCount > 0, count.retirementID == nil,
              package.draftGeneration == handle.draftGeneration, package.phaseRaw == "draftOwned", !package.retirementRequested else { throw SharedMediaStorageFailure.stale }
        return (package, count)
    }
    private func requireNoRecovery() throws {
        guard try context.fetchCount(FetchDescriptor<PhotoPreparationLease>()) == 0,
              try context.fetchCount(FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.cleanupStateRaw != "ready" })) == 0 else { throw PhotoPreparationFailure.cleanupPending }
    }
    private func optionalPackage(_ id: UUID) throws -> PhotoPreparationRecord? {
        var q = FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id }); q.fetchLimit = 2
        let rows = try context.fetch(q); guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }; return rows.first
    }
    private static func one<T: PersistentModel>(_ context: ModelContext, _ query: FetchDescriptor<T>) throws -> T {
        var query = query; query.fetchLimit = 2; let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first else { throw SharedMediaStorageFailure.conflict }; return row
    }
}
