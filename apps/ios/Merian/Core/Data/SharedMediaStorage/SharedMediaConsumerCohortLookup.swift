import CryptoKit
import Foundation
import SwiftData

/// Pure bounded joins, called inside a fresh fenced transaction by the owner.
/// Returned facts are not a file capability and cannot authorize physical cleanup.
@MainActor
enum SharedMediaConsumerCohortLookup {
    static func validate(_ consumer: SharedMediaConsumerRecord, context: ModelContext) throws -> SharedMediaConsumerCohort {
        let cohort = try SharedMediaConsumerCohort.decode(consumer.cohortData)
        guard consumer.lifecycleRaw == "active", consumer.retirementID == nil, consumer.revision >= 0,
              consumer.contractVersion == PhotoPreparationPolicy.contract, consumer.digestVersion == 1,
              consumer.inventoryID == cohort.inventoryID,
              consumer.inventoryGeneration == cohort.inventoryGeneration, consumer.ownerID == cohort.ownerID,
              consumer.packageID == cohort.packageID, consumer.draftGeneration == cohort.draftGeneration,
              consumer.frozenPackageRevision == cohort.packageRevision else { throw SharedMediaStorageFailure.conflict }
        let execution = try SharedMediaConsumerExecution.classify(raw: consumer.executionKindRaw, generation: consumer.inferenceGeneration)
        guard ["queue", "localScan", "analysis"].contains(consumer.kindRaw),
              [consumer.consumerID, consumer.originQueueID, consumer.observationID].allSatisfy({
                  !$0.isEmpty && $0.utf8.count <= SharedMediaStoragePolicy.maximumTokenBytes
              }) else { throw SharedMediaStorageFailure.conflict }
        if consumer.kindRaw == "localScan", case .reanalysis = execution { throw SharedMediaStorageFailure.conflict }
        let inventoryID = cohort.inventoryID, packageID = cohort.packageID
        let inventory = try one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let receipt = try one(context, FetchDescriptor<SharedMediaMembershipBootstrapRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let package = try one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        guard consumer.cohortSHA256 == (try cohort.digest(context: package.supportingContextData)),
              inventory.generation == cohort.inventoryGeneration, inventory.phaseRaw == "readyP1",
              receipt.inventoryGeneration == inventory.generation, receipt.contractVersion == 1, receipt.revision >= 0,
              package.ownerID == cohort.ownerID, package.draftID == packageID,
              package.draftGeneration == cohort.draftGeneration, package.revision == cohort.packageRevision,
              package.contractVersion == consumer.contractVersion, package.phaseRaw == "preparedHeld",
              !package.retirementRequested,
              package.accountingTierRaw == (consumer.kindRaw == "queue" ? "pending" : "retained"),
              SHA256.hash(data: package.supportingContextData).map({ String(format: "%02x", $0) }).joined() == cohort.contextSHA256 else {
            throw SharedMediaStorageFailure.conflict
        }
        var membershipQuery = FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID })
        membershipQuery.fetchLimit = 2
        let memberships = try context.fetch(membershipQuery)
        if package.accountingTierRaw == "pending" {
            guard memberships.count == 1, let member = memberships.first,
                  member.inventoryID == inventoryID, member.inventoryGeneration == inventory.generation,
                  member.ownerID == package.ownerID, member.draftGeneration == package.draftGeneration,
                  member.revision >= 0 else { throw SharedMediaStorageFailure.conflict }
            let assertion = try SharedMediaMembership.decode(member.membersData)
            guard Set(assertion.ids(.reference)) == Set(cohort.entries.map(\.referenceID)),
                  Set(assertion.ids(.asset)) == Set(cohort.entries.map(\.assetID)),
                  Set(assertion.ids(.pair)) == Set(cohort.entries.map(\.pairID)),
                  Set(assertion.ids(.derivative)) == Set(cohort.entries.compactMap(\.workID)),
                  Set(assertion.ids(.allocation)) == Set(cohort.entries.map(\.assetID)),
                  Set(assertion.ids(.edge)) == Set(cohort.entries.map(\.referenceID)),
                  assertion.ids(.work).isEmpty, assertion.ids(.handoff).isEmpty, assertion.ids(.source).isEmpty else { throw SharedMediaStorageFailure.conflict }
        } else {
            guard memberships.isEmpty else { throw SharedMediaStorageFailure.conflict }
        }
        try SharedMediaMembership.requireMetadataBudget(context: package.supportingContextData,
            membership: memberships.first?.membersData ?? Data(), cohort: consumer.cohortData)
        guard try PhotoPreparationPolicy.add(cohort.entries.map(\.byteCount)) == package.allocatedByteCount,
              try PhotoPreparationPolicy.add([package.allocatedByteCount, Int64(package.supportingContextData.count),
                Int64(consumer.cohortData.count), Int64(memberships.first?.membersData.count ?? 0)]) <= PhotoPreparationPolicy.package else {
            throw SharedMediaStorageFailure.capacity
        }
        var edgesQuery = FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.packageID == packageID })
        edgesQuery.fetchLimit = 7
        let edges = try context.fetch(edgesQuery)
        guard edges.count == cohort.entries.count, Set(edges.map(\.id)) == Set(cohort.entries.map(\.referenceID)) else {
            throw SharedMediaStorageFailure.conflict
        }
        let leaseIDs = try cohort.entries.map { try validate($0, cohort: cohort, context: context) }
        guard Set(leaseIDs).count == leaseIDs.count else { throw SharedMediaStorageFailure.conflict }
        if let membership = memberships.first {
            guard Set(try SharedMediaMembership.decode(membership.membersData).ids(.lease)) == Set(leaseIDs) else {
                throw SharedMediaStorageFailure.conflict
            }
        }
        return cohort
    }

    private static func validate(_ entry: SharedMediaConsumerCohort.Entry,
                                 cohort: SharedMediaConsumerCohort, context: ModelContext) throws -> UUID {
        let assetID = entry.assetID, referenceID = entry.referenceID, pairID = entry.pairID
        let asset = try one(context, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID }))
        let reference = try one(context, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == referenceID }))
        let allocation = try one(context, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == assetID }))
        let edge = try one(context, FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == referenceID }))
        let count = try one(context, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID }))
        let lease = try one(context, FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.allocationID == assetID }))
        let pair = try one(context, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == pairID }))
        guard asset.ownerID == cohort.ownerID, asset.generation == entry.assetGeneration,
              asset.byteCount == entry.byteCount, asset.sha256 == entry.sha256,
              asset.contentType == entry.contentType, asset.cleanupStateRaw == "ready",
              reference.packageID == cohort.packageID, reference.ownerID == cohort.ownerID,
              reference.assetID == assetID, reference.roleRaw == entry.role,
              reference.ordinal == entry.ordinal, reference.revision == entry.referenceRevision, reference.isLive,
              edge.allocationID == assetID, edge.accountID == cohort.ownerID,
              edge.ownerID == referenceID.uuidString.lowercased(), edge.roleRaw == SharedMediaPhotoLedger.namespace,
              edge.stateRaw == "live", edge.revision == reference.revision,
              allocation.inventoryID == cohort.inventoryID, allocation.accountID == cohort.ownerID,
              allocation.namespaceRaw == SharedMediaPhotoLedger.namespace, allocation.poolRaw == "durable",
              allocation.materializedBytes == entry.byteCount, allocation.reservedBytes == 0,
              allocation.physicalIdentity == entry.physicalIdentity, allocation.fileToken == asset.fileToken,
              allocation.stateRaw == (entry.role == "original" ? "p1Materialized" : "p1DerivativeMaterialized"),
              count.inventoryID == cohort.inventoryID, count.inventoryGeneration == cohort.inventoryGeneration,
              count.assetGeneration == entry.assetGeneration, count.ownerID == cohort.ownerID,
              count.liveCount > 0, count.revision >= 0, count.retirementID == nil,
              lease.stateRaw == "closed", lease.purposeRaw == (entry.role == "original" ? "p1AcquireV1" : "p1DerivativeV1"),
              pair.inventoryID == cohort.inventoryID, pair.inventoryGeneration == cohort.inventoryGeneration,
              pair.ownerID == cohort.ownerID, pair.packageID == cohort.packageID,
              pair.draftGeneration == cohort.draftGeneration, pair.ordinal == entry.ordinal,
              pair.phaseRaw == "ready", pair.contractVersion == "sharedDerivativeV1",
              let originPackage = allocation.packageID,
              asset.fileToken == cohort.ownerID.uuidString.lowercased() + "/" + originPackage.uuidString.lowercased() + "/" + assetID.uuidString.lowercased() else {
            throw SharedMediaStorageFailure.conflict
        }
        let original = cohort.entries[Int(entry.ordinal)]
        guard pair.originalReferenceID == original.referenceID, pair.originalReferenceRevision == original.referenceRevision,
              pair.originalAssetID == original.assetID, pair.originalAssetGeneration == original.assetGeneration,
              let publishedRevision = pair.publishedRevision, publishedRevision >= 0,
              publishedRevision < cohort.packageRevision else { throw SharedMediaStorageFailure.conflict }
        if let workID = entry.workID {
            let work = try one(context, FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == workID }))
            guard work.pairID == pairID, work.roleRaw == entry.role, work.assetID == assetID,
                  work.assetGeneration == entry.assetGeneration, work.referenceID == referenceID,
                  work.leaseID == lease.id, work.writerEpoch == lease.processEpoch,
                  work.phaseRaw == "completed", work.writerStateRaw == "closed", work.retirementID == nil,
                  work.finalIdentity == entry.physicalIdentity, work.byteCount == entry.byteCount,
                  work.sha256 == entry.sha256, work.contentType == entry.contentType,
                  workID == (entry.role == "aiInput" ? pair.aiWorkID : pair.displayWorkID) else {
                throw SharedMediaStorageFailure.conflict
            }
        }
        return lease.id
    }

    private static func one<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>) throws -> T {
        var query = descriptor; query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first else { throw SharedMediaStorageFailure.conflict }
        return row
    }
}
