import Foundation
import SwiftData

/// Terminal native freeze joins. This does not admit a consumer, queue row,
/// provider invocation or legacy reader, and does not assert file availability.
@MainActor
enum SharedMediaNativeFreezeGraph {
    static func validate(_ envelope: SharedMediaNativeDraftEnvelope.V2, package: PhotoPreparationRecord,
                         inventory: SharedMediaInventoryRecord, context: ModelContext) throws {
        guard let blob = envelope.frozen, envelope.attempt == nil, package.phaseRaw == "preparedHeld",
              package.accountingTierRaw == "pending", !package.retirementRequested else { throw SharedMediaStorageFailure.closed }
        let commit = try SharedMediaNativeFreezeCommit.decode(blob.bytes)
        let cohort = try SharedMediaNativeFrozenCohort.decode(commit.cohort.bytes), id = package.id
        let member = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
        let previous = try SharedMediaNativeDraftEnvelope.V2(version: 2, contexts: envelope.contexts,
            presentation: envelope.presentation, sequence: envelope.sequence, attempt: nil, intents: envelope.intents, frozen: nil).encoded()
        guard commit.inventoryID == inventory.id, commit.inventoryGeneration == inventory.generation,
              inventory.revision >= (try commit.inventoryRevision), package.revision == (try commit.packageRevision),
              commit.membershipRevision == member.revision,
              commit.membershipSHA256 == SharedMediaAcquisitionEncoding.digest(member.membersData),
              commit.previousEnvelopeSHA256 == SharedMediaAcquisitionEncoding.digest(previous),
              cohort.packageID == package.id, cohort.ownerID == package.ownerID, cohort.draftGeneration == package.draftGeneration,
              cohort.supportingBytes == (try SharedMediaNativeFrozenSupporting(contexts: envelope.contexts, presentation: envelope.presentation).encoded()),
              cohort.entries.count == envelope.intents.count,
              Set(cohort.entries.map { $0.intent.sha256 }) == Set(envelope.intents.map(\.sha256)),
              try context.fetchCount(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.packageID == id })) == 0 else {
            throw SharedMediaStorageFailure.conflict
        }
        var originals = Set<UUID>()
        for entry in cohort.entries {
            guard envelope.intents.contains(entry.intent) else { throw SharedMediaStorageFailure.conflict }
            let intent = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes)
            guard originals.insert(intent.preparation.original.reference.referenceID).inserted else { throw SharedMediaStorageFailure.conflict }
            // Narrow ready validation avoids recursing into this frozen graph.
            try SharedMediaNativePairPlanGraph.validateReadyForMembership(envelope, pairID: intent.pairID,
                package: package, inventory: inventory, context: context)
            for (input, revision, identity) in [(intent.ai, entry.aiReferenceRevision, entry.aiDescriptor),
                                               (intent.display, entry.displayReferenceRevision, entry.displayDescriptor)] {
                let refID = input.referenceID, workID = input.id
                let ref = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == refID }))
                let work = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == workID }))
                guard ref.revision == revision, work.finalIdentity == identity.file else { throw SharedMediaStorageFailure.conflict }
            }
        }
        var query = FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.packageID == id && $0.roleRaw == "original" }); query.fetchLimit = 3
        let refs = try context.fetch(query)
        guard (1...2).contains(refs.count), Set(refs.map(\.id)) == originals, refs.allSatisfy(\.isLive) else { throw SharedMediaStorageFailure.conflict }
    }
}
