import Foundation
import SwiftData

/// Pure ready-cohort facts shared by fenced qualification and app callers.
/// This owns no save, dispatch, queue, or physical-media authority.
@MainActor
enum SharedMediaNativeFreezeFacts {
    static func states(context: ModelContext, inventory: SharedMediaInventoryRecord, package: PhotoPreparationRecord,
                       member: SharedMediaPendingMembershipRecord, pairIDs: [UUID]) throws -> [SharedMediaNativePairFileState] {
        let packageID = package.id
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        guard package.phaseRaw == "draftOwned", package.accountingTierRaw == "pending", !package.retirementRequested,
              case .preparation(let envelope) = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData),
              envelope.frozen == nil, envelope.attempt == nil, (1...2).contains(pairIDs.count), Set(pairIDs).count == pairIDs.count,
              pairIDs.count == envelope.intents.count,
              Set(pairIDs) == (try Set(envelope.intents.map { try SharedMediaNativeDerivativeIntent.decode($0.bytes).pairID })),
              try context.fetchCount(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.packageID == packageID })) == 0 else { throw SharedMediaStorageFailure.closed }
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

    static func request(context: ModelContext, inventory: SharedMediaInventoryRecord, package: PhotoPreparationRecord,
                        member: SharedMediaPendingMembershipRecord, binding: SharedMediaNativeBinding,
                        operationID: UUID, pairIDs: [UUID], proofs: [SharedMediaPhotoRetirementInspection]) throws -> SharedMediaNativeFreezeRequest {
        let states = try states(context: context, inventory: inventory, package: package, member: member, pairIDs: pairIDs)
        guard proofs.count == states.count * 3 else { throw SharedMediaStorageFailure.conflict }
        var entries: [SharedMediaNativeFrozenEntry] = []
        for (position, state) in states.enumerated() {
            let intent = try state.intent(), original = intent.preparation.original
            let files = [original.file, try state.file(intent.ai.id), try state.file(intent.display.id)]
            let observations = Array(proofs[(position * 3)..<(position * 3 + 3)])
            for (file, observed) in zip(files, observations) {
                guard observed.file == file, observed.binding == binding.bytes,
                      observed.epoch == binding.epoch else { throw SharedMediaStorageFailure.conflict }
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

}
