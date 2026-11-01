import Foundation
import SwiftData

/// Current serialized accounting inputs, never a reservation or admission.
/// This is the repository's metadata representation, not SQLite file occupancy.
/// Read under the same native store fence as the clean release audit. No models
/// escape, and no generic budget, slot, mutation or cleanup route is enabled.
@MainActor
enum SharedMediaNativeReleaseMetadataSnapshot {
    struct Original: Equatable, Sendable {
        let assetID: UUID
        let physicalOriginID: UUID
        let receiptBytes: Int64
        let identityBytes: Int64
        let retiring: Bool
    }

    struct TargetOrigin: Equatable, Sendable {
        enum Location: Equatable, Sendable {
            case present(packageID: UUID)
            case released(SharedMediaAcquisitionReceipt.TerminalIdentity)
        }
        let assetID: UUID
        let acquisitionID: UUID
        let location: Location
    }

    struct Snapshot {
        let release: SharedMediaNativeReceivingReleaseLiveAudit.Witness
        let inventoryRevision: Int64
        let envelopeBytes: Int64
        let membershipBytes: Int64
        let consumerBytes: Int64
        let executionBytes: Int64
        let slotBytes: Int64
        let pairs: [SharedMediaNativePairFileState]
        /// Includes physical origins still owned by this package even after its
        /// logical reference vanished. Foreign origins are not charged here.
        let ownedOriginals: [Original]
        let targetOrigins: [TargetOrigin]
        var recoveryPresentationData: Data?

        var pairBytes: Int64 {
            get throws {
                try PhotoPreparationPolicy.add(pairs.map { Int64(try SharedMediaNativeDraftEnvelope.bytes($0).count) })
            }
        }
        var packagePayloadBytes: Int64 {
            get throws {
                try PhotoPreparationPolicy.add([envelopeBytes, membershipBytes, consumerBytes,
                    executionBytes, slotBytes, pairBytes])
            }
        }
        var originReceiptBytes: Int64 {
            get throws { try PhotoPreparationPolicy.add(ownedOriginals.map(\.receiptBytes)) }
        }
        var originIdentityBytes: Int64 {
            get throws { try PhotoPreparationPolicy.add(ownedOriginals.map(\.identityBytes)) }
        }
        /// Descriptive current payload amount. The later global evaluator must
        /// deduplicate origins and derive future liability separately. Nothing
        /// here calls Totals or substitutes projected bytes for current bytes.
        var currentSerializedBytes: Int64 {
            get throws { try PhotoPreparationPolicy.add([packagePayloadBytes, originReceiptBytes, originIdentityBytes]) }
        }
    }

