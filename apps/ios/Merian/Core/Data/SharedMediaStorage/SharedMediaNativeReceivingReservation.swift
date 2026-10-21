import Foundation

/// Pure serialized-metadata projection. Inputs must come from one complete
/// audited target snapshot. currentMetadata is the pre-intent audited charge,
/// excluding Prepared bytes. This value grants no admission or save authority.
enum SharedMediaNativeReceivingReservation {
    struct Projection: Equatable, Sendable {
        let current: Int64
        let maximumSuccessor: Int64
        var charged: Int64 { max(current, maximumSuccessor) }
        var reserved: Int64 { charged - current }
    }
    static func maximum(_ prepared: SharedMediaNativeReceivingIntent.Prepared, currentMetadata: Int64,
                        pairStates: [SharedMediaNativePairFileState]) throws -> Projection {
        let header = SharedMediaNativeAppEligibility.Header(inventory: .init(generation: prepared.profile.generation,
            revision: Int64.max - 1, phase: SharedMediaNativeAppProfile.phase, cursor: ""),
            bootstrapID: prepared.profile.inventoryID, bootstrapGeneration: prepared.profile.generation,
            bootstrapContract: 2, bootstrapRevision: Int64.max)
        let current = try PhotoPreparationPolicy.add([currentMetadata, Int64(prepared.encoded().count)])
        let next = try successor(prepared, header: header, currentMetadata: currentMetadata, pairStates: pairStates)
        let result = Projection(current: current, maximumSuccessor: next)
        guard result.charged <= PhotoPreparationPolicy.metadata else { throw SharedMediaStorageFailure.capacity }
        return result
    }
    static func successor(_ prepared: SharedMediaNativeReceivingIntent.Prepared,
                          header: SharedMediaNativeAppEligibility.Header, currentMetadata: Int64,
                          pairStates: [SharedMediaNativePairFileState]) throws -> Int64 {
        let request = try prepared.descriptorForTransaction(header: header), frozen = try request.frozenPackage()
        let result = try SharedMediaNativeReceivingIntent.Received(prepared: prepared, request: request)
        let oldPairs = try pairBytes(prepared, states: pairStates)
        let removed = try PhotoPreparationPolicy.add([Int64(prepared.package.envelope.count), oldPairs])
        guard currentMetadata >= (try PhotoPreparationPolicy.add([removed, Int64(prepared.member.bytes.count)])) else {
            throw SharedMediaStorageFailure.conflict
        }
        var newPairs: Int64 = 0
        for state in pairStates {
            let p = state.plan
            let plan = SharedMediaNativePairPlan(intent: p.intent, writerEpoch: p.writerEpoch,
                inventoryID: p.inventoryID, inventoryGeneration: p.inventoryGeneration,
                inventoryRevision: try request.freeze.commit.inventoryRevision, packageID: p.packageID,
                draftGeneration: p.draftGeneration, packageRevision: frozen.revision, envelope: frozen.envelope,
                membershipRevision: p.membershipRevision, membership: p.membership)
            let next = SharedMediaNativePairFileState(plan: plan, phase: state.phase,
                publishedRevision: state.publishedRevision, allocatedBytes: state.allocatedBytes, work: state.work)
            newPairs = try PhotoPreparationPolicy.add([newPairs, SharedMediaNativePairClosure.maximumStateBytes(next)])
        }
        // Replace all envelope-dependent liabilities, including every ready
        // pair's future cleanup projection. Keep receipt/membership liability.
        // Queue has no context blob; job and event each retain metadata once.
        return try PhotoPreparationPolicy.add([
            currentMetadata - removed, Int64(frozen.envelope.count), newPairs,
            Int64(prepared.encoded().count), Int64(result.encoded(prepared: prepared).count),
            Int64(request.cohort.encoded().count), Int64(request.metadata.utf8.count), Int64(request.metadata.utf8.count)
        ])
    }
    static func materialized(_ prepared: SharedMediaNativeReceivingIntent.Prepared,
                             header: SharedMediaNativeAppEligibility.Header, currentMetadata: Int64,
                             pairStates: [SharedMediaNativePairFileState], reservation: Projection) throws -> Int64 {
        let expected = try maximum(prepared, currentMetadata: currentMetadata, pairStates: pairStates)
        guard expected == reservation else { throw SharedMediaStorageFailure.stale }
        let result = try successor(prepared, header: header, currentMetadata: currentMetadata, pairStates: pairStates)
        guard result <= reservation.maximumSuccessor, result <= PhotoPreparationPolicy.metadata else {
            throw SharedMediaStorageFailure.capacity
        }
        return result
    }
    private static func pairBytes(_ prepared: SharedMediaNativeReceivingIntent.Prepared,
                                  states: [SharedMediaNativePairFileState]) throws -> Int64 {
        let cohort = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes)
        guard states.count == cohort.entries.count,
              Set(states.map { $0.plan.intent.bytes }) == Set(cohort.entries.map { $0.intent.bytes }) else {
            throw SharedMediaStorageFailure.conflict
        }
        var total: Int64 = 0
        for state in states {
            let p = state.plan, intent = try state.intent()
            guard state.phase == "ready", state.allocatedBytes == prepared.package.allocated,
                  p.packageID == prepared.package.id,
                  p.draftGeneration == prepared.package.generation, p.packageRevision == prepared.package.revision,
                  p.envelope == prepared.package.envelope, p.inventoryID == prepared.profile.inventoryID,
                  p.inventoryGeneration == prepared.profile.generation,
                  p.membershipRevision == prepared.member.revision, p.membership == prepared.member.bytes else {
                throw SharedMediaStorageFailure.conflict
            }
            for input in [intent.ai, intent.display] {
                let work = try state.selected(input.id).0
                guard work.phase == "completed", work.writerState == "closed", work.finalIdentity != nil else {
                    throw SharedMediaStorageFailure.conflict
                }
            }
            total = try PhotoPreparationPolicy.add([total, SharedMediaNativePairClosure.maximumStateBytes(state)])
        }
        return total
    }
}
