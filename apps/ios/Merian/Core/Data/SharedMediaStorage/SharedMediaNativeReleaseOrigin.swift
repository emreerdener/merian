import Foundation
import SwiftData

/// Nonrecursive, read-only origin check for the future sealed release owner.
/// This proves the exact historical submission and untouched execution quartet,
/// not current media ownership, physical absence, admission or mutation authority.
/// Runtime release dispatch remains closed until its full state audit is wired.
@MainActor
enum SharedMediaNativeReleaseOrigin {
    typealias Intent = SharedMediaNativeReceivingIntent
    typealias Plan = SharedMediaNativeReceivingReleaseValues.Plan

    struct Snapshot {
        let prepared: Intent.Prepared
        let received: Intent.Received
        let transaction: Intent.Transaction
    }
    struct Witness {
        let snapshot: Snapshot
        let rows: SharedMediaNativeReceivingRows.Set
    }

    static func reconstruct(_ plan: Plan, frozenEnvelope: Data,
                            consumer: SharedMediaNativeConsumerCohort, timestamp: Date) throws -> Snapshot {
        try plan.validate(); try consumer.validate()
        guard consumer.format == .intentReceiving, let origin = consumer.intentBinding,
              origin.preparedRevision == plan.preparedRevision,
              origin.preparedSHA256 == plan.preparedSHA256,
              SharedMediaAcquisitionEncoding.digest(frozenEnvelope) == plan.package.envelopeSHA256,
              case .preparation(let envelope) = try SharedMediaNativeDraftEnvelope.decode(frozenEnvelope),
              envelope.attempt == nil, envelope.frozen == consumer.freeze else {
            throw SharedMediaStorageFailure.conflict
        }
        let commit = try SharedMediaNativeFreezeCommit.decode(consumer.freeze.bytes)
        guard commit.membershipRevision == plan.member.revision,
              commit.cohort.sha256 == plan.cohortSHA256 else { throw SharedMediaStorageFailure.conflict }
        let previous = try SharedMediaNativeDraftEnvelope.V2(version: 2, contexts: envelope.contexts,
            presentation: envelope.presentation, sequence: envelope.sequence, attempt: nil,
            intents: envelope.intents, frozen: nil).encoded()
        let package = try SharedMediaNativeAppMetadataFacts.Package(releaseOrigin: plan.package,
            previousEnvelope: previous, commit: commit)
        let member = try SharedMediaNativeAppMetadataFacts.Member(releaseOrigin: plan.member, bytes: consumer.membership)
        let prepared = try Intent.Prepared(profile: plan.profile, package: package, member: member,
            cohort: commit.cohort, operationID: plan.operationID, queueID: plan.queueID,
            observationID: plan.observationID, bindingID: plan.bindingID, generation: plan.generation,
            eventID: plan.eventID, timestamp: timestamp, intentRevision: origin.preparedRevision,
            restagedFromSHA256: origin.restagedFromSHA256)
        // Recover the saved receipt header, not today's revision or wall clock.
        let header = SharedMediaNativeAppEligibility.Header(inventory: .init(generation: plan.profile.generation,
            revision: commit.beforeInventoryRevision, phase: SharedMediaNativeAppProfile.phase, cursor: ""),
            bootstrapID: plan.preHeader.bootstrapID, bootstrapGeneration: plan.preHeader.bootstrapGeneration,
            bootstrapContract: plan.preHeader.bootstrapContract, bootstrapRevision: plan.preHeader.bootstrapRevision)
        let transaction = try prepared.descriptorForTransaction(header: header)
        let received = try Intent.Received(prepared: prepared, request: transaction)
        guard transaction.cohort == consumer else { throw SharedMediaStorageFailure.conflict }
        // Acquisition IDs here bind the historical target assertion only. The
        // release owner separately audits their current ledger/proof ownership.
        try plan.requireMatch(prepared: prepared, received: received, acquisitionIDs: plan.targets.map(\.acquisitionID))
        return .init(prepared: prepared, received: received, transaction: transaction)
    }

    static func read(_ plan: Plan, in context: ModelContext) throws -> Witness {
        try plan.validate()
        let packageID = plan.package.id, queueID = plan.queueID.uuidString.lowercased()
        let package = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        guard let consumer = try SharedMediaConsumerLookup.one(context, id: plan.bindingID) else {
            throw SharedMediaStorageFailure.conflict
        }
        let queue = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == queueID }))
        let snapshot = try reconstruct(plan, frozenEnvelope: package.supportingContextData,
            consumer: SharedMediaNativeConsumerCohort.decode(consumer.cohortData), timestamp: queue.timestamp)
        // This checks aliases, reverse joins and every held execution scalar.
        // It deliberately does not require today's package/member to equal the
        // immutable pre-cleanup snapshot. The release state audit owns that join.
        guard let rows = try SharedMediaNativeReceivingRows.read(snapshot.transaction, in: context, absent: false) else {
            throw SharedMediaStorageFailure.conflict
        }
        return .init(snapshot: snapshot, rows: rows)
    }
}
