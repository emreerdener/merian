import Foundation
import SwiftData

/// Indexed collision proof for a fully audited staged snapshot. Selected rows
/// are allowed only after readStaged has proved their exact role mappings.
/// Additional references/pairs may name a shared physical original, but cannot
/// reuse any selected logical identity. No mutation or authority is granted.
@MainActor
// The full domain name distinguishes this state or capability from adjacent storage boundaries.
// swiftlint:disable:next type_name
enum SharedMediaNativeReleaseStartDirectIdentity {
    static func check(_ snapshot: SharedMediaNativeReceivedReleaseSnapshot.StagedSnapshot, context c: ModelContext) throws {
        guard !c.hasChanges else { throw SharedMediaStorageFailure.conflict }
        try snapshot.origin.requireCurrent(context: c)
        let plan = snapshot.components.progress.plan, targets = plan.targets
        let identities = SharedMediaNativeReleaseStartIdentity.ids(plan)
        let originals = Set(targets.map { $0.original.assetID })
        let outputs = targets.flatMap { [$0.ai, $0.display] }
        let assets = originals.union(outputs.map(\.assetID))
        let receipts = Set(targets.map(\.acquisitionID))
        let outputLeases = Set(outputs.map(\.leaseID)), leases = receipts.union(outputLeases)
        let references = Set(targets.map { $0.original.referenceID }).union(outputs.map(\.referenceID))
        let pairs = Set(targets.map(\.pairID)), works = Set(outputs.map(\.workID))
        let held = try SharedMediaNativeReceivingPhaseGraph.receivedRows(snapshot.origin.transaction, context: c)
        guard let slot = try SharedMediaNativeReceivingPhaseGraph.row(plan.package.id, in: c) else {
            throw SharedMediaStorageFailure.stale
        }
        for id in identities {
            try allowed(c, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id || $0.assetID == id }, sortBy: [SortDescriptor(\.id)])) { receipts.contains($0.id) }
            try allowed(c, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == id }, sortBy: [SortDescriptor(\.id)])) { assets.contains($0.id) }
            try allowed(c, FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == id || $0.allocationID == id }, sortBy: [SortDescriptor(\.id)])) { leases.contains($0.id) }
            try allowed(c, FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == id || $0.allocationID == id }, sortBy: [SortDescriptor(\.id)])) { references.contains($0.id) || (originals.contains($0.allocationID) && !identities.contains($0.id)) }
            try allowed(c, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == id }, sortBy: [SortDescriptor(\.id)])) { assets.contains($0.id) }
            try allowed(c, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == id }, sortBy: [SortDescriptor(\.id)])) { assets.contains($0.id) }
            try allowed(c, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == id || $0.assetID == id }, sortBy: [SortDescriptor(\.id)])) { references.contains($0.id) || (originals.contains($0.assetID) && !identities.contains($0.id)) }
            try allowed(c, FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == id || $0.assetID == id }, sortBy: [SortDescriptor(\.id)])) { outputLeases.contains($0.id) }
            try allowed(c, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate {
                $0.id == id || $0.originalReferenceID == id || $0.originalAssetID == id || $0.aiWorkID == id || $0.displayWorkID == id || $0.previousPairID == id
            }, sortBy: [SortDescriptor(\.id)])) { pairs.contains($0.id) || sharedPair($0, originals: originals, identities: identities) }
            try allowed(c, FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate {
                $0.id == id || $0.pairID == id || $0.assetID == id || $0.referenceID == id || $0.leaseID == id
            }, sortBy: [SortDescriptor(\.id)])) { works.contains($0.id) }
            try allowed(c, FetchDescriptor<SharedMediaInboxSourceRecord>(predicate: #Predicate { $0.id == id || $0.workID == id }, sortBy: [SortDescriptor(\.id)])) { _ in false }
            try allowed(c, FetchDescriptor<SharedMediaInboxHandoffRecord>(predicate: #Predicate {
                $0.id == id || $0.sourceID == id || $0.assetID == id || $0.referenceID == id || $0.leaseID == id || $0.sourceHoldID == id
            }, sortBy: [SortDescriptor(\.id)])) { _ in false }
            try allowed(c, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id || $0.operationID == id }, sortBy: [SortDescriptor(\.id)])) { $0.persistentModelID == slot.persistentModelID }
            let lower = id.uuidString.lowercased(), upper = id.uuidString.uppercased()
            let lowerJob = "scan-ingestion:" + lower, upperJob = "scan-ingestion:" + upper
            let aliases = [lower, upper]
            let jobs = aliases.map { "scan-ingestion:" + $0 }
            try allowed(c, FetchDescriptor<SharedMediaConsumerRecord>(predicate: #Predicate {
                $0.id == id || $0.packageID == id || $0.retirementID == id || $0.inferenceGeneration == id
            }, sortBy: [SortDescriptor(\.id)])) { $0.persistentModelID == held.consumer.persistentModelID }
            try allowed(c, FetchDescriptor<SharedMediaConsumerRecord>(predicate: #Predicate {
                aliases.contains($0.consumerID) || aliases.contains($0.originQueueID) || aliases.contains($0.observationID)
            }, sortBy: [SortDescriptor(\.id)])) { $0.persistentModelID == held.consumer.persistentModelID }
            try allowed(c, FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { aliases.contains($0.id) || $0.sharedMediaConsumerID == id }, sortBy: [SortDescriptor(\.id)])) { $0.persistentModelID == held.queue.persistentModelID }
            try allowed(c, FetchDescriptor<OfflineJobRecord>(predicate: #Predicate {
                jobs.contains($0.id) || $0.subjectId == lower || $0.subjectId == upper
            }, sortBy: [SortDescriptor(\.id)])) { $0.persistentModelID == held.job.persistentModelID }
            try allowed(c, FetchDescriptor<OfflineQueueEvent>(predicate: #Predicate {
                aliases.contains($0.id) || $0.scanId == lower || $0.scanId == upper || $0.jobId == lowerJob || $0.jobId == upperJob
            }, sortBy: [SortDescriptor(\.id)])) { $0.persistentModelID == held.event.persistentModelID }
            try allowed(c, FetchDescriptor<LocalScanRecord>(predicate: #Predicate { aliases.contains($0.id) || $0.sharedMediaConsumerID == id }, sortBy: [SortDescriptor(\.id)])) { _ in false }
            try allowed(c, FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate {
                aliases.contains($0.id) || aliases.contains($0.observationID) || $0.sharedMediaConsumerID == id
            }, sortBy: [SortDescriptor(\.id)])) { _ in false }
        }
    }

    private static func sharedPair(_ row: SharedMediaDerivativePairRecord,
                                   originals: Set<UUID>, identities: Set<UUID>) -> Bool {
        let logical = [row.id, row.originalReferenceID, row.aiWorkID, row.displayWorkID]
        return originals.contains(row.originalAssetID) && identities.isDisjoint(with: logical) &&
            (row.previousPairID == nil || !identities.contains(row.previousPairID!))
    }

    /// Page matching references; never retain an unbounded shared-file fanout.
    private static func allowed<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>,
                                                    validate: (T) -> Bool) throws {
        var query = descriptor
        query.fetchLimit = SharedMediaStoragePolicy.pageSize; query.includePendingChanges = true
        var offset = 0
        while true {
            try Task.checkCancellation()
            query.fetchOffset = offset
            let rows = try context.fetch(query)
            guard rows.allSatisfy(validate) else { throw SharedMediaStorageFailure.conflict }
            if rows.count < SharedMediaStoragePolicy.pageSize { return }
            let (next, overflow) = offset.addingReportingOverflow(rows.count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }
            offset = next
        }
    }
}