    static func read(packageID: UUID, inventoryID: UUID, context: ModelContext,
                     checkpoint: () throws -> Void = {}) throws -> Snapshot {
        try checkpoint()
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        let release = try SharedMediaNativeReceivingReleaseLiveAudit.read(packageID: packageID,
            inventoryID: inventoryID, context: context)
        let inventory = try one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let revision = inventory.revision
        let package = try one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        let member = try one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        let origin = try SharedMediaNativeReleaseOrigin.read(release.progress.plan, in: context)
        guard let slot = release.slot.resultData,
              let job = origin.rows.job.metadataJSON, let event = origin.rows.event.metadataJSON else {
            throw SharedMediaStorageFailure.conflict
        }
        let cohort = try SharedMediaNativeFrozenCohort.decode(release.origin.prepared.cohort.bytes)
        var pairs: [SharedMediaNativePairFileState] = []
        for (index, target) in release.progress.targets.enumerated() {
            try Task.checkCancellation(); try checkpoint()
            if target.stage == .readyPair || target.stage == .retiringPair {
                // Generic PairPlanGraph.state validates the whole immutable
                // envelope and cannot represent partial release. The complete
                // clean audit above has already validated these exact rows.
                pairs.append(try pairState(target.pairID, intent: cohort.entries[index].intent,
                    package: package, member: member, inventory: inventory, context: context))
            }
        }
        let originals = try ownedOriginals(packageID, inventory: inventory, context: context, checkpoint: checkpoint)
        let result = Snapshot(release: release, inventoryRevision: revision,
            envelopeBytes: Int64(package.supportingContextData.count), membershipBytes: Int64(member.membersData.count),
            consumerBytes: Int64(origin.rows.consumer.cohortData.count),
            executionBytes: try PhotoPreparationPolicy.add([Int64(job.utf8.count), Int64(event.utf8.count)]),
            slotBytes: Int64(slot.count), pairs: pairs, ownedOriginals: originals,
            targetOrigins: try targetOrigins(release, inventory: inventory, context: context),
            recoveryPresentationData: origin.rows.queue.recoveryPresentationData)
        // No metadata-cap policy is adopted by this reader. Its checked sum is
        // measured evidence for the next projection, not an enforcement route.
        _ = try result.currentSerializedBytes
        _ = try SharedMediaNativeReceivingRows.recoveryPresentation(result.recoveryPresentationData, prepared: release.origin.prepared)
        try checkpoint()
        guard !context.hasChanges, inventory.revision == revision,
              SharedMediaNativeAppMetadataFacts.Package(package) == release.state.package,
              SharedMediaNativeAppMetadataFacts.Member(member) == release.state.member,
              try SharedMediaNativeReleaseOrigin.read(release.progress.plan, in: context)
                .rows.queue.recoveryPresentationData == result.recoveryPresentationData else {
            throw SharedMediaStorageFailure.stale
        }
        return result
    }

