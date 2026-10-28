import Foundation
import SwiftData

/// Release-stage namespace checks, under the caller's pinned store/account
/// authority. These read-only checks grant no save or recovery permission.
@MainActor
enum SharedMediaNativeReleaseStageIdentity {
    typealias Values = SharedMediaNativeReceivingReleaseValues

    static func audit(_ id: UUID, container: ModelContainer, check: () throws -> Void) async throws {
        var offset = 0
        while true {
            try Task.checkCancellation(); try check()
            let count: Int = try {
                let context = ModelContext(container); context.autosaveEnabled = false
                var query = FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(sortBy: [SortDescriptor(\.id)])
                query.fetchOffset = offset; query.fetchLimit = SharedMediaStoragePolicy.pageSize
                let rows = try context.fetch(query)
                for row in rows { try requireAbsent(id, receipt: SharedMediaAcquisitionReceipt.read(row)) }
                return rows.count
            }()
            try check()
            if count < SharedMediaStoragePolicy.pageSize { break }
            let (next, overflow) = offset.addingReportingOverflow(count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }
            offset = next; await Task.yield()
        }
    }

    static func requireAbsent(_ id: UUID, receipt: SharedMediaAcquisitionReceipt) throws {
        let identities: [UUID]
        switch receipt {
        case .reserved(let r), .held(let r): identities = [r.operationID, r.assetID, r.referenceID]
        case .completed(let r, let result): identities = [r.operationID, r.assetID, r.referenceID, result.leaseID]
        case .released(let r): identities = [r.operationID]
        }
        guard !identities.contains(id) else { throw SharedMediaStorageFailure.conflict }
    }

    /// Pending witnesses come from the complete clean graph after the raw-slot
    /// audit. In particular, do not substitute its smaller dispatch-ID list for
    /// retained target and retirement identities whose physical rows are gone.
    static func requireAbsent(_ id: UUID, witnesses: [SharedMediaNativeReceivingCleanGraph.Witness]) throws {
        for witness in witnesses {
            guard !witness.identities.contains(id) else { throw SharedMediaStorageFailure.conflict }
            switch witness {
            case .allocating(let value): try requireAbsent(id, prepared: value.prepared)
            case .generic(let value):
                switch value.slot {
                case .prepared(let p), .received(let p, _, _):
                    try requireAbsent(id, prepared: p)
                case .abandoned: break
                }
            case .staged(let value): try requireAbsent(id, progress: value.components.progress)
            case .releasing(let value): try requireAbsent(id, progress: value.release.progress)
            }
        }
    }

