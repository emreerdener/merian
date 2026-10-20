import Foundation
import SwiftData

/// One fenced save owns the terminal native freeze. All queried rows and the
/// save context remain private; physical proofs come only from locked files.
@MainActor
final class SharedMediaNativeFreezeMutation {
    private let container: ModelContainer
    private let authority: SharedMediaNativeMutationAuthority
    private let context: ModelContext
    private let inventory: SharedMediaInventoryRecord
    private let package: PhotoPreparationRecord
    private let member: SharedMediaPendingMembershipRecord

    init(container: ModelContainer, inventoryID: UUID, packageID: UUID, authority: SharedMediaNativeMutationAuthority) throws {
        try authority.validate()
        self.container = container; self.authority = authority
        context = ModelContext(container); context.autosaveEnabled = false
        inventory = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        package = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        member = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        guard !authority.binding.initializing, package.ownerID == authority.ownerID,
              member.ownerID == authority.ownerID, member.inventoryID == inventory.id,
              member.inventoryGeneration == inventory.generation, member.draftGeneration == package.draftGeneration,
              authority.binding.bytes == (try JSONEncoder().encode(["nativeQualificationV1", inventory.id.uuidString, inventory.storeIdentity, inventory.rootIdentity])) else {
            throw SharedMediaStorageFailure.closed
        }
        try SharedMediaNativeAcquisitionGraph.audit(context: context, inventoryID: inventoryID)
    }

    func states(pairIDs: [UUID]) throws -> [SharedMediaNativePairFileState] {
        try authority.validate(); try SharedMediaNativePreparationGraph.requireNoUnfinished(context)
        guard try context.fetchCount(FetchDescriptor<PhotoPreparationLease>()) == 0 else { throw SharedMediaStorageFailure.closed }
        return try SharedMediaNativeFreezeFacts.states(context: context, inventory: inventory, package: package, member: member, pairIDs: pairIDs)
    }

    func request(operationID: UUID, pairIDs: [UUID], proofs: [SharedMediaPhotoRetirementInspection]) throws -> SharedMediaNativeFreezeRequest {
        _ = try states(pairIDs: pairIDs)
        return try SharedMediaNativeFreezeFacts.request(context: context, inventory: inventory, package: package, member: member,
            binding: authority.binding, operationID: operationID, pairIDs: pairIDs, proofs: proofs)
    }

    func result(_ request: SharedMediaNativeFreezeRequest) throws -> SharedMediaNativeFreezeCommit? {
        try request.validate(); try authority.validate()
        guard case .preparation(let value) = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData) else { throw SharedMediaStorageFailure.closed }
        guard let frozen = value.frozen else { return nil }
        let commit = try SharedMediaNativeFreezeCommit.decode(frozen.bytes)
        guard commit == request.commit else { throw SharedMediaStorageFailure.conflict }
        return commit
    }

    func apply(_ request: SharedMediaNativeFreezeRequest, proofs: [SharedMediaPhotoRetirementInspection], availableBytes: Int64,
               verifyProofs: ([SharedMediaPhotoRetirementInspection]) throws -> Void, beforeSave: () throws -> Void, afterSave: () throws -> Void) throws -> SharedMediaNativeFreezeCommit {
        if let saved = try result(request) { return saved }
        let cohort = try SharedMediaNativeFrozenCohort.decode(request.commit.cohort.bytes)
        let ids = try cohort.entries.map { try SharedMediaNativeDerivativeIntent.decode($0.intent.bytes).pairID }
        guard try self.request(operationID: request.commit.operationID, pairIDs: ids, proofs: proofs) == request,
              case .preparation(let value) = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData) else { throw SharedMediaStorageFailure.stale }
        package.supportingContextData = try SharedMediaNativeDraftEnvelope.V2(version: 2, contexts: value.contexts,
            presentation: value.presentation, sequence: value.sequence, attempt: nil, intents: value.intents,
            frozen: .init(bytes: try request.commit.encoded())).encoded()
        package.phaseRaw = "preparedHeld"; package.revision = try request.commit.packageRevision
        inventory.revision = try request.commit.inventoryRevision
        let graph = try SharedMediaPendingGraph.derive(in: context, inventory: inventory)
        try graph.validateMembership(in: context, inventory: inventory)
        let budget = try SharedMediaNativeAcquisitionBudget.evaluate(context: context, inventory: inventory)
        try budget.totals.checkAvailable(availableBytes, additionalReservation: max(0, Int64(package.supportingContextData.count - request.previousEnvelope.count)))
        try beforeSave(); try authority.validate()
        guard try fresh().request(operationID: request.commit.operationID, pairIDs: ids, proofs: proofs) == request else { throw SharedMediaStorageFailure.stale }
        try verifyProofs(proofs)
        do { try context.save(); try afterSave() }
        catch {
            let failure = error; context.rollback()
            guard (try? fresh().result(request)) == request.commit else { throw failure }
        }
        guard let saved = try fresh().result(request) else { throw SharedMediaStorageFailure.conflict }; return saved
    }
    private func fresh() throws -> SharedMediaNativeFreezeMutation {
        try .init(container: container, inventoryID: inventory.id, packageID: package.id, authority: authority)
    }
}