    /// Classification comes from the authoritative receipt after the full live
    /// audit. A terminal receipt deliberately has no recoverable origin package;
    /// never infer it from the logical target or invent a previous byte charge.
    private static func targetOrigins(_ release: SharedMediaNativeReceivingReleaseLiveAudit.Witness,
                                      inventory: SharedMediaInventoryRecord, context: ModelContext) throws -> [TargetOrigin] {
        try release.progress.plan.targets.enumerated().map { index, target in
            let id = target.acquisitionID
            let row = try one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id }))
            let location: TargetOrigin.Location
            switch try SharedMediaNativeAcquisitionGraph.scopedReceipt(row, inventory: inventory, context: context, format: .appV2) {
            case .completed(let request, _):
                guard request.assetID == target.original.assetID, request.assetGeneration == target.original.assetGeneration,
                      request.ownerID == target.original.ownerID else { throw SharedMediaStorageFailure.conflict }
                location = .present(packageID: request.packageID)
            case .released(let terminal):
                guard release.progress.targets[index].stage == .removed,
                      terminal.operationID == id, terminal.inventoryID == inventory.id,
                      terminal.inventoryGeneration == inventory.generation,
                      terminal.ownerID == target.original.ownerID else { throw SharedMediaStorageFailure.conflict }
                location = .released(terminal)
            default: throw SharedMediaStorageFailure.conflict
            }
            return .init(assetID: target.original.assetID, acquisitionID: id, location: location)
        }
    }

    private static func pairState(_ id: UUID, intent: SharedMediaNativePreparationBlob,
                                  package: PhotoPreparationRecord, member: SharedMediaPendingMembershipRecord,
                                  inventory: SharedMediaInventoryRecord, context: ModelContext) throws -> SharedMediaNativePairFileState {
        let pair = try one(context, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == id }))
        let values = try [pair.aiWorkID, pair.displayWorkID].map { workID in
            let row = try one(context, FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == workID }))
            let leaseID = row.leaseID
            var query = FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == leaseID }); query.fetchLimit = 2
            let leases = try context.fetch(query)
            guard leases.count <= 1 else { throw SharedMediaStorageFailure.conflict }
            return SharedMediaNativePairFileState.Work(id: row.id, writerEpoch: row.writerEpoch,
                phase: row.phaseRaw, writerState: row.writerStateRaw, device: row.partialDevice, inode: row.partialInode,
                finalIdentity: row.finalIdentity, retirementID: row.retirementID,
                retirementPartial: row.retirementPartialIdentity, retirementFinal: row.retirementFinalIdentity,
                retirementParent: row.retirementParentIdentity, retirementNamespace: row.retirementNamespaceIdentity,
                closure: leases.first?.terminalProof)
        }
        guard let first = values.first else { throw SharedMediaStorageFailure.conflict }
        return .init(plan: .init(intent: intent, writerEpoch: first.writerEpoch,
            inventoryID: inventory.id, inventoryGeneration: inventory.generation, inventoryRevision: inventory.revision,
            packageID: package.id, draftGeneration: package.draftGeneration, packageRevision: package.revision,
            envelope: package.supportingContextData, membershipRevision: member.revision, membership: member.membersData),
            phase: pair.phaseRaw, publishedRevision: pair.publishedRevision,
            allocatedBytes: package.allocatedByteCount, work: values)
    }

    /// Shared physical-origin leaf for clean received and releasing readers.
    /// Each allocation/receipt is independently validated; logical ownership is
    /// never a substitute. The caller still owes its phase and complete audit.
    static func ownedOriginals(_ packageID: UUID, inventory: SharedMediaInventoryRecord,
                                       context: ModelContext, checkpoint: () throws -> Void) throws -> [Original] {
        // Mirror the existing budget's authoritative physical-origin traversal,
        // not the current package's logical-reference list. Page materialization
        // and checkpoint on every row; never silently omit a surviving share.
        var query = FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.packageID == packageID },
            sortBy: [SortDescriptor(\.id)])
        query.fetchLimit = SharedMediaStoragePolicy.pageSize
        var offset = 0, result: [Original] = []
        var payloadBytes: Int64 = 0
        while true {
            try Task.checkCancellation(); try checkpoint(); query.fetchOffset = offset
            let rows = try context.fetch(query)
            for allocation in rows {
                try Task.checkCancellation(); try checkpoint()
                let assetID = allocation.id
                guard allocation.inventoryID == inventory.id,
                      allocation.namespaceRaw == SharedMediaPhotoLedger.namespace else {
                    throw SharedMediaStorageFailure.conflict
                }
                if try SharedMediaNativePairFileGraph.nativeWork(assetID: assetID, context: context) != nil { continue }
                let receipt = try one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == assetID }))
                guard allocation.inventoryID == inventory.id,
                      case .completed(let request, let saved) = try SharedMediaNativeAcquisitionGraph.scopedReceipt(receipt,
                        inventory: inventory, context: context, format: .appV2, checkpoint: checkpoint),
                      request.packageID == packageID, request.assetID == assetID,
                      allocation.accountID == request.ownerID, let identity = allocation.physicalIdentity else {
                    throw SharedMediaStorageFailure.conflict
                }
                let bytes = try SharedMediaAcquisitionReceipt.metadataCharge(request: request, result: saved)
                payloadBytes = try SharedMediaStoragePolicy.add(payloadBytes, bytes)
                // Same existing origin-receipt cap as AcquisitionBudget. This
                // bounds retained value materialization, not the whole library.
                guard payloadBytes <= PhotoPreparationPolicy.metadata else { throw SharedMediaStorageFailure.capacity }
                result.append(.init(assetID: assetID, physicalOriginID: packageID, receiptBytes: bytes,
                    identityBytes: Int64(identity.utf8.count),
                    retiring: allocation.stateRaw == SharedMediaNativeRetirementIdentity.allocationState))
            }
            if rows.count < SharedMediaStoragePolicy.pageSize { break }
            let (next, overflow) = offset.addingReportingOverflow(rows.count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }; offset = next
        }
        return result
    }

    private static func one<T: PersistentModel>(_ context: ModelContext, _ query: FetchDescriptor<T>) throws -> T {
        try SharedMediaNativePairPlanGraph.one(context, query)
    }
}
