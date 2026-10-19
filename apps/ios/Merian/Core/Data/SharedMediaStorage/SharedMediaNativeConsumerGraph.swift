import Foundation
import SwiftData

/// Scoped, read-only frozen facts. The caller holds the session fence and uses
/// a clean private context. Queue/result joins, physical verification and account
/// authority remain separate requirements; this is not an execution capability.
@MainActor
enum SharedMediaNativeConsumerGraph {
    static let contract = "nativeReceivingV1"

    static func validate(_ consumer: SharedMediaConsumerRecord, context: ModelContext) throws -> SharedMediaNativeConsumerCohort {
        try facts(consumer, context: context, format: nil)
    }

    static func validateScoped(_ consumer: SharedMediaConsumerRecord, context: ModelContext, format: SharedMediaNativeScopedFormat = .existingV1, checkpoint: () throws -> Void = {}) throws -> SharedMediaNativeConsumerCohort {
        try facts(consumer, context: context, format: format, checkpoint: checkpoint)
    }

    private static func facts(_ consumer: SharedMediaConsumerRecord, context: ModelContext,
                              format: SharedMediaNativeScopedFormat?, checkpoint: () throws -> Void = {}) throws -> SharedMediaNativeConsumerCohort {
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        let value = try SharedMediaNativeConsumerCohort.decode(consumer.cohortData)
        let commit = try SharedMediaNativeFreezeCommit.decode(value.freeze.bytes)
        let cohort = try SharedMediaNativeFrozenCohort.decode(commit.cohort.bytes)
        guard consumer.id == value.bindingID, consumer.cursorKey == value.bindingID.uuidString.lowercased(),
              consumer.originQueueID == value.originQueueID, consumer.observationID == value.observationID,
              consumer.executionKindRaw == value.executionKind, consumer.inferenceGeneration == value.inferenceGeneration,
              consumer.contractVersion == contract, consumer.digestVersion == 1,
              consumer.cohortSHA256 == (try value.digest()), consumer.lifecycleRaw == "active",
              consumer.retirementID == nil, consumer.revision >= 0,
              consumer.inventoryID == commit.inventoryID, consumer.inventoryGeneration == commit.inventoryGeneration,
              consumer.ownerID == cohort.ownerID, consumer.packageID == cohort.packageID,
              consumer.draftGeneration == cohort.draftGeneration,
              consumer.frozenPackageRevision == (try commit.packageRevision),
              ["queue", "localScan", "analysis"].contains(consumer.kindRaw),
              UUID(uuidString: consumer.consumerID)?.uuidString.lowercased() == consumer.consumerID,
              consumer.kindRaw != "queue" || consumer.consumerID == value.originQueueID,
              consumer.kindRaw != "localScan" || (consumer.consumerID == value.observationID && value.executionKind == "ordinaryV1"),
              try SharedMediaConsumerLookup.one(context, packageID: cohort.packageID)?.id == consumer.id else {
            throw SharedMediaStorageFailure.conflict
        }
        let inventoryID = commit.inventoryID, id = cohort.packageID
        let inventory = try one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let bootstrap = try one(context, FetchDescriptor<SharedMediaMembershipBootstrapRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let package = try one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id }))
        if let format { try format.requireProfile(inventory) }
        guard inventory.generation == commit.inventoryGeneration,
              inventory.phaseRaw == (format?.phase ?? "readyNativeAccountingV1"),
              bootstrap.inventoryGeneration == inventory.generation, bootstrap.contractVersion == (format?.membershipVersion ?? 1), bootstrap.revision >= 0,
              package.draftID == id, package.contractVersion == PhotoPreparationPolicy.contract,
              package.ownerID == cohort.ownerID, package.draftGeneration == cohort.draftGeneration,
              package.accountingTierRaw == (consumer.kindRaw == "queue" ? "pending" : "retained"),
              case .preparation(let envelope) = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData),
              envelope.frozen == value.freeze else { throw SharedMediaStorageFailure.conflict }
        let liveMembership: Data
        if consumer.kindRaw == "queue" {
            let member = try one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
            guard member.membersData == value.membership, member.revision == commit.membershipRevision else {
                throw SharedMediaStorageFailure.conflict
            }
            try SharedMediaNativeFreezeGraph.validate(envelope, package: package, inventory: inventory, context: context)
            liveMembership = member.membersData
        } else {
            try SharedMediaNativeFreezeGraph.validateRetained(envelope, membership: value.membership,
                membershipRevision: commit.membershipRevision, package: package, inventory: inventory, context: context)
            liveMembership = Data()
        }
        try validateMembership(value.membership, cohort: cohort, package: package, inventory: inventory, context: context, checkpoint: checkpoint)
        try SharedMediaMembership.requireMetadataBudget(context: package.supportingContextData,
            membership: liveMembership, cohort: consumer.cohortData)
        guard try PhotoPreparationPolicy.add([package.allocatedByteCount, Int64(package.supportingContextData.count),
            Int64(liveMembership.count), Int64(consumer.cohortData.count)]) <= PhotoPreparationPolicy.package,
              !context.hasChanges else { throw SharedMediaStorageFailure.capacity }
        return value
    }

    private static func validateMembership(_ bytes: Data, cohort: SharedMediaNativeFrozenCohort,
                                           package: PhotoPreparationRecord, inventory: SharedMediaInventoryRecord,
                                           context: ModelContext, checkpoint: () throws -> Void) throws {
        let member = try SharedMediaMembership.decode(bytes), id = package.id
        let intents = try cohort.entries.map { try SharedMediaNativeDerivativeIntent.decode($0.intent.bytes) }
        let originals = intents.map { $0.preparation.original }
        let outputs = intents.flatMap { [$0.ai, $0.display] }
        let refs = originals.map { $0.reference.referenceID } + outputs.map(\.referenceID)
        let assets = originals.map { $0.reference.assetID } + outputs.map(\.assetID)
        guard Set(refs).count == refs.count, Set(outputs.map(\.assetID)).count == outputs.count,
              Set(outputs.map(\.assetID)).isDisjoint(with: originals.map { $0.reference.assetID }),
              Set(member.ids(.reference)) == Set(refs), Set(member.ids(.edge)) == Set(refs),
              Set(member.ids(.asset)) == Set(assets), Set(member.ids(.allocation)) == Set(assets),
              Set(member.ids(.pair)) == Set(intents.map(\.pairID)),
              Set(member.ids(.derivative)) == Set(outputs.map(\.id)),
              member.ids(.work).isEmpty, member.ids(.source).isEmpty, member.ids(.handoff).isEmpty,
              try context.fetchCount(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.packageID == id })) == refs.count,
              try context.fetchCount(FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.packageID == id })) == intents.count,
              try context.fetchCount(FetchDescriptor<SharedMediaInboxHandoffRecord>(predicate: #Predicate { $0.packageID == id })) == 0 else {
            throw SharedMediaStorageFailure.conflict
        }
        var leases = Set<UUID>()
        // Historical IDs never replace the current complete reverse-reference audit.
        for original in originals {
            let current = try SharedMediaNativeOriginalAccounting.audit(assetID: original.reference.assetID,
                inventoryID: inventory.id, context: context, checkpoint: checkpoint)
            guard current.assetGeneration == original.reference.assetGeneration, current.ownerID == package.ownerID,
                  current.liveCount > 0, current.retirement == nil, current.physicalIdentity == original.descriptor.file,
                  current.byteCount == original.byteCount, current.sha256 == original.sha256,
                  current.contentType == original.contentType, current.fileToken == original.token else {
                throw SharedMediaStorageFailure.conflict
            }
            leases.insert(current.leaseID)
        }
        let logicalBytes = try PhotoPreparationPolicy.add(originals.map(\.byteCount) + outputs.map(\.byteCount))
        guard Set(member.ids(.lease)) == leases, package.allocatedByteCount == logicalBytes else {
            throw SharedMediaStorageFailure.conflict
        }
        guard try PhotoPreparationPolicy.add(originals.map(\.byteCount)) <= PhotoPreparationPolicy.originalCohort,
              try PhotoPreparationPolicy.add(intents.map { $0.ai.byteCount }) <= PhotoPreparationPolicy.aiCohort,
              try PhotoPreparationPolicy.add(intents.map { $0.display.byteCount }) <= PhotoPreparationPolicy.displayCohort else {
            throw SharedMediaStorageFailure.capacity
        }
    }

    private static func one<T: PersistentModel>(_ context: ModelContext, _ query: FetchDescriptor<T>) throws -> T {
        try SharedMediaNativePairPlanGraph.one(context, query)
    }
}
