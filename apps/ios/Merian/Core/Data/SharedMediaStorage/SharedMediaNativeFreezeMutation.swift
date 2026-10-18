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
        guard package.phaseRaw == "draftOwned", package.accountingTierRaw == "pending", !package.retirementRequested,
              case .preparation(let envelope) = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData),
              envelope.frozen == nil, envelope.attempt == nil, (1...2).contains(pairIDs.count), Set(pairIDs).count == pairIDs.count,
              pairIDs.count == envelope.intents.count,
              Set(pairIDs) == (try Set(envelope.intents.map { try SharedMediaNativeDerivativeIntent.decode($0.bytes).pairID })),
              try context.fetchCount(FetchDescriptor<PhotoPreparationLease>()) == 0 else { throw SharedMediaStorageFailure.closed }
        let states = try pairIDs.map { try SharedMediaNativePairFileGraph.state(context: context, inventory: inventory,
            package: package, member: member, pairID: $0) }
        let id = package.id
        var query = FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.packageID == id && $0.roleRaw == "original" }); query.fetchLimit = 3
        let refs = try context.fetch(query)
        guard refs.count == states.count, refs.allSatisfy(\.isLive),
              Set(refs.map(\.id)) == (try Set(states.map { try $0.intent().preparation.original.reference.referenceID })),
              states.allSatisfy({ $0.phase == "ready" }) else { throw SharedMediaStorageFailure.conflict }
        return states
    }

    func request(operationID: UUID, pairIDs: [UUID], proofs: [SharedMediaPhotoRetirementInspection]) throws -> SharedMediaNativeFreezeRequest {
        let states = try states(pairIDs: pairIDs)
        guard proofs.count == states.count * 3 else { throw SharedMediaStorageFailure.conflict }
        var entries: [SharedMediaNativeFrozenEntry] = []
        for (position, state) in states.enumerated() {
            let intent = try state.intent(), original = intent.preparation.original
            let files = [original.file, try state.file(intent.ai.id), try state.file(intent.display.id)]
            let observations = Array(proofs[(position * 3)..<(position * 3 + 3)])
            for (file, observed) in zip(files, observations) {
                guard observed.file == file, observed.binding == authority.binding.bytes,
                      observed.epoch == authority.binding.epoch else { throw SharedMediaStorageFailure.conflict }
            }
            guard observations[0].identity == original.descriptor,
                  observations[1].identity.file == state.work.first(where: { $0.id == intent.ai.id })?.finalIdentity,
                  observations[2].identity.file == state.work.first(where: { $0.id == intent.display.id })?.finalIdentity else {
                throw SharedMediaStorageFailure.conflict
            }
            let aiID = intent.ai.referenceID, displayID = intent.display.referenceID
            let ai = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == aiID }))
            let display = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == displayID }))
            entries.append(.init(position: position, intent: state.plan.intent, aiReferenceRevision: ai.revision,
                displayReferenceRevision: display.revision, aiDescriptor: observations[1].identity, displayDescriptor: observations[2].identity))
        }
        let envelope = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData)
        let cohort = SharedMediaNativeFrozenCohort(format: .cohort, packageID: package.id, ownerID: package.ownerID,
            draftGeneration: package.draftGeneration, supportingBytes: try SharedMediaNativeFrozenSupporting(
                contexts: envelope.contexts, presentation: envelope.presentation).encoded(), entries: entries)
        let commit = SharedMediaNativeFreezeCommit(format: .receipt, operationID: operationID, inventoryID: inventory.id,
            inventoryGeneration: inventory.generation, beforeInventoryRevision: inventory.revision,
            beforePackageRevision: package.revision, membershipRevision: member.revision,
            previousEnvelopeSHA256: SharedMediaAcquisitionEncoding.digest(package.supportingContextData),
            membershipSHA256: SharedMediaAcquisitionEncoding.digest(member.membersData), cohort: .init(bytes: try cohort.encoded()))
        let request = SharedMediaNativeFreezeRequest(commit: commit, previousEnvelope: package.supportingContextData, membership: member.membersData)
        try request.validate(); return request
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
