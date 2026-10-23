import Foundation
import SwiftData

/// Clean received-state measurement only. No reserve, admission, filesystem,
/// release-start or save authority. A future writer must re-read under its fence
/// and prove the complete two-row replacement and aggregate revision runway.
@MainActor
enum SharedMediaNativeReceivedReleaseSnapshot {
    typealias Intent = SharedMediaNativeReceivingIntent
    typealias Values = SharedMediaNativeReceivingReleaseValues
    typealias Projection = SharedMediaNativeReleaseSurvivorProjection
    typealias Metadata = SharedMediaNativeReleaseMetadataSnapshot
    typealias Liability = SharedMediaNativeAcquisitionBudget.MetadataLiability

    struct Funding {
        let before: Liability
        let after: Liability
        let projection: Projection.Projection

        init(before: Liability, projection: Projection.Projection) throws {
            _ = try before.charged
            guard projection.maximumIdentityExcludedBytes >= projection.currentIdentityExcludedBytes else {
                throw SharedMediaStorageFailure.conflict
            }
            self.before = before; self.projection = projection
            after = .init(current: projection.currentIdentityExcludedBytes,
                reserved: projection.maximumIdentityExcludedBytes - projection.currentIdentityExcludedBytes)
        }
        /// Compare total funded liability. Current shrink may fund a larger
        /// future reserve; neither component is individually monotone. This says
        /// nothing about immediate SQLite/WAL reclamation or available disk.
        func requireExistingFunding() throws {
            try projection.requireMetadataCapacity()
            guard try after.charged <= before.charged else { throw SharedMediaStorageFailure.capacity }
        }
    }

    struct Snapshot {
        let slot: SharedMediaNativeReceivingIntentGraph.Row
        let header: SharedMediaNativeAppEligibility.Header
        let components: Projection.Components
        let funding: Funding
    }

