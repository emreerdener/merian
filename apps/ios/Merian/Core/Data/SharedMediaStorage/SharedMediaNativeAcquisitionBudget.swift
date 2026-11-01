import Foundation
import SwiftData

/// Pending-only accounting derived from the current graph. No mutation or
/// admission authority. Call after the complete graph audit (or typed post-state
/// validation) while retaining the same store fence. Retained bytes remain disk
/// occupancy and are never assigned a pending-package or retained-library cap.
@MainActor
enum SharedMediaNativeAcquisitionBudget {
    /// Existing received metadata accounting split, excluding physical media and
    /// globally owned original identities. This is descriptive, not a reservation.
    struct MetadataLiability: Equatable, Sendable {
        let current: Int64
        let reserved: Int64
        var charged: Int64 { get throws { try PhotoPreparationPolicy.add([current, reserved]) } }
    }

    struct Snapshot {
        let totals: SharedMediaStoragePolicy.Totals
        /// Asset-owned identity bytes and headroom included once in global totals.
        let originalIdentity: SharedMediaNativeOriginalLiability.Snapshot?
        let metadataByPackage: [UUID: Int64]
        let baseMetadataByPackage: [UUID: Int64]
        let receivedLiabilityByPackage: [UUID: MetadataLiability]
    }

    static func evaluate(context: ModelContext, inventory: SharedMediaInventoryRecord) throws -> Snapshot {
        let graph = try SharedMediaPendingGraph.derive(in: context, inventory: inventory)
        return try evaluate(context: context, inventory: inventory, graph: graph, format: nil)
    }

