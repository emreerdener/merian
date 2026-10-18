import Foundation
import SwiftData

/// Envelope-only preparation reservation. The sealed repository supplies the
/// account/store authority. This transaction cannot load, process or write media.
@MainActor
final class SharedMediaNativePreparationMutation {
    private let container: ModelContainer
    private let context: ModelContext
    private let inventory: SharedMediaInventoryRecord
    private let package: PhotoPreparationRecord
    private let member: SharedMediaPendingMembershipRecord
    private let authority: SharedMediaNativeMutationAuthority

    init(container: ModelContainer, inventoryID: UUID, packageID: UUID, authority: SharedMediaNativeMutationAuthority) throws {
        try authority.validate()
        self.container = container; self.authority = authority
        context = ModelContext(container); context.autosaveEnabled = false
        inventory = try Self.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        guard !authority.binding.initializing,
              authority.binding.bytes == (try JSONEncoder().encode(["nativeQualificationV1", inventory.id.uuidString, inventory.storeIdentity, inventory.rootIdentity])) else {
            throw SharedMediaStorageFailure.conflict
        }
        try SharedMediaNativeAcquisitionGraph.audit(context: context, inventoryID: inventoryID)
        package = try Self.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        member = try Self.one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        guard package.ownerID == authority.ownerID, package.accountingTierRaw == "pending", !package.retirementRequested,
              member.ownerID == authority.ownerID, member.inventoryID == inventoryID,
              member.inventoryGeneration == inventory.generation, member.draftGeneration == package.draftGeneration else { throw SharedMediaStorageFailure.closed }
    }