    static func read(packageID: UUID, inventoryID: UUID, releaseID: UUID,
                     context: ModelContext, checkpoint: () throws -> Void = {}) throws -> Snapshot {
        try checkpoint()
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        let inventory = try one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let profile = try SharedMediaNativeAppEligibility.profile(inventory)
        let scope = SharedMediaNativeScopeIdentity(inventoryID: profile.inventoryID, generation: profile.generation,
            ownerID: profile.ownerID, storeIdentity: profile.storeIdentity, rootBinding: try profile.rootIdentity)
        let header = try SharedMediaNativeAppEligibility.snapshot(context: context, scope: scope)
        guard let record = try SharedMediaNativeReceivingPhaseGraph.row(packageID, in: context) else {
            throw SharedMediaStorageFailure.conflict
        }
        let slot = SharedMediaNativeReceivingIntentGraph.Row(record)
        guard case .received(let prepared, let received, let transaction) = try SharedMediaNativeReceivingSlot.decode(slot, profile: profile),
              prepared.version == 2 else { throw SharedMediaStorageFailure.closed }
        let rows = try SharedMediaNativeReceivingPhaseGraph.receivedRows(transaction, context: context)
        let consumer = try SharedMediaNativeConsumerGraph.validateScoped(rows.consumer, context: context,
            format: .appV2, checkpoint: checkpoint)
        guard consumer == transaction.cohort else { throw SharedMediaStorageFailure.conflict }
        let components = try assemble(slot: slot, prepared: prepared, received: received, rows: rows,
            header: header, inventory: inventory, releaseID: releaseID, context: context, checkpoint: checkpoint)
        let budget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: context, inventory: inventory,
            ownerID: profile.ownerID, format: .appV2, checkpoint: checkpoint)
        guard let before = budget.receivedLiabilityByPackage[packageID],
              try before.charged == budget.metadataByPackage[packageID] else { throw SharedMediaStorageFailure.conflict }
        let funding = try Funding(before: before, projection: Projection.maximum(components))
        try checkpoint()
        guard !context.hasChanges, SharedMediaNativeReceivingIntentGraph.Row(record) == slot,
              header == (try SharedMediaNativeAppEligibility.snapshot(context: context, scope: scope)) else {
            throw SharedMediaStorageFailure.stale
        }
        try requireFrozenRows(components, context: context)
        return .init(slot: slot, header: header, components: components, funding: funding)
    }

    /// Reclassifies existing received headroom. These values do not authorize
    /// global budget inclusion, revision allocation, staging or release-start.
    struct StagedFunding {
        let historical: Liability
        let staged: Liability
        let release: Funding

        init(historical: Liability, sidecarBytes: Int64, projection: Projection.Projection) throws {
            let total = try historical.charged
            guard sidecarBytes >= 0 else { throw SharedMediaStorageFailure.conflict }
            let current = try PhotoPreparationPolicy.add([historical.current, sidecarBytes])
            guard current <= total, total <= PhotoPreparationPolicy.metadata else {
                throw SharedMediaStorageFailure.capacity
            }
            self.historical = historical
            staged = .init(current: current, reserved: total - current)
            release = try Funding(before: historical, projection: projection)
            try release.requireExistingFunding()
        }
    }

    struct StagedSnapshot {
        let origin: SharedMediaNativeStagedReleaseOrigin
        let components: Projection.Components
        let historical: SharedMediaNativeAcquisitionBudget.HistoricalReceived
        let funding: StagedFunding
    }

    static func readStaged(_ origin: SharedMediaNativeStagedReleaseOrigin,
                           context: ModelContext, projectionMemo: Projection.Memo? = nil, checkpoint: () throws -> Void = {}) throws -> StagedSnapshot {
        try checkpoint(); try origin.requireCurrent(context: context)
        let inventoryID = origin.prepared.profile.inventoryID
        let inventory = try one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let rows = try SharedMediaNativeReceivingPhaseGraph.receivedRows(origin.transaction, context: context)
        _ = try SharedMediaNativeConsumerGraph.validateStagedReceived(rows.consumer, origin: origin,
            context: context, checkpoint: checkpoint)
        let components = try assemble(slot: origin.row, prepared: origin.prepared, received: origin.received,
            rows: rows, header: origin.header, inventory: inventory, releaseID: origin.request.releaseID,
            context: context, checkpoint: checkpoint)
        let historical = try SharedMediaNativeAcquisitionBudget.historicalReceived(origin,
            context: context, checkpoint: checkpoint)
        let sidecar = try origin.request.encoding()
        let funding = try StagedFunding(historical: historical.liability,
            sidecarBytes: sidecar.metadataBytes,
            projection: Projection.maximum(components, memo: projectionMemo))
        try checkpoint(); try origin.requireCurrent(context: context)
        try requireFrozenRows(components, context: context)
        return .init(origin: origin, components: components, historical: historical, funding: funding)
    }

    /// Only the two validated origin adapters above call this leaf. It neither
    /// dispatches receiving/clean state nor invokes the global budget. Future
    /// release sizing uses today's header, never the unverified staging floor.
    private static func assemble(slot: SharedMediaNativeReceivingIntentGraph.Row,
                                 prepared: Intent.Prepared, received: Intent.Received,
                                 rows: SharedMediaNativeReceivingRows.Set,
                                 header: SharedMediaNativeAppEligibility.Header,
                                 inventory: SharedMediaInventoryRecord, releaseID: UUID,
                                 context: ModelContext, checkpoint: () throws -> Void) throws -> Projection.Components {
        let packageID = slot.id
        let package = try one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        let member = try one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        let postStartRevision = try SharedMediaStoragePolicy.add(inventory.revision, 1)
        let cohort = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes)
        var pairs: [SharedMediaNativePairFileState] = [], origins: [Metadata.TargetOrigin] = []
        for entry in cohort.entries {
            try Task.checkCancellation(); try checkpoint()
            // Consumer/FreezeGraph above validates the exact frozen ready cohort,
            // descriptors and reference revisions. This reconstructs those same
            // rows; editable Prepared.currentCohort cannot read a frozen package.
            let intent = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes)
            let pair = try SharedMediaNativePairFileGraph.state(context: context, inventory: inventory,
                package: package, member: member, pairID: intent.pairID)
            guard pair.phase == "ready", pair.plan.intent == entry.intent,
                  pair.allocatedBytes == package.allocatedByteCount else { throw SharedMediaStorageFailure.conflict }
            // The rows are unchanged. The reconstructed value includes today's
            // inventory revision, so predict the post-start view explicitly.
            // This matters at decimal-width boundaries (e.g. 99 -> 100).
            let p = pair.plan
            let postPlan = SharedMediaNativePairPlan(intent: p.intent, writerEpoch: p.writerEpoch,
                inventoryID: p.inventoryID, inventoryGeneration: p.inventoryGeneration, inventoryRevision: postStartRevision,
                packageID: p.packageID, draftGeneration: p.draftGeneration, packageRevision: p.packageRevision,
                envelope: p.envelope, membershipRevision: p.membershipRevision, membership: p.membership)
            pairs.append(.init(plan: postPlan, phase: pair.phase, publishedRevision: pair.publishedRevision,
                allocatedBytes: pair.allocatedBytes, work: pair.work))
            let reference = intent.preparation.original.reference, assetID = reference.assetID
            let receipt = try one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == assetID }))
            guard case .completed(let request, _) = try SharedMediaNativeAcquisitionGraph.scopedReceipt(receipt,
                inventory: inventory, context: context, format: .appV2, checkpoint: checkpoint),
                  request.assetID == assetID, request.assetGeneration == reference.assetGeneration,
                  request.ownerID == reference.ownerID else { throw SharedMediaStorageFailure.conflict }
            origins.append(.init(assetID: assetID, acquisitionID: request.operationID, location: .present(packageID: request.packageID)))
        }
        let plan = try Values.Plan(prepared: prepared, received: received, header: header,
            releaseID: releaseID, acquisitionIDs: origins.map(\.acquisitionID))
        let progress = try Values.Progress(plan: plan)
        // One proposed start increment, then this release's remaining steps.
        // This is not the later aggregate check across every active release.
        try progress.requireRevisionCapacity(inventoryRevision: postStartRevision)
        let expected = try SharedMediaNativeReceivingReleaseState.expected(progress, prepared: prepared, received: received)
        guard expected.completedSteps == 0, slot.revision == (try plan.receivedRevision),
              expected.package == SharedMediaNativeAppMetadataFacts.Package(package),
              expected.member == SharedMediaNativeAppMetadataFacts.Member(member),
              let job = rows.job.metadataJSON, let event = rows.event.metadataJSON else {
            throw SharedMediaStorageFailure.conflict
        }
        let components = Projection.Components(progress: progress, prepared: prepared, received: received,
            package: expected.package, member: expected.member,
            envelopeBytes: Int64(package.supportingContextData.count), membershipBytes: Int64(member.membersData.count),
            consumerBytes: Int64(rows.consumer.cohortData.count),
            executionBytes: try PhotoPreparationPolicy.add([Int64(job.utf8.count), Int64(event.utf8.count)]),
            slotBytes: Int64(try progress.encoded().count), pairs: pairs,
            ownedOriginals: try Metadata.ownedOriginals(packageID, inventory: inventory, context: context, checkpoint: checkpoint),
            targetOrigins: origins)
        guard !context.hasChanges,
              expected.package == SharedMediaNativeAppMetadataFacts.Package(package),
              expected.member == SharedMediaNativeAppMetadataFacts.Member(member) else {
            throw SharedMediaStorageFailure.stale
        }
        return components
    }

    private static func requireFrozenRows(_ components: Projection.Components, context: ModelContext) throws {
        let id = components.package.id
        let package = try one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id }))
        let member = try one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
        guard !context.hasChanges, components.package == SharedMediaNativeAppMetadataFacts.Package(package),
              components.member == SharedMediaNativeAppMetadataFacts.Member(member) else {
            throw SharedMediaStorageFailure.stale
        }
    }

    private static func one<T: PersistentModel>(_ context: ModelContext, _ query: FetchDescriptor<T>) throws -> T {
        try SharedMediaNativePairPlanGraph.one(context, query)
    }
}
