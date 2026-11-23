import Foundation
import SwiftData

/// Exact current photo-selection joins shared by receiving and ordinary hold
/// preparation. A value comparison grants no persistence, file or dispatch right.
@MainActor
enum SharedMediaNativeReadyPhotoCohort {
    static func read(_ submission: SharedMediaNativePreparationBlob, package: PhotoPreparationRecord,
                     member: SharedMediaPendingMembershipRecord, inventory: SharedMediaInventoryRecord,
                     context: ModelContext) throws -> [SharedMediaNativePairFileState] {
        try submission.validate()
        let frozen = try SharedMediaNativeFrozenCohort.decode(submission.bytes), id = package.id
        guard case .preparation(let envelope) = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData),
              frozen.packageID == id, frozen.ownerID == package.ownerID, frozen.draftGeneration == package.draftGeneration,
              member.id == id, member.inventoryID == inventory.id, member.inventoryGeneration == inventory.generation,
              member.ownerID == package.ownerID, member.draftGeneration == package.draftGeneration,
              frozen.supportingBytes == (try SharedMediaNativeFrozenSupporting(
                contexts: envelope.contexts, presentation: envelope.presentation).encoded()),
              frozen.entries.count == envelope.intents.count,
              frozen.entries.allSatisfy({ envelope.intents.contains($0.intent) }),
              try context.fetchCount(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.packageID == id })) == 0 else {
            throw SharedMediaStorageFailure.conflict
        }
        var originals = Set<UUID>(), states: [SharedMediaNativePairFileState] = []
        // Preserve explicit submitted positions; membership sorting cannot set media order.
        for entry in frozen.entries {
            let intent = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes)
            guard originals.insert(intent.preparation.original.reference.referenceID).inserted else {
                throw SharedMediaStorageFailure.conflict
            }
            try SharedMediaNativePairPlanGraph.validateReadyForMembership(envelope, pairID: intent.pairID,
                package: package, inventory: inventory, context: context)
            let state = try SharedMediaNativePairFileGraph.state(context: context, inventory: inventory,
                package: package, member: member, pairID: intent.pairID)
            guard state.phase == "ready", state.plan.intent == entry.intent else { throw SharedMediaStorageFailure.conflict }
            for (input, revision, identity) in [(intent.ai, entry.aiReferenceRevision, entry.aiDescriptor),
                                               (intent.display, entry.displayReferenceRevision, entry.displayDescriptor)] {
                let refID = input.referenceID
                let ref = try SharedMediaNativePairPlanGraph.one(context,
                    FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == refID }))
                let work = try state.selected(input.id).0
                guard ref.revision == revision, work.phase == "completed", work.writerState == "closed",
                      work.finalIdentity == identity.file else { throw SharedMediaStorageFailure.conflict }
            }
            states.append(state)
        }
        var query = FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.packageID == id && $0.roleRaw == "original" })
        query.fetchLimit = 3; query.includePendingChanges = true
        let refs = try context.fetch(query)
        guard refs.count == states.count, Set(refs.map(\.id)) == originals, refs.allSatisfy(\.isLive) else {
            throw SharedMediaStorageFailure.conflict
        }
        return states
    }
}