    func request(original: PhotoOriginalReference, recipe: SharedMediaNativePreparationRecipe) throws -> SharedMediaNativePreparationAttempt {
        try original.validate(); try recipe.validate()
        let previous = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData)
        guard original.packageID == package.id, original.ownerID == package.ownerID, original.draftGeneration == package.draftGeneration,
              package.phaseRaw == "draftOwned", previous.attempt == nil,
              try context.fetchCount(FetchDescriptor<PhotoPreparationLease>()) == 0,
              try context.fetchCount(FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.cleanupStateRaw != "ready" })) == 0 else { throw SharedMediaStorageFailure.closed }
        try SharedMediaNativePreparationGraph.requireNoUnfinished(context)
        let id = original.referenceID, assetID = original.assetID
        let ref = try Self.one(context, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == id }))
        let asset = try Self.one(context, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID }))
        let receipt = try Self.one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == assetID }))
        guard ref.isLive, ref.packageID == original.packageID, ref.ownerID == original.ownerID, ref.assetID == assetID,
              ref.revision == original.referenceRevision, ref.roleRaw == "original", asset.generation == original.assetGeneration,
              case .completed(_, let result) = try SharedMediaAcquisitionReceipt.read(receipt) else { throw SharedMediaStorageFailure.stale }
        let request = SharedMediaNativePreparationAttempt(format: .attempt,
            sequence: try SharedMediaStoragePolicy.add(previous.sequence, 1), operationID: UUID(), writerEpoch: authority.writerEpoch,
            inventoryID: inventory.id, inventoryGeneration: inventory.generation, inventoryRevision: inventory.revision,
            packageRevision: package.revision, membershipRevision: member.revision, membershipBytes: member.membersData,
            previousEnvelope: package.supportingContextData,
            original: .init(reference: original, ordinal: ref.ordinal, token: asset.fileToken, byteCount: asset.byteCount,
                sha256: asset.sha256, contentType: asset.contentType, descriptor: result.descriptor), recipe: recipe)
        try request.validate(); return request
    }

    func result(_ request: SharedMediaNativePreparationAttempt) throws {
        try validateIdentity(request)
        guard inventory.revision == request.inventoryRevision + 1, package.revision == request.packageRevision + 1,
              package.phaseRaw == "preparing", package.supportingContextData == (try reservedEnvelope(request)) else {
            throw SharedMediaStorageFailure.stale
        }
    }

    func reserve(_ request: SharedMediaNativePreparationAttempt, availableBytes: Int64,
                 beforeSave: () throws -> Void, afterSave: () throws -> Void) throws {
        try requireBefore(request)
        package.supportingContextData = try reservedEnvelope(request)
        package.phaseRaw = "preparing"
        package.revision = request.packageRevision + 1; inventory.revision = request.inventoryRevision + 1
        try result(request)
        let budget = try SharedMediaNativeAcquisitionBudget.evaluate(context: context, inventory: inventory)
        // Metadata now represented in this unsaved context still needs free
        // bytes; the remaining metadata/output reservations are in totals.
        let growth = max(0, Int64(package.supportingContextData.count - request.previousEnvelope.count))
        try budget.totals.checkAvailable(availableBytes, additionalReservation: growth)
        try beforeSave()
        try fresh().requireBefore(request)
        do { try context.save() } catch { context.rollback(); throw error }
        try afterSave()
    }

    func activeAttempt() throws -> SharedMediaNativePreparationAttempt? {
        try authority.validate()
        return try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData).attempt.map { try .decode($0.bytes) }
    }

    /// Called only by the serial registered owner, after its previous operation
    /// drained. No processor/file callback is exposed by this reservation API.
    func abandon(_ request: SharedMediaNativePreparationAttempt,
                 beforeSave: () throws -> Void, afterSave: () throws -> Void) throws {
        try result(request)
        guard case .preparation(let value) = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData),
              value.intents.isEmpty, value.frozen == nil else { throw SharedMediaStorageFailure.closed }
        package.supportingContextData = try SharedMediaNativeDraftEnvelope.V2(version: 2, contexts: value.contexts,
            presentation: value.presentation, sequence: value.sequence, attempt: nil, intents: [], frozen: nil).encoded()
        package.phaseRaw = "draftOwned"
        package.revision = request.packageRevision + 2; inventory.revision = request.inventoryRevision + 2
        _ = try SharedMediaNativeAcquisitionBudget.evaluate(context: context, inventory: inventory)
        try beforeSave(); try fresh().result(request)
        do { try context.save() } catch { context.rollback(); throw error }
        try afterSave()
    }

    func abandonedResult(_ request: SharedMediaNativePreparationAttempt) throws {
        try validateIdentity(request)
        let previous = try SharedMediaNativeDraftEnvelope.decode(request.previousEnvelope)
        let expected = try SharedMediaNativeDraftEnvelope.V2(version: 2, contexts: previous.contexts, presentation: previous.presentation,
            sequence: request.sequence, attempt: nil, intents: [], frozen: nil).encoded()
        guard package.phaseRaw == "draftOwned", inventory.revision == request.inventoryRevision + 2,
              package.revision == request.packageRevision + 2, package.supportingContextData == expected else { throw SharedMediaStorageFailure.stale }
    }

    private func requireBefore(_ request: SharedMediaNativePreparationAttempt) throws {
        try validateIdentity(request)
        guard request.writerEpoch == authority.writerEpoch, inventory.revision == request.inventoryRevision,
              package.revision == request.packageRevision, package.phaseRaw == "draftOwned",
              package.supportingContextData == request.previousEnvelope else { throw SharedMediaStorageFailure.stale }
        let expected = try self.request(original: request.original.reference, recipe: request.recipe)
        guard expected.original == request.original, expected.sequence == request.sequence else { throw SharedMediaStorageFailure.stale }
    }
    private func validateIdentity(_ request: SharedMediaNativePreparationAttempt) throws {
        try authority.validate(); try request.validate()
        guard request.inventoryID == inventory.id, request.inventoryGeneration == inventory.generation,
              request.original.reference.packageID == package.id, request.original.reference.ownerID == authority.ownerID,
              request.original.reference.draftGeneration == package.draftGeneration,
              member.revision == request.membershipRevision, member.membersData == request.membershipBytes else { throw SharedMediaStorageFailure.stale }
    }
    private func reservedEnvelope(_ request: SharedMediaNativePreparationAttempt) throws -> Data {
        let previous = try SharedMediaNativeDraftEnvelope.decode(request.previousEnvelope)
        guard previous.attempt == nil, request.sequence == (try SharedMediaStoragePolicy.add(previous.sequence, 1)) else { throw SharedMediaStorageFailure.stale }
        if case .preparation(let value) = previous {
            guard value.intents.isEmpty, value.frozen == nil else { throw SharedMediaStorageFailure.closed }
        }
        return try SharedMediaNativeDraftEnvelope.V2(version: 2, contexts: previous.contexts, presentation: previous.presentation,
            sequence: request.sequence, attempt: .init(bytes: request.encoded()), intents: [], frozen: nil).encoded()
    }
    private func fresh() throws -> SharedMediaNativePreparationMutation {
        try .init(container: container, inventoryID: inventory.id, packageID: package.id, authority: authority)
    }
    private static func one<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>) throws -> T {
        var query = descriptor; query.fetchLimit = 2; let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first else { throw SharedMediaStorageFailure.conflict }; return row
    }
}

enum SharedMediaNativePreparationBoundary: Equatable, Sendable { case beforeSave, afterSave, beforeReadback, beforePairSave, afterPairSave
    case beforeFileReserve, afterFileReserve, beforeFileIdentity, afterFileIdentity
    case beforeFileCompletion, afterFileCompletion, beforeFilePublish, afterFilePublish
    case beforeFileRetire, afterFileRetire, beforeFileRelease, afterFileRelease
}
