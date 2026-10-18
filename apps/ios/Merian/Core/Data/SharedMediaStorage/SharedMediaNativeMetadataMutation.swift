import Foundation
import SwiftData

/// Exact local edit intent. These values grant no storage or account authority.
/// Retain the produced bytes across retries; JSON key order is not an identity.
struct SharedMediaNativeMetadataRequest: Equatable, Sendable {
    let inventoryID: UUID
    let inventoryGeneration: UUID
    let ownerID: UUID
    let packageID: UUID
    let draftGeneration: UUID
    let inventoryRevision: Int64
    let packageRevision: Int64
    let membershipRevision: Int64
    let membershipBytes: Data
    let previousEnvelope: Data
    let envelope: Data
    var growth: Int64 { max(0, Int64(envelope.count) - Int64(previousEnvelope.count)) }
}

enum SharedMediaNativeMetadataBoundary: Equatable, Sendable { case beforeSave, afterSave, beforeReadback }

/// Synchronous metadata-only transaction under the repository's sealed authority.
/// All queried models and the sole save context stay private to this helper.
@MainActor
final class SharedMediaNativeMetadataMutation {
    private let container: ModelContainer
    private let context: ModelContext
    private let inventory: SharedMediaInventoryRecord
    private let package: PhotoPreparationRecord
    private let member: SharedMediaPendingMembershipRecord
    private let authority: SharedMediaNativeMutationAuthority
    private var consumed = false

    init(container: ModelContainer, inventoryID: UUID, packageID: UUID, authority: SharedMediaNativeMutationAuthority) throws {
        try authority.validate()
        self.authority = authority; self.container = container
        context = ModelContext(container); context.autosaveEnabled = false
        inventory = try Self.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        guard !authority.binding.initializing,
              authority.binding.bytes == (try JSONEncoder().encode(["nativeQualificationV1", inventory.id.uuidString, inventory.storeIdentity, inventory.rootIdentity])) else {
            throw SharedMediaStorageFailure.conflict
        }
        try SharedMediaNativeAcquisitionGraph.audit(context: context, inventoryID: inventoryID)
        package = try Self.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        member = try Self.one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        guard package.ownerID == authority.ownerID, package.accountingTierRaw == "pending", package.phaseRaw == "draftOwned",
              !package.retirementRequested, member.ownerID == authority.ownerID,
              member.inventoryID == inventoryID, member.inventoryGeneration == inventory.generation,
              member.draftGeneration == package.draftGeneration,
              try context.fetchCount(FetchDescriptor<PhotoPreparationLease>()) == 0,
              try context.fetchCount(FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.cleanupStateRaw != "ready" })) == 0 else {
            throw SharedMediaStorageFailure.closed
        }
    }

    func request(draftGeneration: UUID, contexts: [ObservationContext], presentation: [PhotoPreparationImagePresentation]?) throws -> SharedMediaNativeMetadataRequest {
        guard package.draftGeneration == draftGeneration else { throw SharedMediaStorageFailure.stale }
        let previous = try PhotoPreparationPolicy.decodeDraft(package.supportingContextData)
        let photos = presentation ?? previous.presentation
        let envelope = try PhotoPreparationPolicy.encodeDraft(contexts: contexts, presentation: photos)
        try SharedMediaNativeAcquisitionGraph.validatePresentation(photos, package: package, context: context)
        return .init(inventoryID: inventory.id, inventoryGeneration: inventory.generation, ownerID: package.ownerID,
            packageID: package.id, draftGeneration: draftGeneration, inventoryRevision: inventory.revision,
            packageRevision: package.revision, membershipRevision: member.revision, membershipBytes: member.membersData,
            previousEnvelope: package.supportingContextData, envelope: envelope)
    }

    func result(_ request: SharedMediaNativeMetadataRequest) throws -> Int64 {
        try validate(request)
        guard matchesResult(request) else { throw SharedMediaStorageFailure.stale }
        return package.revision
    }

    func apply(_ request: SharedMediaNativeMetadataRequest, availableBytes: Int64,
               beforeSave: () throws -> Void, afterSave: () throws -> Void) throws -> Int64 {
        guard !consumed else { throw SharedMediaStorageFailure.closed }
        consumed = true
        try validate(request)
        if matchesResult(request) { return package.revision }
        guard inventory.revision == request.inventoryRevision, package.revision == request.packageRevision,
              package.supportingContextData == request.previousEnvelope else { throw SharedMediaStorageFailure.stale }
        package.supportingContextData = request.envelope
        package.revision = try SharedMediaStoragePolicy.add(request.packageRevision, 1)
        inventory.revision = try SharedMediaStoragePolicy.add(request.inventoryRevision, 1)
        guard matchesResult(request) else { throw SharedMediaStorageFailure.conflict }
        let graph = try SharedMediaPendingGraph.derive(in: context, inventory: inventory)
        try graph.validateMembership(in: context, inventory: inventory)
        let budget = try SharedMediaNativeAcquisitionBudget.evaluate(context: context, inventory: inventory)
        try budget.totals.checkAvailable(availableBytes, additionalReservation: request.growth)
        try beforeSave()
        let fresh = try Self(container: container, inventoryID: inventory.id, packageID: package.id, authority: authority)
        try fresh.validate(request)
        guard fresh.inventory.revision == request.inventoryRevision, fresh.package.revision == request.packageRevision,
              fresh.package.supportingContextData == request.previousEnvelope else { throw SharedMediaStorageFailure.stale }
        do { try context.save() } catch { context.rollback(); throw error }
        try afterSave()
        return package.revision
    }

    private func matchesResult(_ request: SharedMediaNativeMetadataRequest) -> Bool {
        inventory.revision == request.inventoryRevision + 1 && package.revision == request.packageRevision + 1
            && package.supportingContextData == request.envelope
            && member.revision == request.membershipRevision && member.membersData == request.membershipBytes
    }

    private func validate(_ request: SharedMediaNativeMetadataRequest) throws {
        try authority.validate()
        guard request.inventoryID == inventory.id, request.inventoryGeneration == inventory.generation,
              request.ownerID == authority.ownerID, request.packageID == package.id, request.draftGeneration == package.draftGeneration,
              request.inventoryRevision >= 0, request.inventoryRevision < Int64.max,
              request.packageRevision >= 0, request.packageRevision < Int64.max,
              request.membershipRevision == member.revision, request.membershipBytes == member.membersData else {
            throw SharedMediaStorageFailure.stale
        }
        _ = try PhotoPreparationPolicy.decodeDraft(request.previousEnvelope)
        let next = try PhotoPreparationPolicy.decodeDraft(request.envelope)
        try SharedMediaNativeAcquisitionGraph.validatePresentation(next.presentation, package: package, context: context)
    }

    private static func one<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>) throws -> T {
        var query = descriptor; query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first else { throw SharedMediaStorageFailure.conflict }
        return row
    }
}