    static func evaluateScoped(context: ModelContext, inventory: SharedMediaInventoryRecord, ownerID: UUID, format: SharedMediaNativeScopedFormat = .existingV1, projectionMemo: SharedMediaNativeReleaseSurvivorProjection.Memo? = nil, checkpoint: () throws -> Void = {}) throws -> Snapshot {
        let graph = try SharedMediaPendingGraph.deriveScoped(in: context, inventory: inventory, ownerID: ownerID, format: format)
        let clean = format == .appV2 ? try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory, projectionMemo: projectionMemo, checkpoint: checkpoint) : nil
        return try evaluate(context: context, inventory: inventory, graph: graph, format: format, clean: clean, checkpoint: checkpoint)
    }

    static func evaluateMetadataPoststate(context: ModelContext, inventory: SharedMediaInventoryRecord,
                                          proof: SharedMediaNativeAppMetadataPoststate) throws -> Snapshot {
        let graph = try SharedMediaPendingGraph.deriveMetadataPoststate(in: context, inventory: inventory, proof: proof)
        return try evaluate(context: context, inventory: inventory, graph: graph, format: .appV2, allocationPeers: proof.allocationPeers, metadataProof: proof)
    }

    static func evaluateAcquisitionPoststate(context: ModelContext, inventory: SharedMediaInventoryRecord,
                                             proof: SharedMediaNativeAppAcquisitionPoststate) throws -> Snapshot {
        let graph = try SharedMediaPendingGraph.deriveAcquisitionPoststate(in: context, inventory: inventory, proof: proof)
        return try evaluate(context: context, inventory: inventory, graph: graph, format: .appV2, allocationPeers: proof.allocationPeers, acquisitionProof: proof)
    }

    static func evaluatePreparationPoststate(context: ModelContext, inventory: SharedMediaInventoryRecord,
                                             proof: SharedMediaNativeAppPreparationPoststate) throws -> Snapshot {
        let graph = try SharedMediaPendingGraph.derivePreparationPoststate(in: context, inventory: inventory, proof: proof)
        return try evaluate(context: context, inventory: inventory, graph: graph, format: .appV2, allocationPeers: proof.allocationPeers, preparationProof: proof)
    }

    static func evaluatePairPlanPoststate(context: ModelContext, inventory: SharedMediaInventoryRecord,
                                          proof: SharedMediaNativeAppPairPlanPoststate) throws -> Snapshot {
        let graph = try SharedMediaPendingGraph.derivePairPlanPoststate(in: context, inventory: inventory, proof: proof)
        return try evaluate(context: context, inventory: inventory, graph: graph, format: .appV2, allocationPeers: proof.allocationPeers, pairPlanProof: proof)
    }

    static func evaluatePairClosurePoststate(context: ModelContext, inventory: SharedMediaInventoryRecord,
                                             proof: SharedMediaNativeAppPairPlanClosurePoststate) throws -> Snapshot {
        let graph = try SharedMediaPendingGraph.derivePairClosurePoststate(in: context, inventory: inventory, proof: proof)
        return try evaluate(context: context, inventory: inventory, graph: graph, format: .appV2, allocationPeers: proof.allocationPeers, pairClosureProof: proof)
    }

    static func evaluatePairFilePoststate(context: ModelContext, inventory: SharedMediaInventoryRecord,
                                         proof: SharedMediaNativeAppPairPoststate) throws -> Snapshot {
        let graph = try SharedMediaPendingGraph.derivePairFilePoststate(in: context, inventory: inventory, proof: proof)
        return try evaluate(context: context, inventory: inventory, graph: graph, format: .appV2, allocationPeers: proof.allocationPeers, pairFileProof: proof)
    }

    static func evaluatePairRetirementPoststate(context: ModelContext, inventory: SharedMediaInventoryRecord,
                                               proof: SharedMediaNativeAppPairRetirementPoststate) throws -> Snapshot {
        let graph = try SharedMediaPendingGraph.derivePairRetirementPoststate(in: context, inventory: inventory, proof: proof)
        return try evaluate(context: context, inventory: inventory, graph: graph, format: .appV2, allocationPeers: proof.allocationPeers, pairRetirementProof: proof)
    }

    static func evaluateIntentPoststate(context: ModelContext, inventory: SharedMediaInventoryRecord,
                                       proof: SharedMediaNativeAppIntentPoststate) throws -> Snapshot {
        let graph = try SharedMediaPendingGraph.deriveIntentPoststate(in: context, inventory: inventory, proof: proof)
        return try evaluate(context: context, inventory: inventory, graph: graph, format: .appV2, allocationPeers: proof.allocationPeers, intentProof: proof)
    }

    static func evaluateStagingPoststate(context: ModelContext, inventory: SharedMediaInventoryRecord,
                                         proof: SharedMediaNativeAppStagingPoststate) throws -> Snapshot {
        let graph = try SharedMediaPendingGraph.deriveStagingPoststate(in: context, inventory: inventory, proof: proof)
        return try evaluate(context: context, inventory: inventory, graph: graph, format: .appV2, allocationPeers: proof.allocationPeers, stagingProof: proof)
    }

    static func evaluatePendingCleanupPoststate(context: ModelContext, inventory: SharedMediaInventoryRecord,
                                                proof: SharedMediaNativeAppPendingPoststate) throws -> Snapshot {
        let graph = try SharedMediaPendingGraph.derivePendingCleanupPoststate(in: context, inventory: inventory, proof: proof)
        return try evaluate(context: context, inventory: inventory, graph: graph, format: .appV2, allocationPeers: proof.allocationPeers, pendingCleanupProof: proof)
    }

    static func evaluateOriginalPoststate(context: ModelContext, inventory: SharedMediaInventoryRecord,
                                         proof: SharedMediaNativeAppOriginalPoststate) throws -> Snapshot {
        let graph = try SharedMediaPendingGraph.deriveOriginalPoststate(in: context, inventory: inventory, proof: proof)
        return try evaluate(context: context, inventory: inventory, graph: graph, format: .appV2, allocationPeers: proof.allocationPeers, originalProof: proof)
    }

    static func evaluateOriginalReleasePoststate(context: ModelContext, inventory: SharedMediaInventoryRecord,
                                         proof: SharedMediaNativeAppOriginalReleasePoststate) throws -> Snapshot {
        let graph = try SharedMediaPendingGraph.deriveOriginalReleasePoststate(in: context, inventory: inventory, proof: proof)
        return try evaluate(context: context, inventory: inventory, graph: graph, format: .appV2, allocationPeers: proof.allocationPeers, originalReleaseProof: proof)
    }

    /// Complete successor accounting over the clean predecessor. A terminal
    /// seal proves this exact projection is the entire dirty mutation; readback
    /// repeats ordinary clean accounting and compares the full result vector.
    static func terminalProjection(context: ModelContext, inventory: SharedMediaInventoryRecord,
                                   before: SharedMediaNativeReleaseMetadataSnapshot.Snapshot,
                                   after: SharedMediaNativeReceivingReleaseValues.Released) throws -> Snapshot {
        guard after == (try .init(progress: before.release.progress,
            inventoryRevision: SharedMediaStoragePolicy.add(inventory.revision, 1))) else { throw SharedMediaStorageFailure.conflict }
        let graph = try SharedMediaPendingGraph.terminalProjection(in: context, inventory: inventory, before: before)
        var clean = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory)
        guard clean.removeValue(forKey: after.plan.package.id) != nil else { throw SharedMediaStorageFailure.conflict }
        let old = try SharedMediaNativeOriginalLiability.read(context: context, inventoryID: inventory.id)
        var selected = Set(graph.allocations.map(\.id)), retained = Set<UUID>()
        for witness in clean.values {
            if case .releasing(let release) = witness {
                selected.formUnion(release.ownedOriginals.map(\.assetID))
                for origin in release.targetOrigins where old.retainedTargets.contains(origin.assetID) { retained.insert(origin.assetID) }
            }
        }
        for entry in old.entries.values where !selected.contains(entry.assetID) {
            let original = try SharedMediaNativeOriginalAccounting.audit(assetID: entry.assetID, inventoryID: inventory.id, context: context)
            guard original.retirement == nil else { throw SharedMediaStorageFailure.conflict }
            try SharedMediaNativeOriginalLiability.requireRetainedSurvivors(assetID: entry.assetID,
                expectedCount: original.liveCount, context: context)
        }
        let liability = SharedMediaNativeOriginalLiability.Snapshot(inventoryID: old.inventoryID, generation: old.generation,
            revision: after.inventoryRevision, entries: old.entries.filter { selected.contains($0.key) }, retainedTargets: retained)
        return try evaluate(context: context, inventory: inventory, graph: graph, format: .appV2, clean: clean,
            terminalProjection: after, terminalLiability: liability)
    }

    private static func evaluate(context: ModelContext, inventory: SharedMediaInventoryRecord,
                                 graph: SharedMediaPendingGraph, format: SharedMediaNativeScopedFormat?, clean: [UUID: SharedMediaNativeReceivingCleanGraph.Witness]? = nil, allocationPeers: [UUID: SharedMediaNativePhotoAllocationPeer]? = nil, intentProof: SharedMediaNativeAppIntentPoststate? = nil, metadataProof: SharedMediaNativeAppMetadataPoststate? = nil, acquisitionProof: SharedMediaNativeAppAcquisitionPoststate? = nil, preparationProof: SharedMediaNativeAppPreparationPoststate? = nil, pairPlanProof: SharedMediaNativeAppPairPlanPoststate? = nil, pairClosureProof: SharedMediaNativeAppPairPlanClosurePoststate? = nil, pairFileProof: SharedMediaNativeAppPairPoststate? = nil, pairRetirementProof: SharedMediaNativeAppPairRetirementPoststate? = nil, stagingProof: SharedMediaNativeAppStagingPoststate? = nil, pendingCleanupProof: SharedMediaNativeAppPendingPoststate? = nil, originalProof: SharedMediaNativeAppOriginalPoststate? = nil, originalReleaseProof: SharedMediaNativeAppOriginalReleasePoststate? = nil, terminalProjection: SharedMediaNativeReceivingReleaseValues.Released? = nil, terminalLiability: SharedMediaNativeOriginalLiability.Snapshot? = nil, checkpoint: () throws -> Void = {}) throws -> Snapshot {
        guard graph.sources.isEmpty, graph.handoffs.isEmpty else {
            throw SharedMediaStorageFailure.closed
        }
        let intents: [UUID: SharedMediaNativeReceivingPhaseGraph.Witness]
        if format == .appV2 {
            if let clean {
                guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
                intents = clean.compactMapValues { if case .generic(let value) = $0 { return value }; return nil }
            } else if let allocationPeers {
                intents = try SharedMediaNativePhotoAllocationPeer.pending(context, inventory: inventory, preserving: allocationPeers)
            } else {
                intents = try SharedMediaNativeReceivingPhaseGraph.pending(context, inventory: inventory)
            }
        } else {
            guard try SharedMediaNativeReceivingIntentGraph.snapshots(context).isEmpty else { throw SharedMediaStorageFailure.closed }
            intents = [:]
        }
        var totals = SharedMediaStoragePolicy.Totals(), metadata: [UUID: Int64] = [:], baseMetadata: [UUID: Int64] = [:]
        if format == .appV2 {
            let terminal = try SharedMediaNativeTerminalScan.read(container: context.container, inventoryID: inventory.id, checkpoint: checkpoint)
            try totals.includePhotoPhysical(materialized: terminal.bytes, reserved: 0)
            if let terminalProjection {
                try totals.includePhotoPhysical(materialized: Int64(terminalProjection.encoded().count), reserved: 0)
            }
        }
        var receivedLiability: [UUID: MetadataLiability] = [:]
        var chargedOriginAllocations = Set<UUID>(), chargedPhysical = Set<UUID>()
        for allocation in graph.allocations {
            guard chargedPhysical.insert(allocation.id).inserted else { throw SharedMediaStorageFailure.conflict }
            try totals.includePhotoPhysical(materialized: allocation.materializedBytes, reserved: allocation.reservedBytes)
        }
        for package in graph.packages {
            try Task.checkCancellation(); try checkpoint()
            let id = package.id
            if let witness = clean?[id], case .releasing(let release) = witness {
                let contribution = try releaseContribution(release, graph: graph, context: context,
                    inventory: inventory, totals: &totals, chargedPhysical: &chargedPhysical,
                    chargedReceipts: &chargedOriginAllocations)
                metadata[id] = contribution // No generic receiving base or mutation projection for a release.
                continue
            }
            let staged: SharedMediaNativeReceivedReleaseSnapshot.StagedSnapshot?
            if case .staged(let value) = clean?[id] { staged = value } else { staged = nil }
            let input: PackageInput; var allocation = allocationPeers?[id]
            if case .allocating(let snapshot) = clean?[id] { allocation = try .init(snapshot, context: context) }
            if let allocation {
                input = .init(consumerBytes: allocation.consumerBytes,
                    intent: .init(row: allocation.row, slot: .received(allocation.prepared, allocation.received, allocation.transaction), states: [], recoveryPresentationData: allocation.recoveryPresentationData),
                    allocation: allocation)
            } else if let staged {
                input = try stagedInput(staged.origin, context: context, checkpoint: checkpoint)
            } else {
                var receivingBytes: Int64 = 0
                if let consumer = try SharedMediaConsumerLookup.one(context, packageID: id) {
                    guard let format else { throw SharedMediaStorageFailure.closed }
                    if let intentProof { receivingBytes = try intentProof.receivingBytes(consumer, context: context, inventory: inventory) }
                    else if let stagingProof { receivingBytes = try stagingProof.receivingBytes(consumer) }
                    else if let pendingCleanupProof { receivingBytes = try pendingCleanupProof.receivingBytes(consumer) }
                    else if let originalProof { receivingBytes = try originalProof.receivingBytes(consumer) }
                    else if let originalReleaseProof { receivingBytes = try originalReleaseProof.receivingBytes(consumer) }
                    else if let pairRetirementProof { receivingBytes = try pairRetirementProof.receivingBytes(consumer) }
                    else if let pairFileProof { receivingBytes = try pairFileProof.receivingBytes(consumer) }
                    else if let pairClosureProof { receivingBytes = try pairClosureProof.receivingBytes(consumer) }
                    else if let pairPlanProof { receivingBytes = try pairPlanProof.receivingBytes(consumer) }
                    else if let preparationProof { receivingBytes = try preparationProof.receivingBytes(consumer) }
                    else if let metadataProof { receivingBytes = try metadataProof.receivingBytes(consumer) }
                    else if let acquisitionProof { receivingBytes = try acquisitionProof.receivingBytes(consumer) } else {
                        _ = try SharedMediaNativeConsumerGraph.validateScoped(consumer, context: context, format: format, checkpoint: checkpoint)
                        receivingBytes = Int64(consumer.cohortData.count)
                    }
                }
                input = .init(consumerBytes: receivingBytes, intent: intents[id])
            }
            // The scoped graph and phase/poststate proofs above have validated
            // these facts. The private input cannot be supplied by another owner.
            let measured = try measurePackage(input,
                package: package, graph: graph, inventory: inventory, context: context,
                format: format, checkpoint: checkpoint)
            for assetID in measured.originIDs {
                guard chargedOriginAllocations.insert(assetID).inserted else { throw SharedMediaStorageFailure.conflict }
            }
            let outstandingMetadata: Int64
            if let staged {
                guard measured.received == staged.historical.liability,
                      measured.baseBytes == staged.historical.baseBytes,
                      measured.originIDs == staged.historical.originIDs,
                      measured.preparationMetadata == 0 else { throw SharedMediaStorageFailure.conflict }
                try staged.origin.requireCurrent(context: context)
                outstandingMetadata = staged.funding.staged.reserved
                // No ordinary mutation base or received projection for a staged
                // root. Historical B and current S remain typed witness values.
            } else {
                baseMetadata[id] = measured.baseBytes
                if let received = measured.received { receivedLiability[id] = received }
                outstandingMetadata = measured.outstandingMetadata
            }
            let presentation = try input.intent?.recoveryPresentation
            let companion = presentation?.chargedBytes ?? 0
            let charged = try PhotoPreparationPolicy.add([measured.bytes, measured.preparationMetadata, companion])
            guard charged <= PhotoPreparationPolicy.metadata else { throw SharedMediaStorageFailure.capacity }
            metadata[id] = charged
            let bytes = measured.bytes
            let preparationMetadata = measured.preparationMetadata, plannedOutput = measured.plannedOutput
            let pairState = measured.pairState, attempt = measured.attempt, jobs = measured.jobs
            try totals.includePhotoPhysical(materialized: bytes - outstandingMetadata, reserved: outstandingMetadata)
            try totals.includePhotoPhysical(materialized: 0, reserved: preparationMetadata)
            try totals.includePhotoPhysical(materialized: presentation?.materializedBytes ?? 0, reserved: presentation?.reservedBytes ?? 0)
            var logical = charged
            for ref in graph.references where ref.packageID == id {
                guard let asset = graph.assets.first(where: { $0.id == ref.assetID }) else { throw SharedMediaStorageFailure.conflict }
                logical = try SharedMediaStoragePolicy.add(logical, asset.byteCount)
            }
            for job in jobs {
                logical = try SharedMediaStoragePolicy.add(logical, job.reservedByteCount)
            }
            if let attempt {
                logical = try SharedMediaStoragePolicy.add(logical, attempt.outputReservation)
                // One outstanding physical reservation, also counted logically
                // in the existing preparation pool (not counted free twice).
                try totals.includePhotoPhysical(materialized: 0, reserved: attempt.outputReservation)
            }
            if pairState?.phase == "planned" {
                logical = try SharedMediaStoragePolicy.add(logical, plannedOutput)
                try totals.includePhotoPhysical(materialized: 0, reserved: plannedOutput)
            }
            try totals.includePhotoPackage(id: id, bytes: logical, transferReserved: allocation?.allocation.transferReservation != nil)
            if let pairState, pairState.phase == "retiring" {
                // Retirement cannot resume preparation. Keep unfinished output
                // reservations until both absence proofs release the rows, but
                // do not reacquire scratch or duplicate completed references.
                let unfinished = try pairState.work.filter { $0.finalIdentity == nil }.reduce(Int64(0)) { sum, work in
                    try SharedMediaStoragePolicy.add(sum, pairState.selected(work.id).1.byteCount)
                }
                if unfinished > 0 { try totals.includePhotoPreparation(package: id, bytes: unfinished) }
            } else if pairState != nil && pairState?.phase != "ready" {
                try totals.includePhotoPreparation(package: id, bytes: try SharedMediaStoragePolicy.add(plannedOutput, preparationMetadata))
            }
            if let attempt {
                try totals.includePhotoPreparation(package: id, bytes: try SharedMediaStoragePolicy.add(attempt.outputReservation, preparationMetadata))
            }
            for job in jobs {
                if try SharedMediaNativePairFileGraph.nativeWork(assetID: job.assetID, context: context) != nil { continue }
                try totals.includeLogical(package: id, pool: .acquisition, bytes: job.reservedByteCount)
            }
        }
        // A pending share may outlive its physical origin package. Its original
        // receipt still occupies pending-owned physical storage exactly once,
        // without becoming metadata owned by each logical destination. The
        // bounded pending graph excludes entirely retained-library assets.
        let pendingIDs = Set(graph.packages.map(\.id))
        for allocation in graph.allocations.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            try Task.checkCancellation(); try checkpoint()
            let assetID = allocation.id
            if chargedOriginAllocations.contains(assetID) { continue }
            if try SharedMediaNativePairFileGraph.nativeWork(assetID: assetID, context: context) != nil { continue }
            guard let origin = allocation.packageID, !pendingIDs.contains(origin),
                  let owner = allocation.accountID, allocation.inventoryID == inventory.id else {
                throw SharedMediaStorageFailure.conflict
            }
            let row = try one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == assetID }))
            guard case .completed(let request, let result) = try SharedMediaAcquisitionReceipt.read(row),
                  request.assetID == assetID, request.packageID == origin, request.ownerID == owner,
                  request.inventoryID == inventory.id, request.inventoryGeneration == inventory.generation else {
                throw SharedMediaStorageFailure.conflict
            }
            try totals.includePhotoPhysical(materialized: SharedMediaAcquisitionReceipt.metadataCharge(request: request, result: result), reserved: 0)
            guard chargedOriginAllocations.insert(assetID).inserted else { throw SharedMediaStorageFailure.conflict }
        }
        let originalIdentity: SharedMediaNativeOriginalLiability.Snapshot?
        if format == .appV2 {
            let proof: SharedMediaNativeOriginalLiabilityPoststate.Proof?
            if let metadataProof { proof = .metadata(metadataProof) }
            else if let acquisitionProof { proof = .acquisition(acquisitionProof) }
            else if let preparationProof { proof = .preparation(preparationProof) }
            else if let pairPlanProof { proof = .pairPlan(pairPlanProof) }
            else if let pairClosureProof { proof = .pairClosure(pairClosureProof) }
            else if let pairFileProof { proof = .pairFile(pairFileProof) }
            else if let pairRetirementProof { proof = .pairRetirement(pairRetirementProof) }
            else if let intentProof { proof = .intent(intentProof) }
            else if let stagingProof { proof = .staging(stagingProof) }
            else if let pendingCleanupProof { proof = .pendingCleanup(pendingCleanupProof) }
            else if let originalProof { proof = .original(originalProof) }
            else if let originalReleaseProof { proof = .originalRelease(originalReleaseProof) }
            else { proof = nil }
            if let terminalLiability { originalIdentity = terminalLiability }
            else if let proof {
                originalIdentity = try SharedMediaNativeOriginalLiabilityPoststate.read(context: context, inventory: inventory, proof: proof)
            } else {
                originalIdentity = try SharedMediaNativeOriginalLiability.read(context: context, inventoryID: inventory.id, checkpoint: checkpoint)
            }
        } else { originalIdentity = nil }
        if let originalIdentity {
            try totals.includePhotoPhysical(materialized: originalIdentity.currentBytes,
                reserved: originalIdentity.reservedBytes)
        }
        return .init(totals: totals, originalIdentity: originalIdentity, metadataByPackage: metadata, baseMetadataByPackage: baseMetadata,
            receivedLiabilityByPackage: receivedLiability)
    }

    /// Private measured inputs are minted only after the existing consumer and
    /// phase/poststate checks, or after the explicit staged-origin validator.
    /// They grant no save, admission, cleanup or global accounting authority.
    private struct PackageInput {
        let consumerBytes: Int64
        let intent: SharedMediaNativeReceivingPhaseGraph.Witness?
        var allocation: SharedMediaNativePhotoAllocationPeer? = nil
    }

    private struct PackageBreakdown {
        let baseBytes: Int64
        let bytes: Int64
        let outstandingMetadata: Int64
        let preparationMetadata: Int64
        let plannedOutput: Int64
        let pairState: SharedMediaNativePairFileState?
        let attempt: SharedMediaNativePreparationAttempt?
        let jobs: [PhotoPreparationLease]
        let originIDs: Set<UUID>
        let received: MetadataLiability?
    }

    /// No global totals or dispatcher calls. Pair/receipt/membership sizing is
    /// shared by ordinary clean/dirty paths and the staged descriptive reader.
    private static func measurePackage(_ input: PackageInput, package: PhotoPreparationRecord,
                                       graph: SharedMediaPendingGraph, inventory: SharedMediaInventoryRecord,
                                       context: ModelContext, format: SharedMediaNativeScopedFormat?,
                                       checkpoint: () throws -> Void) throws -> PackageBreakdown {
        let id = package.id, receivingBytes = input.consumerBytes
        var originIDs = Set<UUID>(), received: MetadataLiability?
        let envelope = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData)
        try SharedMediaNativePreparationGraph.validate(envelope, package: package, context: context, scopedInventory: format == nil ? nil : inventory)
        let attempt = try envelope.attempt.map { try SharedMediaNativePreparationAttempt.decode($0.bytes) }
        var states: [SharedMediaNativePairFileState] = []
        if case .preparation(let value) = envelope, !value.intents.isEmpty {
            let member = try one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
            for blob in value.intents {
                let pairID = try SharedMediaNativeDerivativeIntent.decode(blob.bytes).pairID
                states.append(try SharedMediaNativePairFileGraph.state(context: context, inventory: inventory,
                    package: package, member: member, pairID: pairID))
            }
        }
        let active = states.filter { $0.phase != "ready" }
        guard active.count <= 1, attempt == nil || active.isEmpty else { throw SharedMediaStorageFailure.conflict }
        let pairState = active.first
        let plannedOutput: Int64
        if let pairState {
            let intent = try pairState.intent()
            plannedOutput = try SharedMediaStoragePolicy.add(intent.ai.byteCount, intent.display.byteCount)
        } else { plannedOutput = 0 }
        var planBytes: Int64 = 0
        for state in states {
            // Every survivor retains its full future cleanup projection.
            // Physical allocations and logical references are charged once
            // below; only the one active pair can own processing scratch.
            let maximum = try SharedMediaNativePairClosure.maximumStateBytes(state)
            guard Int64(try SharedMediaNativeDraftEnvelope.bytes(state).count) <= maximum else { throw SharedMediaStorageFailure.capacity }
            planBytes = try SharedMediaStoragePolicy.add(planBytes, maximum)
        }
        let jobs = graph.work.filter { $0.packageID == id }
        var pending: [SharedMediaAcquisitionIntent] = []
        var closureBytes: Int64 = 0
        for work in jobs {
            if try SharedMediaNativePairFileGraph.nativeWork(assetID: work.assetID, context: context) != nil { continue }
            let operation = work.id
            let row = try one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == operation }))
            switch try SharedMediaAcquisitionReceipt.read(row) {
            case .reserved(let request), .held(let request):
                guard request.assetID == work.assetID, request.packageID == id else { throw SharedMediaStorageFailure.conflict }
                pending.append(request)
                if let proof = work.terminalProof {
                    _ = try SharedMediaNativePendingClosure.decode(proof, request: request)
                    guard work.writerStateRaw == "closedPendingCleanupV1" else { throw SharedMediaStorageFailure.conflict }
                    closureBytes = try SharedMediaStoragePolicy.add(closureBytes, Int64(proof.utf8.count))
                }
            default: throw SharedMediaStorageFailure.conflict
            }
        }
        // Origin charges come from authoritative physical allocations, not
        // the receipt's package lookup aid or this package's logical shares.
        var origins = FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.packageID == id }, sortBy: [SortDescriptor(\.id)])
        origins.fetchLimit = SharedMediaStoragePolicy.pageSize; origins.includePendingChanges = true
        var receiptBytes: Int64 = 0, resultHeadroom: Int64 = 0
        var offset = 0
        while true {
            try Task.checkCancellation(); try checkpoint()
            origins.fetchOffset = offset
            let allocations = try context.fetch(origins)
            for allocation in allocations {
                try Task.checkCancellation(); try checkpoint()
                let assetID = allocation.id
                if try SharedMediaNativePairFileGraph.nativeWork(assetID: assetID, context: context) != nil { continue }
                let row = try one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == assetID }))
                let request: SharedMediaAcquisitionIntent, result: SharedMediaAcquisitionResult?
                switch try SharedMediaAcquisitionReceipt.read(row) {
                case .reserved(let value), .held(let value): request = value; result = nil
                case .completed(let value, let saved): request = value; result = saved
                case .released: throw SharedMediaStorageFailure.conflict
                }
                guard request.packageID == id, request.ownerID == package.ownerID,
                      allocation.inventoryID == inventory.id, allocation.accountID == package.ownerID else {
                    throw SharedMediaStorageFailure.conflict
                }
                receiptBytes = try SharedMediaStoragePolicy.add(receiptBytes,
                    SharedMediaAcquisitionReceipt.metadataCharge(request: request, result: result))
                guard originIDs.insert(assetID).inserted else { throw SharedMediaStorageFailure.conflict }
                if result == nil { resultHeadroom = try SharedMediaStoragePolicy.add(resultHeadroom, Int64(SharedMediaAcquisitionResult.reservedEncodingBytes)) }
                guard receiptBytes <= PhotoPreparationPolicy.metadata else { throw SharedMediaStorageFailure.capacity }
            }
            if allocations.count < SharedMediaStoragePolicy.pageSize { break }
            let (next, overflow) = offset.addingReportingOverflow(allocations.count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }
            offset = next
        }
        let member = try graph.membership(packageID: id)
        let projected = try member.maximumAcquisitionBytes(pending: pending)
        let baseBytes = try PhotoPreparationPolicy.add([Int64(package.supportingContextData.count), projected, receiptBytes, planBytes, receivingBytes])

        var preparedBytes: Int64 = 0, receivingHeadroom: Int64 = 0
        if let intent = input.intent {
            if let allocation = input.allocation {
                try allocation.requireUnchanged(context)
                guard allocation.row == intent.row else { throw SharedMediaStorageFailure.stale }
            } else { try intent.row.requireNoAllocation() }
            switch intent.slot {
            case .prepared(let prepared):
                guard attempt == nil, active.isEmpty, receivingBytes == 0 else { throw SharedMediaStorageFailure.closed }
                preparedBytes = Int64(try prepared.encoded().count)
                let projection = try SharedMediaNativeReceivingReservation.maximum(prepared,
                    currentMetadata: baseBytes, pairStates: intent.states)
                receivingHeadroom = projection.reserved
            case .received(_, _, let transaction):
                guard attempt == nil, active.isEmpty, receivingBytes > 0,
                      let prepared = intent.row.preparedData, let result = intent.row.resultData else {
                    throw SharedMediaStorageFailure.conflict
                }
                preparedBytes = try PhotoPreparationPolicy.add([Int64(prepared.count), Int64(result.count),
                    Int64(transaction.metadata.utf8.count), Int64(transaction.metadata.utf8.count)])
            case .abandoned:
                guard receivingBytes == 0, let result = intent.row.resultData else { throw SharedMediaStorageFailure.conflict }
                preparedBytes = Int64(result.count)
            }
        }
        let allocationCharge = try input.allocation?.allocation.storageCharge ?? 0
        let allocationCurrent = try input.allocation.map {
            try PhotoPreparationPolicy.add([Int64($0.allocation.encoded().count), 64])
        } ?? 0
        let bytes = try PhotoPreparationPolicy.add([baseBytes, preparedBytes, receivingHeadroom, allocationCharge])
        guard bytes <= PhotoPreparationPolicy.metadata else { throw SharedMediaStorageFailure.capacity }
        // Reserve the entire remaining existing metadata allowance before
        // processing. Later pair/result/member encodings must fit it.
        let preparing = attempt != nil || pairState?.phase == "planned" || pairState?.phase == "writing"
        let preparationMetadata = preparing ? PhotoPreparationPolicy.metadata - bytes : 0

        let membershipGrowth = projected - Int64(try member.encoded().count)
        guard closureBytes <= resultHeadroom else { throw SharedMediaStorageFailure.conflict }
        // The bounded closure projection is future liability, not bytes already on disk.
        let outstandingMetadata = try PhotoPreparationPolicy.add([
            resultHeadroom - closureBytes, membershipGrowth, planBytes, receivingHeadroom, allocationCharge - allocationCurrent])
        guard outstandingMetadata <= bytes else { throw SharedMediaStorageFailure.conflict }
        if let intent = input.intent, case .received = intent.slot {
            guard preparationMetadata == 0 else { throw SharedMediaStorageFailure.conflict }
            received = .init(current: bytes - outstandingMetadata, reserved: outstandingMetadata)
        }
        return .init(baseBytes: baseBytes, bytes: bytes, outstandingMetadata: outstandingMetadata,
            preparationMetadata: preparationMetadata, plannedOutput: plannedOutput, pairState: pairState,
            attempt: attempt, jobs: jobs, originIDs: originIDs, received: received)
    }

    struct HistoricalReceived {
        let baseBytes: Int64
        let liability: MetadataLiability
        let originIDs: Set<UUID>
    }

    /// Reconstruct the sidecar-free received liability under supported immutable
    /// receipt/allocation owners. This does not attest historical staging or
    /// arbitrary database tampering, and does not enter the global budget.
    static func historicalReceived(_ origin: SharedMediaNativeStagedReleaseOrigin,
                                   context: ModelContext, checkpoint: () throws -> Void = {}) throws -> HistoricalReceived {
        try origin.requireCurrent(context: context)
        let inventoryID = origin.prepared.profile.inventoryID, id = origin.row.id
        let inventory = try one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let graph = try SharedMediaPendingGraph.deriveScoped(in: context, inventory: inventory,
            ownerID: origin.prepared.profile.ownerID, format: .appV2)
        guard graph.sources.isEmpty, graph.handoffs.isEmpty,
              let package = graph.packages.first(where: { $0.id == id }) else { throw SharedMediaStorageFailure.closed }
        let input = try stagedInput(origin, context: context, checkpoint: checkpoint)
        let measured = try measurePackage(input, package: package, graph: graph,
            inventory: inventory, context: context, format: .appV2, checkpoint: checkpoint)
        guard let received = measured.received, measured.preparationMetadata == 0,
              try received.charged == measured.bytes else { throw SharedMediaStorageFailure.conflict }
        try origin.requireCurrent(context: context)
        return .init(baseBytes: measured.baseBytes, liability: received, originIDs: measured.originIDs)
    }

    private static func stagedInput(_ origin: SharedMediaNativeStagedReleaseOrigin,
                                    context: ModelContext, checkpoint: () throws -> Void) throws -> PackageInput {
        try origin.requireCurrent(context: context)
        let rows = try SharedMediaNativeReceivingPhaseGraph.receivedRows(origin.transaction, context: context)
        _ = try SharedMediaNativeConsumerGraph.validateStagedReceived(rows.consumer, origin: origin,
            context: context, checkpoint: checkpoint)
        return .init(consumerBytes: Int64(rows.consumer.cohortData.count),
            intent: .init(row: origin.row, slot: .received(origin.prepared, origin.received, origin.transaction), states: [], recoveryPresentationData: origin.recoveryPresentationData))
    }

    private static func one<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>) throws -> T {
        var query = descriptor; query.fetchLimit = 2; query.includePendingChanges = true
        let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first else { throw SharedMediaStorageFailure.conflict }
        return row
    }
}
