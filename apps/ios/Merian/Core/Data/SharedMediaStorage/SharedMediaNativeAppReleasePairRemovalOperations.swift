import Foundation
import SwiftData

/// First selected saved retiring pair only. Runtime dispatch/activation remains
/// closed; the existing owner supplies locks, work lease, root and account fences.
@MainActor
// The full name identifies the exact native operation and its ownership boundary.
// swiftlint:disable:next type_name
struct SharedMediaNativeAppReleasePairRemovalOperations {
    typealias Values = SharedMediaNativeReceivingReleaseValues
    let container: ModelContainer
    let authority: SharedMediaNativeAppOperationAuthority
    let expected: SharedMediaNativeAppEligibility.Header
    let settlement: SharedMediaNativeReleaseStageSettlement
    let io: SharedMediaNativeOriginalIO
    let binding: SharedMediaNativeBinding
    let verify: (SharedMediaNativeRetiringPairInspection) throws -> Void
    let verifyAbsence: (SharedMediaNativePairAbsence) throws -> Void
    let recoveryHeader: () throws -> SharedMediaNativeAppEligibility.Header
    let boundary: (SharedMediaNativeMetadataBoundary) throws -> Void

    func apply(_ before: Values.Progress) async throws -> Values.Progress {
        try validate()
        let saved = try SharedMediaNativeReleasePairRemovalRecovery.read(before, container: container,
            header: { try authority.header(container) })
        let after = try SharedMediaNativeReleasePairRemovalRecovery.successor(before)
        guard settlement.request == nil, settlement.pendingOriginalDisposition == nil, settlement.pendingOriginalDisposal == nil,
              settlement.pendingPairDisposal == nil || settlement.pendingPairDisposal?.before == before else {
            throw SharedMediaStorageFailure.closed
        }
        if saved.release.progress == after {
            if let prior = settlement.pendingPairDisposal {
                try prior.seal.requireSavedSuccessor(fresh()); try settlement.resolvedPairDisposal(before)
            }
            return after // Exact saved outcome always wins; no inspection/unlink.
        }
        let context = fresh()
        let capability = try SharedMediaNativeReleasePairRemovalCapability.audited(before, context: context,
            container: container, authority: authority, binding: binding, header: expected)
        if let prior = settlement.pendingPairDisposal {
            try prior.requireSame(capability); try prior.seal.requirePredecessor(context)
        }
        try SharedMediaNativeReleasePairRemovalFunding.check(capability)
        let container = container, io = io, verify = verify, recoveryHeader = recoveryHeader
        try settlement.beginPairDisposal(capability) {
            try await SharedMediaNativeReleasePairRemovalRecovery.settle(capability, container: container,
                io: io, verify: verify, header: recoveryHeader)
        }
        defer { capability.permit.revoke() }
        var inspections: [SharedMediaNativeRetiringPairInspection] = []
        for work in capability.state.work {
            let proof = try await io.inspectRetiringPair(capability.state, workID: work.id)
            try validate(); try capability.requireInspection(proof); inspections.append(proof)
        }
        try requirePredecessor(capability)
        try capability.activate(inspections, verify: verify)
        let disposal = try SharedMediaNativePairDisposal.held(capability)
        var proofs: [SharedMediaNativePairAbsence] = []
        for work in capability.state.work {
            proofs.append(try await io.releasePair(disposal, workID: work.id))
            try validate()
        }
        try requirePredecessor(capability)
        guard proofs.count == 2, Set(proofs.map(\.workID)) == Set(capability.state.work.map(\.id)),
              proofs.allSatisfy({ $0.state == capability.state && $0.binding == binding.bytes && $0.epoch == binding.epoch }) else {
            throw SharedMediaStorageFailure.conflict
        }
        for proof in proofs { try verifyAbsence(proof) }
        let packageID = before.plan.package.id, pairID = try capability.state.intent().pairID
        let inventoryID = authority.profile.inventoryID
        let inventory = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let package = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        let member = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        let pair = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == pairID }))
        guard let row = try SharedMediaNativeReceivingPhaseGraph.row(packageID, in: context) else { throw SharedMediaStorageFailure.stale }
        do {
            try SharedMediaNativePairRemovalRows.apply(context: context, package: package, pair: pair, before: capability.state)
            let next = capability.successor
            guard package.allocatedByteCount == next.package.allocated else { throw SharedMediaStorageFailure.conflict }
            package.revision = next.package.revision
            member.revision = next.member.revision; member.membersData = next.member.bytes
            row.revision = next.slotRevision; row.resultData = try after.encoded()
            row.resultSHA256 = SharedMediaAcquisitionEncoding.digest(row.resultData!)
            inventory.revision = try SharedMediaStoragePolicy.add(expected.inventory.revision, 1)
            try capability.seal.validate(context); try boundary(.beforeSave); try validate()
            try requirePredecessor(capability)
            try capability.seal.validate(context)
            for proof in proofs { try verifyAbsence(proof) }
            try validate() // No await between complete clean/physical/raw seals and save.
            do { try context.save(); try boundary(.afterSave) } catch { context.rollback(); return try recover(capability) }
            return try recover(capability)
        } catch { context.rollback(); throw error }
    }
    private func requirePredecessor(_ capability: SharedMediaNativeReleasePairRemovalCapability) throws {
        try validate()
        let context = fresh()
        let current = try SharedMediaNativeReleasePairRemovalCapability.audited(capability.before, context: context,
            container: container, authority: authority, binding: binding, header: expected)
        defer { current.permit.revoke() }
        try capability.requireSame(current); try capability.seal.requirePredecessor(context)
        try SharedMediaNativeReleasePairRemovalFunding.check(current)
    }
    private func recover(_ capability: SharedMediaNativeReleasePairRemovalCapability) throws -> Values.Progress {
        try boundary(.beforeReadback)
        let current = try authority.header(container)
        guard current.inventory.revision == (try SharedMediaStoragePolicy.add(expected.inventory.revision, 1)),
              try SharedMediaNativeReleasePairRemovalRecovery.read(capability.before, container: container,
                header: { try authority.header(container) }).release.progress == capability.after else { throw SharedMediaStorageFailure.closed }
        try capability.seal.requireSavedSuccessor(fresh())
        try settlement.resolvedPairDisposal(capability.before)
        return capability.after
    }
    private func validate() throws {
        guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
    }
    private func fresh() -> ModelContext { let c = ModelContext(container); c.autosaveEnabled = false; return c }
}
