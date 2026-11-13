import Foundation

// The full domain name distinguishes this state or capability from adjacent storage boundaries.
/// Unconsumed metadata feasibility calculation, not admission or deletion
/// authority. All inputs must come from the same fully audited received P2
/// snapshot. Physical media stays charged until the existing absence authority
/// settles it; this calculation only replaces serialized metadata liabilities.
enum SharedMediaNativeReceivingReleaseProjection { // swiftlint:disable:this type_name
    typealias Values = SharedMediaNativeReceivingReleaseValues
    typealias Intent = SharedMediaNativeReceivingIntent

    struct Projection: Equatable, Sendable {
        let receivedBytes: Int64
        let maximumIntermediateBytes: Int64
        let terminalBytes: Int64
        let statesExamined: Int
        var maximum: Int64 { max(maximumIntermediateBytes, terminalBytes) }
        var additionalReservation: Int64 { max(0, maximum - receivedBytes) }
        func requireExistingReservation() throws {
            guard maximum <= receivedBytes, maximum <= PhotoPreparationPolicy.metadata else {
                throw SharedMediaStorageFailure.capacity
            }
        }
    }

    /// Enumerates a conservative superset of reachable stages (at most 36).
    /// The ordinary owner permits only one active pair, but considering both
    /// retiring simultaneously cannot understate the metadata upper bound.
    static func maximum(plan: Values.Plan, prepared: Intent.Prepared, received: Intent.Received,
                        acquisitionIDs: [UUID], currentMetadata: Int64,
                        pairStates: [SharedMediaNativePairFileState]) throws -> Projection {
        let slot = try Values.slotBound(plan: plan, prepared: prepared, received: received, acquisitionIDs: acquisitionIDs)
        let request = try received.reconstruct(prepared), frozen = try request.frozenPackage()
        guard currentMetadata >= 0, currentMetadata <= PhotoPreparationPolicy.metadata,
              pairStates.count == plan.targets.count,
              pairStates.map({ $0.plan.intent.sha256 }) == plan.targets.map(\.intentSHA256) else {
            throw SharedMediaStorageFailure.conflict
        }
        var oldPairs: Int64 = 0
        for (target, state) in zip(plan.targets, pairStates) {
            let p = state.plan, intent = try state.intent()
            guard state.phase == "ready", state.allocatedBytes == frozen.allocated,
                  p.inventoryID == plan.profile.inventoryID, p.inventoryGeneration == plan.profile.generation,
                  p.inventoryRevision == plan.preHeader.inventory.revision,
                  p.packageID == frozen.id, p.draftGeneration == frozen.generation,
                  p.packageRevision == frozen.revision, p.envelope == frozen.envelope,
                  p.membershipRevision == prepared.member.revision, p.membership == prepared.member.bytes,
                  intent.pairID == target.pairID, intent.preparation.original.reference == target.original,
                  Values.Output(intent.ai) == target.ai, Values.Output(intent.display) == target.display else {
                throw SharedMediaStorageFailure.conflict
            }
            for input in [intent.ai, intent.display] {
                let work = try state.selected(input.id).0
                guard work.phase == "completed", work.writerState == "closed", work.finalIdentity != nil else {
                    throw SharedMediaStorageFailure.conflict
                }
            }
            oldPairs = try SharedMediaStoragePolicy.add(oldPairs, SharedMediaNativePairClosure.maximumStateBytes(state))
        }
        let removed = try PhotoPreparationPolicy.add([Int64(prepared.member.bytes.count), oldPairs, slot.replacedBytes])
        guard currentMetadata >= removed else { throw SharedMediaStorageFailure.conflict }
        // Keep envelope, acquisition receipts and execution quartet unchanged
        // in the conservative residual until final exact deletion. Progress
        // embeds Plan, so there is no separately added progress/plan charge.
        let residual = currentMetadata - removed
        let count = pairStates.count == 1 ? 6 : 36
        // A saved retiring pair can embed an earlier, larger membership even
        // after another target is removed. Bound every survivor against the
        // union of initial IDs and all possible retirement additions. Reusing
        // only today's smaller membership would lose that historical proof.
        let closureMembership = try membership(prepared.member.bytes, targets: plan.targets,
            stages: Array(repeating: 1, count: pairStates.count))
        var maximum: Int64 = 0
        for code in 0..<count {
            let stages = pairStates.count == 1 ? [code] : [code % 6, code / 6]
            let membership = try membership(prepared.member.bytes, targets: plan.targets, stages: stages)
            var survivorPairs: Int64 = 0
            for (index, state) in pairStates.enumerated() where stages[index] <= 1 {
                let p = state.plan
                let nextPlan = SharedMediaNativePairPlan(intent: p.intent, writerEpoch: p.writerEpoch,
                    inventoryID: p.inventoryID, inventoryGeneration: p.inventoryGeneration,
                    inventoryRevision: p.inventoryRevision, packageID: p.packageID,
                    draftGeneration: p.draftGeneration, packageRevision: p.packageRevision,
                    envelope: p.envelope, membershipRevision: p.membershipRevision, membership: closureMembership)
                let next = SharedMediaNativePairFileState(plan: nextPlan, phase: state.phase,
                    publishedRevision: state.publishedRevision, allocatedBytes: state.allocatedBytes, work: state.work)
                survivorPairs = try SharedMediaStoragePolicy.add(survivorPairs, SharedMediaNativePairClosure.maximumStateBytes(next))
            }
            // A last-original retirement identity is bounded by the existing
            // 512-byte native identity format. Keep the full amount, without
            // assuming any offset from the previous allocation identity.
            let originals = Int64(stages.filter { $0 == 3 }.count) * 512
            maximum = max(maximum, try PhotoPreparationPolicy.add([
                residual, Int64(membership.count), survivorPairs, slot.charged, originals
            ]))
        }
        return Projection(receivedBytes: currentMetadata, maximumIntermediateBytes: maximum,
            terminalBytes: slot.maximumReleasedBytes, statesExamined: count)
    }