    private static func requireAbsent(_ id: UUID, prepared p: SharedMediaNativeReceivingIntent.Prepared) throws {
                    let cohort = try SharedMediaNativeFrozenCohort.decode(p.cohort.bytes)
                    for entry in cohort.entries {
                        let intent = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes)
                        let original = intent.preparation.original.reference
                        let ids = [intent.pairID, original.assetID, original.referenceID]
                            + [intent.ai, intent.display].flatMap { [$0.id, $0.assetID, $0.referenceID, $0.leaseID] }
                        guard !ids.contains(id) else { throw SharedMediaStorageFailure.conflict }
                    }
    }

    static func requireAbsent(_ id: UUID, progress: Values.Progress) throws {
        try progress.validate()
        let p = progress.plan
        let identities = [p.package.id, p.releaseID, p.operationID, p.queueID, p.observationID, p.bindingID, p.generation, p.eventID]
            + p.targets.flatMap(\.identities)
            + progress.targets.flatMap { [$0.pair?.retirementID, $0.original?.retirementID].compactMap { $0 } }
        guard !identities.contains(id) else { throw SharedMediaStorageFailure.conflict }
    }

    /// Fresh logical IDs only. Existing physical originals/acquisition leases
    /// are deliberately omitted by sharing callers, never relabelled as fresh.
    /// A terminal receiving row remains rejected by the complete clean reader.
    static func requireFresh(_ ids: [UUID], inventoryID: UUID, context: ModelContext) throws {
        guard !context.hasChanges, Set(ids).count == ids.count else { throw SharedMediaStorageFailure.conflict }
        let inventory = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let witnesses = Array(try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory).values)
        try SharedMediaNativeTerminalScan.requireAbsent(ids, container: context.container, inventoryID: inventoryID)
        for id in ids {
            try requireAbsent(id, witnesses: witnesses)
            try direct(id, context: context)
        }
    }

    /// Indexed probes repeat immediately before save. Arbitrary metadata JSON,
    /// fence generations and process epochs are not part of this namespace.
    static func direct(_ id: UUID, context c: ModelContext) throws {
        guard !c.hasChanges else { throw SharedMediaStorageFailure.conflict }
        try empty(c, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id }))
        try empty(c, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
        try empty(c, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id || $0.assetID == id }))
        try empty(c, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == id }))
        try empty(c, FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == id || $0.allocationID == id }))
        try empty(c, FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == id || $0.allocationID == id }))
        try empty(c, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == id || $0.retirementID == id }))
        try empty(c, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == id }))
        try empty(c, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == id || $0.assetID == id }))
        try empty(c, FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == id || $0.assetID == id }))
        try empty(c, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate {
            $0.id == id || $0.originalReferenceID == id || $0.originalAssetID == id || $0.aiWorkID == id || $0.displayWorkID == id || $0.previousPairID == id
        }))
        try empty(c, FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate {
            $0.id == id || $0.pairID == id || $0.assetID == id || $0.referenceID == id || $0.leaseID == id || $0.retirementID == id
        }))
        try empty(c, FetchDescriptor<SharedMediaInboxSourceRecord>(predicate: #Predicate { $0.id == id || $0.workID == id }))
        try empty(c, FetchDescriptor<SharedMediaInboxHandoffRecord>(predicate: #Predicate {
            $0.id == id || $0.sourceID == id || $0.assetID == id || $0.referenceID == id || $0.leaseID == id || $0.sourceHoldID == id
        }))
        try empty(c, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id || $0.operationID == id }))
        let aliases = [id.uuidString.lowercased(), id.uuidString.uppercased()]
        let jobs = aliases.map { "scan-ingestion:" + $0 }
        try empty(c, FetchDescriptor<SharedMediaConsumerRecord>(predicate: #Predicate {
            $0.id == id || $0.packageID == id || $0.retirementID == id || $0.inferenceGeneration == id
        }))
        try empty(c, FetchDescriptor<SharedMediaConsumerRecord>(predicate: #Predicate {
            aliases.contains($0.consumerID) || aliases.contains($0.originQueueID) || aliases.contains($0.observationID)
        }))
        try empty(c, FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { aliases.contains($0.id) || $0.sharedMediaConsumerID == id }))
        try empty(c, FetchDescriptor<OfflineJobRecord>(predicate: #Predicate {
            jobs.contains($0.id) || ($0.subjectId != nil && aliases.contains($0.subjectId!))
        }))
        try empty(c, FetchDescriptor<OfflineQueueEvent>(predicate: #Predicate {
            aliases.contains($0.id) || ($0.scanId != nil && aliases.contains($0.scanId!)) || ($0.jobId != nil && jobs.contains($0.jobId!))
        }))
        try empty(c, FetchDescriptor<LocalScanRecord>(predicate: #Predicate { aliases.contains($0.id) || $0.sharedMediaConsumerID == id }))
        try empty(c, FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate {
            aliases.contains($0.id) || aliases.contains($0.observationID) || $0.sharedMediaConsumerID == id
        }))
    }

    private static func empty<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>) throws {
        var query = descriptor; query.fetchLimit = 1; query.includePendingChanges = true
        guard try context.fetch(query).isEmpty else { throw SharedMediaStorageFailure.conflict }
    }
}
