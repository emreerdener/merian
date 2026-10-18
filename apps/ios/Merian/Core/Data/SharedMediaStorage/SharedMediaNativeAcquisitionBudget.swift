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
        let metadataByPackage: [UUID: Int64]
    }

    static func evaluate(context: ModelContext, inventory: SharedMediaInventoryRecord) throws -> Snapshot {
        let graph = try SharedMediaPendingGraph.derive(in: context, inventory: inventory)
        guard graph.sources.isEmpty, graph.handoffs.isEmpty else {
            throw SharedMediaStorageFailure.closed
        }
        var totals = SharedMediaStoragePolicy.Totals(), metadata: [UUID: Int64] = [:]
        for allocation in graph.allocations {
            try totals.includePhotoPhysical(materialized: allocation.materializedBytes, reserved: allocation.reservedBytes)
        }
        for package in graph.packages {
            let id = package.id
            let envelope = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData)
            try SharedMediaNativePreparationGraph.validate(envelope, package: package, context: context)
            let attempt = try envelope.attempt.map { try SharedMediaNativePreparationAttempt.decode($0.bytes) }
            let plan: SharedMediaNativePairPlan?
            if case .preparation(let value) = envelope, !value.intents.isEmpty {
                let member = try one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
                plan = try SharedMediaNativePairPlanGraph.state(context: context, inventory: inventory, package: package, member: member)
            } else { plan = nil }
            let plannedOutput: Int64
            var pairState: SharedMediaNativePairFileState?
            let planBytes: Int64
            if let plan {
                let intent = try SharedMediaNativeDerivativeIntent.decode(plan.intent.bytes)
                plannedOutput = try SharedMediaStoragePolicy.add(intent.ai.byteCount, intent.display.byteCount)
                // This bounded canonical projection charges duplicated row facts,
                // not only the envelope. It includes the future saved witness.
                let member = try one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
                let state = try SharedMediaNativePairFileGraph.state(context: context, inventory: inventory, package: package, member: member)
                pairState = state
                // Charge the complete assertion and both saved cleanup proofs.
                // Reserve the maximum canonical closure encoding before files.
                planBytes = try SharedMediaNativePairClosure.maximumStateBytes(state)
                guard Int64(try SharedMediaNativeDraftEnvelope.bytes(state).count) <= planBytes else { throw SharedMediaStorageFailure.capacity }
            } else { plannedOutput = 0; planBytes = 0 }
            guard try SharedMediaConsumerLookup.one(context, packageID: id) == nil else { throw SharedMediaStorageFailure.closed }
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
            origins.fetchLimit = SharedMediaStoragePolicy.pageSize
            var receiptBytes: Int64 = 0, resultHeadroom: Int64 = 0
            var offset = 0
            while true {
                origins.fetchOffset = offset
                let allocations = try context.fetch(origins)
                for allocation in allocations {
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
            let bytes = try PhotoPreparationPolicy.add([Int64(package.supportingContextData.count), projected, receiptBytes, planBytes])
            guard bytes <= PhotoPreparationPolicy.metadata else { throw SharedMediaStorageFailure.capacity }
            // Reserve the entire remaining existing metadata allowance before
            // processing. Later pair/result/member encodings must fit it.
            let preparing = attempt != nil || pairState?.phase == "planned" || pairState?.phase == "writing"
            let preparationMetadata = preparing ? PhotoPreparationPolicy.metadata - bytes : 0
            metadata[id] = bytes + preparationMetadata
            let membershipGrowth = projected - Int64(try member.encoded().count)
            guard closureBytes <= resultHeadroom else { throw SharedMediaStorageFailure.conflict }
            // The bounded closure projection is future liability, not bytes already on disk.
            let outstandingMetadata = try SharedMediaStoragePolicy.add(
                SharedMediaStoragePolicy.add(resultHeadroom - closureBytes, membershipGrowth), planBytes)
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
        return .init(totals: totals, metadataByPackage: metadata)
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
        var query = descriptor; query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first else { throw SharedMediaStorageFailure.conflict }
        return row
    }
}