    /// 0 ready, 1 retiring pair, 2 pair gone, 3 original retiring,
    /// 4 last original settled, 5 logical shared reference removed. Keep shared
    /// physical origin membership conservatively until terminal settlement.
    /// This is a projection, never a replacement for authoritative graph joins.
    private static func membership(_ bytes: Data, targets: [Values.Target], stages: [Int]) throws -> Data {
        var groups = Dictionary(uniqueKeysWithValues: try SharedMediaMembership.decode(bytes).groups.map { ($0.kind, Set($0.ids)) })
        func remove(_ kind: SharedMediaMembership.Kind, _ id: UUID) throws {
            guard groups[kind, default: []].remove(id) != nil else { throw SharedMediaStorageFailure.conflict }
        }
        for (index, target) in targets.enumerated() {
            let stage = stages[index]
            if stage == 1 {
                for output in [target.ai, target.display] {
                    guard groups[.work, default: []].insert(output.leaseID).inserted,
                          groups[.lease, default: []].insert(output.leaseID).inserted else {
                        throw SharedMediaStorageFailure.conflict
                    }
                }
            } else if stage >= 2 {
                try remove(.pair, target.pairID)
                for output in [target.ai, target.display] {
                    try remove(.derivative, output.workID)
                    try remove(.allocation, output.assetID); try remove(.asset, output.assetID)
                    try remove(.reference, output.referenceID); try remove(.edge, output.referenceID)
                }
            }
            if stage >= 4 {
                try remove(.reference, target.original.referenceID); try remove(.edge, target.original.referenceID)
                if stage == 4 {
                    try remove(.asset, target.original.assetID); try remove(.allocation, target.original.assetID)
                    try remove(.lease, target.acquisitionID)
                }
            }
        }
        return try SharedMediaMembership(groups: groups.filter { !$0.value.isEmpty }.map { kind, ids in
            .init(kind: kind, ids: ids.sorted { $0.uuidString < $1.uuidString })
        }.sorted { $0.kind.rawValue < $1.kind.rawValue }).encoded()
    }
}
