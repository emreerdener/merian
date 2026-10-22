import Foundation
import SwiftData

/// Pending-only accounting derived from the current graph. No mutation or
/// admission authority. Call after the complete graph audit (or typed post-state
/// validation) while retaining the same store fence. Retained bytes remain disk
/// occupancy and are never assigned a pending-package or retained-library cap.
@MainActor
enum SharedMediaNativeAcquisitionBudget {
    struct Snapshot {
        let totals: SharedMediaStoragePolicy.Totals
        /// Asset-owned identity bytes and headroom included once in global totals.
        let originalIdentity: SharedMediaNativeOriginalLiability.Snapshot?
        let metadataByPackage: [UUID: Int64]
        let baseMetadataByPackage: [UUID: Int64]
    }

    static func evaluate(context: ModelContext, inventory: SharedMediaInventoryRecord) throws -> Snapshot {
        let graph = try SharedMediaPendingGraph.derive(in: context, inventory: inventory)
        return try evaluate(context: context, inventory: inventory, graph: graph, format: nil)
    }

    static func evaluateScoped(context: ModelContext, inventory: SharedMediaInventoryRecord, ownerID: UUID, format: SharedMediaNativeScopedFormat = .existingV1, checkpoint: () throws -> Void = {}) throws -> Snapshot {
        let graph = try SharedMediaPendingGraph.deriveScoped(in: context, inventory: inventory, ownerID: ownerID, format: format)
        let clean = format == .appV2 ? try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory, checkpoint: checkpoint) : nil
        return try evaluate(context: context, inventory: inventory, graph: graph, format: format, clean: clean, checkpoint: checkpoint)
    }

    static func evaluateMetadataPoststate(context: ModelContext, inventory: SharedMediaInventoryRecord,
                                          proof: SharedMediaNativeAppMetadataPoststate) throws -> Snapshot {
        let graph = try SharedMediaPendingGraph.deriveMetadataPoststate(in: context, inventory: inventory, proof: proof)
        return try evaluate(context: context, inventory: inventory, graph: graph, format: .appV2, metadataProof: proof)
    }

    static func evaluateAcquisitionPoststate(context: ModelContext, inventory: SharedMediaInventoryRecord,
                                             proof: SharedMediaNativeAppAcquisitionPoststate) throws -> Snapshot {
        let graph = try SharedMediaPendingGraph.deriveAcquisitionPoststate(in: context, inventory: inventory, proof: proof)
        return try evaluate(context: context, inventory: inventory, graph: graph, format: .appV2, acquisitionProof: proof)
    }

    static func evaluatePreparationPoststate(context: ModelContext, inventory: SharedMediaInventoryRecord,
                                             proof: SharedMediaNativeAppPreparationPoststate) throws -> Snapshot {
        let graph = try SharedMediaPendingGraph.derivePreparationPoststate(in: context, inventory: inventory, proof: proof)
        return try evaluate(context: context, inventory: inventory, graph: graph, format: .appV2, preparationProof: proof)
    }

    static func evaluatePairPlanPoststate(context: ModelContext, inventory: SharedMediaInventoryRecord,
                                          proof: SharedMediaNativeAppPairPlanPoststate) throws -> Snapshot {
        let graph = try SharedMediaPendingGraph.derivePairPlanPoststate(in: context, inventory: inventory, proof: proof)
        return try evaluate(context: context, inventory: inventory, graph: graph, format: .appV2, pairPlanProof: proof)
    }

    static func evaluatePairClosurePoststate(context: ModelContext, inventory: SharedMediaInventoryRecord,
                                             proof: SharedMediaNativeAppPairPlanClosurePoststate) throws -> Snapshot {
        let graph = try SharedMediaPendingGraph.derivePairClosurePoststate(in: context, inventory: inventory, proof: proof)
        return try evaluate(context: context, inventory: inventory, graph: graph, format: .appV2, pairClosureProof: proof)
    }

    static func evaluatePairFilePoststate(context: ModelContext, inventory: SharedMediaInventoryRecord,
                                         proof: SharedMediaNativeAppPairPoststate) throws -> Snapshot {
        let graph = try SharedMediaPendingGraph.derivePairFilePoststate(in: context, inventory: inventory, proof: proof)
        return try evaluate(context: context, inventory: inventory, graph: graph, format: .appV2, pairFileProof: proof)
    }

    static func evaluatePairRetirementPoststate(context: ModelContext, inventory: SharedMediaInventoryRecord,
                                               proof: SharedMediaNativeAppPairRetirementPoststate) throws -> Snapshot {
        let graph = try SharedMediaPendingGraph.derivePairRetirementPoststate(in: context, inventory: inventory, proof: proof)
        return try evaluate(context: context, inventory: inventory, graph: graph, format: .appV2, pairRetirementProof: proof)
    }

    static func evaluateIntentPoststate(context: ModelContext, inventory: SharedMediaInventoryRecord,
                                       proof: SharedMediaNativeAppIntentPoststate) throws -> Snapshot {
        let graph = try SharedMediaPendingGraph.deriveIntentPoststate(in: context, inventory: inventory, proof: proof)
        return try evaluate(context: context, inventory: inventory, graph: graph, format: .appV2, intentProof: proof)
    }

    static func evaluateStagingPoststate(context: ModelContext, inventory: SharedMediaInventoryRecord,
                                         proof: SharedMediaNativeAppStagingPoststate) throws -> Snapshot {
        let graph = try SharedMediaPendingGraph.deriveStagingPoststate(in: context, inventory: inventory, proof: proof)
        return try evaluate(context: context, inventory: inventory, graph: graph, format: .appV2, stagingProof: proof)
    }

    static func evaluatePendingCleanupPoststate(context: ModelContext, inventory: SharedMediaInventoryRecord,
                                                proof: SharedMediaNativeAppPendingPoststate) throws -> Snapshot {
        let graph = try SharedMediaPendingGraph.derivePendingCleanupPoststate(in: context, inventory: inventory, proof: proof)
        return try evaluate(context: context, inventory: inventory, graph: graph, format: .appV2, pendingCleanupProof: proof)
    }

    static func evaluateOriginalPoststate(context: ModelContext, inventory: SharedMediaInventoryRecord,
                                         proof: SharedMediaNativeAppOriginalPoststate) throws -> Snapshot {
        let graph = try SharedMediaPendingGraph.deriveOriginalPoststate(in: context, inventory: inventory, proof: proof)
        return try evaluate(context: context, inventory: inventory, graph: graph, format: .appV2, originalProof: proof)
    }

    static func evaluateOriginalReleasePoststate(context: ModelContext, inventory: SharedMediaInventoryRecord,
                                         proof: SharedMediaNativeAppOriginalReleasePoststate) throws -> Snapshot {
        let graph = try SharedMediaPendingGraph.deriveOriginalReleasePoststate(in: context, inventory: inventory, proof: proof)
        return try evaluate(context: context, inventory: inventory, graph: graph, format: .appV2, originalReleaseProof: proof)
    }

    private static func evaluate(context: ModelContext, inventory: SharedMediaInventoryRecord,
                                 graph: SharedMediaPendingGraph, format: SharedMediaNativeScopedFormat?, clean: [UUID: SharedMediaNativeReceivingCleanGraph.Witness]? = nil, intentProof: SharedMediaNativeAppIntentPoststate? = nil, metadataProof: SharedMediaNativeAppMetadataPoststate? = nil, acquisitionProof: SharedMediaNativeAppAcquisitionPoststate? = nil, preparationProof: SharedMediaNativeAppPreparationPoststate? = nil, pairPlanProof: SharedMediaNativeAppPairPlanPoststate? = nil, pairClosureProof: SharedMediaNativeAppPairPlanClosurePoststate? = nil, pairFileProof: SharedMediaNativeAppPairPoststate? = nil, pairRetirementProof: SharedMediaNativeAppPairRetirementPoststate? = nil, stagingProof: SharedMediaNativeAppStagingPoststate? = nil, pendingCleanupProof: SharedMediaNativeAppPendingPoststate? = nil, originalProof: SharedMediaNativeAppOriginalPoststate? = nil, originalReleaseProof: SharedMediaNativeAppOriginalReleasePoststate? = nil, checkpoint: () throws -> Void = {}) throws -> Snapshot {
        guard graph.sources.isEmpty, graph.handoffs.isEmpty else {
            throw SharedMediaStorageFailure.closed
        }
        let intents: [UUID: SharedMediaNativeReceivingPhaseGraph.Witness]
        if format == .appV2 {
            if let clean {
                guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
                intents = clean.compactMapValues { if case .generic(let value) = $0 { return value }; return nil }
            } else {
                intents = try SharedMediaNativeReceivingPhaseGraph.pending(context, inventory: inventory)
            }
        } else {
            guard try SharedMediaNativeReceivingIntentGraph.snapshots(context).isEmpty else { throw SharedMediaStorageFailure.closed }
            intents = [:]
        }
        var totals = SharedMediaStoragePolicy.Totals(), metadata: [UUID: Int64] = [:], baseMetadata: [UUID: Int64] = [:]
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
                    guard chargedOriginAllocations.insert(assetID).inserted else { throw SharedMediaStorageFailure.conflict }
                    if result == nil { resultHeadroom = try SharedMediaStoragePolicy.add(resultHeadroom, Int64(SharedMediaAcquisitionResult.reservedEncodingBytes)) }
                    guard receiptBytes <= PhotoPreparationPolicy.metadata else { throw SharedMediaStorageFailure.capacity }
                }
                if allocations.count < SharedMediaStoragePolicy.pageSize { break }
                let (next, overflow) = offset.addingReportingOverflow(allocations.count)
                guard !overflow else { throw SharedMediaStorageFailure.capacity }
                offset = next
            }
            let member = try graph.membership(packageID: id)
            let projected = try maximumMembershipBytes(member, pending: pending)
            let baseBytes = try PhotoPreparationPolicy.add([Int64(package.supportingContextData.count), projected, receiptBytes, planBytes, receivingBytes])
            baseMetadata[id] = baseBytes
            var preparedBytes: Int64 = 0, receivingHeadroom: Int64 = 0
            if let intent = intents[id] {
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
            let bytes = try PhotoPreparationPolicy.add([baseBytes, preparedBytes, receivingHeadroom])
            guard bytes <= PhotoPreparationPolicy.metadata else { throw SharedMediaStorageFailure.capacity }
            // Reserve the entire remaining existing metadata allowance before
            // processing. Later pair/result/member encodings must fit it.
            let preparing = attempt != nil || pairState?.phase == "planned" || pairState?.phase == "writing"
            let preparationMetadata = preparing ? PhotoPreparationPolicy.metadata - bytes : 0
            metadata[id] = bytes + preparationMetadata
            let membershipGrowth = projected - Int64(try member.encoded().count)
            guard closureBytes <= resultHeadroom else { throw SharedMediaStorageFailure.conflict }
            // The bounded closure projection is future liability, not bytes already on disk.
            let outstandingMetadata = try PhotoPreparationPolicy.add([
                resultHeadroom - closureBytes, membershipGrowth, planBytes, receivingHeadroom])
            guard outstandingMetadata <= bytes else { throw SharedMediaStorageFailure.conflict }
            try totals.includePhotoPhysical(materialized: bytes - outstandingMetadata, reserved: outstandingMetadata)
            try totals.includePhotoPhysical(materialized: 0, reserved: preparationMetadata)
            var logical = bytes + preparationMetadata
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
            try totals.includePhotoPackage(id: id, bytes: logical)
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
            if let proof {
                originalIdentity = try SharedMediaNativeOriginalLiabilityPoststate.read(context: context, inventory: inventory, proof: proof)
            } else {
                originalIdentity = try SharedMediaNativeOriginalLiability.read(context: context, inventoryID: inventory.id, checkpoint: checkpoint)
            }
        } else { originalIdentity = nil }
        if let originalIdentity {
            try totals.includePhotoPhysical(materialized: originalIdentity.currentBytes,
                reserved: originalIdentity.reservedBytes)
        }
        return .init(totals: totals, originalIdentity: originalIdentity, metadataByPackage: metadata, baseMetadataByPackage: baseMetadata)
    }

    /// Clean held-release values only. Identity is deliberately absent here:
    /// the single asset-owned pass below supplies current bytes and headroom.
    private static func releaseContribution(_ snapshot: SharedMediaNativeReleaseMetadataSnapshot.Snapshot,
                                            graph: SharedMediaPendingGraph, context: ModelContext,
                                            inventory: SharedMediaInventoryRecord,
                                            totals: inout SharedMediaStoragePolicy.Totals,
                                            chargedPhysical: inout Set<UUID>, chargedReceipts: inout Set<UUID>) throws -> Int64 {
        guard !context.hasChanges, snapshot.inventoryRevision == inventory.revision else {
            throw SharedMediaStorageFailure.stale
        }
        let projection = try SharedMediaNativeReleaseSurvivorProjection.maximum(snapshot)
        try projection.requireMetadataCapacity()
        let current = try PhotoPreparationPolicy.add([snapshot.packagePayloadBytes, snapshot.originReceiptBytes])
        var maximum = current
        for charge in projection.charges {
            maximum = max(maximum, try PhotoPreparationPolicy.add([charge.packageBytes, charge.originReceiptBytes]))
        }
        try totals.includePhotoPhysical(materialized: current, reserved: maximum - current)
        let id = snapshot.release.state.package.id
        for original in snapshot.ownedOriginals {
            let assetID = original.assetID
            let allocation = try one(context, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == assetID }))
            guard allocation.inventoryID == inventory.id, allocation.packageID == id,
                  allocation.accountID == snapshot.release.progress.plan.profile.ownerID,
                  allocation.reservedBytes == 0,
                  allocation.physicalIdentity.map({ Int64($0.utf8.count) }) == original.identityBytes,
                  chargedReceipts.insert(assetID).inserted else { throw SharedMediaStorageFailure.conflict }
            let receipt = try one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == assetID }))
            guard case .completed(let request, let result) = try SharedMediaAcquisitionReceipt.read(receipt),
                  request.assetID == assetID, request.packageID == id,
                  request.inventoryID == inventory.id, request.inventoryGeneration == inventory.generation,
                  request.ownerID == allocation.accountID, allocation.materializedBytes == result.byteCount,
                  try SharedMediaAcquisitionReceipt.metadataCharge(request: request, result: result) == original.receiptBytes else {
                throw SharedMediaStorageFailure.conflict
            }
            // The complete metadata/live audit binds receipt, acquisition and
            // physical origin. The same allocation may also be in a recipient's
            // pending graph; only an origin absent there adds physical bytes.
            if chargedPhysical.insert(assetID).inserted {
                try totals.includePhotoPhysical(materialized: allocation.materializedBytes, reserved: 0)
            }
        }
        let metadata = projection.maximumLivePackageMetadataBytes
        var logical = metadata
        for reference in graph.references where reference.packageID == id {
            guard let asset = graph.assets.first(where: { $0.id == reference.assetID }) else {
                throw SharedMediaStorageFailure.conflict
            }
            logical = try SharedMediaStoragePolicy.add(logical, asset.byteCount)
        }
        try totals.includePhotoPackage(id: id, bytes: logical)
        return metadata
    }

    /// Existing two-original limit bounds the power set to four states. A
    /// partial completion can encode more than both-current or both-complete
    /// membership, because empty groups disappear from canonical encoding.
    static func maximumMembershipBytes(_ current: SharedMediaMembership,
                                       pending: [SharedMediaAcquisitionIntent]) throws -> Int64 {
        guard pending.count <= 2, Set(pending.map(\.operationID)).count == pending.count else {
            throw SharedMediaStorageFailure.conflict
        }
        var maximum: Int64 = 0
        for mask in 0..<(1 << pending.count) {
            var groups = Dictionary(uniqueKeysWithValues: current.groups.map { ($0.kind, Set($0.ids)) })
            for (index, request) in pending.enumerated() {
                guard groups[.work]?.contains(request.operationID) == true,
                      groups[.lease]?.contains(request.operationID) == true,
                      groups[.allocation]?.contains(request.assetID) == true else { throw SharedMediaStorageFailure.conflict }
                if mask & (1 << index) == 0 { continue }
                groups[.work]?.remove(request.operationID)
                guard groups[.asset, default: []].insert(request.assetID).inserted,
                      groups[.reference, default: []].insert(request.referenceID).inserted,
                      groups[.edge, default: []].insert(request.referenceID).inserted else { throw SharedMediaStorageFailure.conflict }
            }
            let value = try SharedMediaMembership(groups: groups.filter { !$0.value.isEmpty }.map { kind, ids in
                .init(kind: kind, ids: ids.sorted { $0.uuidString < $1.uuidString })
            }.sorted { $0.kind.rawValue < $1.kind.rawValue })
            maximum = max(maximum, Int64(try value.encoded().count))
        }
        return maximum
    }

    private static func one<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>) throws -> T {
        var query = descriptor; query.fetchLimit = 2; query.includePendingChanges = true
        let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first else { throw SharedMediaStorageFailure.conflict }
        return row
    }
}
