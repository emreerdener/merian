import Foundation
import SwiftData

/// Explicit abandonment and exact saved-closure recovery only. One transaction
/// per audited instance; the owner reacquires fresh authority between phases.
@MainActor
final class SharedMediaNativeAppPendingOperations {
    private let container: ModelContainer
    private let authority: SharedMediaNativeAppOperationAuthority
    private let expected: SharedMediaNativeAppEligibility.Header
    private let facts: SharedMediaNativeAppMetadataFacts
    private let originals: [UUID: SharedMediaNativeOriginalAccounting.Snapshot]
    private let io: SharedMediaNativeOriginalIO
    private let binding: SharedMediaNativeBinding
    private let files: PhotoPreparationLockedFiles
    private let boundary: (SharedMediaNativeLifecycleBoundary) throws -> Void
    private var consumed = false

    private init(container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                 expected: SharedMediaNativeAppEligibility.Header, facts: SharedMediaNativeAppMetadataFacts,
                 io: SharedMediaNativeOriginalIO, binding: SharedMediaNativeBinding, files: PhotoPreparationLockedFiles,
                 boundary: @escaping (SharedMediaNativeLifecycleBoundary) throws -> Void) throws {
        self.container = container; self.authority = authority; self.expected = expected; self.facts = facts
        self.io = io; self.binding = binding; self.files = files; self.boundary = boundary
        let c = ModelContext(container); c.autosaveEnabled = false
        originals = try Self.originalFacts(c, facts: facts)
    }
    static func audited(container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                        io: SharedMediaNativeOriginalIO, binding: SharedMediaNativeBinding, files: PhotoPreparationLockedFiles,
                        boundary: @escaping (SharedMediaNativeLifecycleBoundary) throws -> Void) async throws -> SharedMediaNativeAppPendingOperations {
        let header = try authority.header(container)
        func check() throws { guard try authority.header(container) == header else { throw SharedMediaStorageFailure.stale } }
        _ = try await SharedMediaNativeScopedAudit(app: container, profile: authority.profile, expected: header.inventory,
            check: check, betweenPages: { await Task.yield() }).run()
        try check()
        let c = ModelContext(container); c.autosaveEnabled = false
        return try .init(container: container, authority: authority, expected: header,
            facts: try SharedMediaNativeAppMetadataFacts.capture(c, profile: authority.profile),
            io: io, binding: binding, files: files, boundary: boundary)
    }
    func abandon(_ request: SharedMediaAcquisitionIntent) async throws {
        try validate()
        if try terminal(request) { return }
        let c = fresh(), rows = try target(c, request), before = try rows.state(request)
        _ = try rows.remainingPhase(c, request: request)
        if before.closure != nil { return }
        let inspection = try await io.inspectPending(request)
        try requireBefore(before)
        guard inspection.binding == binding.bytes, inspection.epoch == binding.epoch else { throw SharedMediaStorageFailure.conflict }
        let closure = inspection.closure, encoded = try closure.encoded(request: request)
        let proof = try SharedMediaNativeAppPendingPoststate(context: c, rows: rows, before: before,
            facts: facts, header: expected, closure: closure, releasedPhase: nil)
        rows.allocation.stateRaw = "p1PendingCleanupV1"; rows.lease.stateRaw = "closedPendingCleanupV1"
        rows.work.writerStateRaw = "closedPendingCleanupV1"; rows.work.terminalProof = encoded
        rows.package.phaseRaw = "needsAttention"; rows.package.revision = proof.package.revision
        rows.inventory.revision = proof.header.inventory.revision
        try save(c, rows: rows, before: before, proof: proof, closure: closure, releasing: false)
    }
    /// Selection is limited to this owner's bounded pending membership. Raw
    /// reservations without saved explicit closure are never selected.
    func recoverOne() async throws -> Bool {
        try validate()
        let c = fresh()
        for packageID in facts.members.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            if facts.intents[packageID] != nil { continue }
            guard let member = facts.members[packageID] else { throw SharedMediaStorageFailure.conflict }
            for id in try SharedMediaMembership.decode(member.bytes).ids(.work) {
                let work = try SharedMediaNativeAppPendingRows.one(c, FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == id }))
                guard work.writerStateRaw == "closedPendingCleanupV1" else { continue }
                let receipt = try SharedMediaNativeAppPendingRows.one(c, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id }))
                let request: SharedMediaAcquisitionIntent
                switch try SharedMediaAcquisitionReceipt.read(receipt) {
                case .reserved(let value), .held(let value): request = value
                default: throw SharedMediaStorageFailure.conflict
                }
                let rows = try target(c, request), before = try rows.state(request)
                guard let closure = before.closure else { throw SharedMediaStorageFailure.conflict }
                let phase = try rows.remainingPhase(c, request: request)
                try requireBefore(before)
                // A sealed, current V2 witness is required even when the physical
                // closure was recorded under a different process epoch.
                let witness = SharedMediaNativeAppPendingDisposalWitness(state: before, binding: binding)
                let disposal = SharedMediaNativePendingDisposal.app(witness)
                let absence = try await io.releasePending(disposal)
                try requireBefore(before)
                guard absence.disposal.state == before, absence.disposal.binding == binding.bytes,
                      absence.disposal.epoch == binding.epoch else { throw SharedMediaStorageFailure.conflict }
                let proof = try SharedMediaNativeAppPendingPoststate(context: c, rows: rows, before: before,
                    facts: facts, header: expected, closure: closure, releasedPhase: phase)
                c.delete(rows.allocation); c.delete(rows.lease); c.delete(rows.work)
                rows.receipt.phaseRaw = "terminal"; rows.receipt.revision = 2; rows.receipt.terminalOutcomeRaw = "released"
                rows.receipt.requestData = nil; rows.receipt.resultData = nil; rows.receipt.packageID = nil; rows.receipt.assetID = nil
                rows.package.phaseRaw = phase; rows.package.revision = proof.package.revision
                rows.member.membersData = proof.member.bytes; rows.member.revision = proof.member.revision
                rows.inventory.revision = proof.header.inventory.revision
                try save(c, rows: rows, before: before, proof: proof, closure: closure, releasing: true)
                return true
            }
        }
        return false
    }
    private func save(_ c: ModelContext, rows: SharedMediaNativeAppPendingRows, before: SharedMediaNativePendingState,
                      proof: SharedMediaNativeAppPendingPoststate, closure: SharedMediaNativePendingClosure, releasing: Bool) throws {
        _ = try SharedMediaNativeAcquisitionBudget.evaluatePendingCleanupPoststate(context: c, inventory: rows.inventory, proof: proof)
        try boundary(releasing ? .beforeReleaseSave : .beforeSave)
        try proof.validate(context: c, inventory: rows.inventory); try requireBefore(before)
        // Synchronous final seal, after all fault/await boundaries. General
        // closure compatibility is insufficient for releasing capacity.
        try files.verifyNativePending(before.request, closure: closure, binding: binding, requireAbsence: releasing)
        consumed = true
        do {
            try c.save(); try boundary(releasing ? .afterReleaseSave : .afterSave)
            try acknowledge(proof)
        } catch {
            let failure = error; c.rollback()
            do { try acknowledge(proof) } catch { throw failure }
        }
    }
    private func acknowledge(_ proof: SharedMediaNativeAppPendingPoststate) throws {
        try boundary(.beforeReadback)
        guard try authority.header(container) == proof.header else { throw SharedMediaStorageFailure.stale }
        let c = fresh(), id = authority.profile.inventoryID
        let inventory = try SharedMediaNativeAppPendingRows.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        try proof.validateSaved(context: c, inventory: inventory)
        _ = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inventory, ownerID: authority.profile.ownerID, format: .appV2)
    }
    private func terminal(_ request: SharedMediaAcquisitionIntent) throws -> Bool {
        try requireRequest(request); try boundary(.beforeReadback)
        let c = fresh(), id = request.operationID, inventoryID = request.inventoryID
        let row = try SharedMediaNativeAppPendingRows.one(c, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id }))
        let inventory = try SharedMediaNativeAppPendingRows.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        _ = try SharedMediaNativeAcquisitionGraph.scopedReceipt(row, inventory: inventory, context: c, format: .appV2)
        if case .released = try SharedMediaAcquisitionReceipt.read(row, expected: request) { try validate(); return true }
        return false
    }
    private func target(_ c: ModelContext, _ request: SharedMediaAcquisitionIntent) throws -> SharedMediaNativeAppPendingRows {
        try facts.requireNoIntent(request.packageID)
        try requireRequest(request)
        let rows = try SharedMediaNativeAppPendingRows(c, request: request)
        _ = try SharedMediaNativeAcquisitionGraph.scopedReceipt(rows.receipt, inventory: rows.inventory, context: c, format: .appV2)
        guard let package = facts.packages[request.packageID], let member = facts.members[request.packageID],
              facts.consumers[request.packageID] == nil,
              package == SharedMediaNativeAppMetadataFacts.Package(rows.package),
              member == SharedMediaNativeAppMetadataFacts.Member(rows.member),
              try SharedMediaNativeAppMetadataFacts.capture(c, profile: authority.profile) == facts else { throw SharedMediaStorageFailure.stale }
        try SharedMediaNativeAppPendingRows.noAdoption(c, request: request)
        _ = try rows.remainingPhase(c, request: request)
        _ = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: rows.inventory,
            ownerID: authority.profile.ownerID, format: .appV2)
        return rows
    }
    private func requireBefore(_ before: SharedMediaNativePendingState) throws {
        try validate()
        let c = fresh()
        guard try target(c, before.request).state(before.request) == before,
              try Self.originalFacts(c, facts: facts) == originals else { throw SharedMediaStorageFailure.stale }
    }
    private static func originalFacts(_ c: ModelContext, facts: SharedMediaNativeAppMetadataFacts) throws -> [UUID: SharedMediaNativeOriginalAccounting.Snapshot] {
        var ids = Set<UUID>(), result: [UUID: SharedMediaNativeOriginalAccounting.Snapshot] = [:]
        for member in facts.members.values {
            let membership = try SharedMediaMembership.decode(member.bytes)
            ids.formUnion(membership.ids(.asset)); ids.formUnion(membership.ids(.allocation))
        }
        for id in ids {
            if try SharedMediaNativePairFileGraph.nativeWork(assetID: id, context: c) != nil { continue }
            // Pending originals have no asset yet; their target tuple is checked
            // separately. Materialized originals include cross-package owners.
            if try c.fetchCount(FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == id })) == 0 { continue }
            result[id] = try SharedMediaNativeOriginalAccounting.audit(assetID: id, inventoryID: facts.profile.inventoryID, context: c)
        }
        return result
    }
    private func requireRequest(_ r: SharedMediaAcquisitionIntent) throws {
        try r.validate()
        guard r.inventoryID == authority.profile.inventoryID, r.inventoryGeneration == authority.profile.generation,
              r.ownerID == authority.profile.ownerID else { throw SharedMediaStorageFailure.conflict }
    }
    private func validate() throws {
        try Task.checkCancellation()
        guard !consumed, try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
    }
    private func fresh() -> ModelContext { let c = ModelContext(container); c.autosaveEnabled = false; return c }
    #if DEBUG
    func setReleaseFault(_ fault: (@Sendable (SharedMediaPhotoReleaseBoundary) throws -> Void)?) async throws {
        try validate(); await io.setReleaseFault(fault); try validate()
    }
    #endif
}

/// Can only be minted by the V2 owner after a fresh exact saved-intent read.
struct SharedMediaNativeAppPendingDisposalWitness: Sendable {
    let state: SharedMediaNativePendingState
    let binding: SharedMediaNativeBinding
    fileprivate init(state: SharedMediaNativePendingState, binding: SharedMediaNativeBinding) { self.state = state; self.binding = binding }
}

/// Closed five-update or three-delete/four-update transition. Public clean
/// audits stay clean-only; no generic dirty-context permission escapes.
@MainActor
struct SharedMediaNativeAppPendingPoststate {
    var allocationPeers: [UUID: SharedMediaNativePhotoAllocationPeer] { facts.allocationPeers }
    var predecessorRevision: Int64 { header.inventory.revision - 1 }
    let profile: SharedMediaNativeAppProfile
    let header: SharedMediaNativeAppEligibility.Header
    let package: SharedMediaNativeAppMetadataFacts.Package
    let member: SharedMediaNativeAppMetadataFacts.Member
    private let facts: SharedMediaNativeAppMetadataFacts
    private let before: SharedMediaNativePendingState
    private let closure: SharedMediaNativePendingClosure
    private let released: Bool
    private let contextID: ObjectIdentifier, inventoryIdentity: PersistentIdentifier
    private let updates: Set<PersistentIdentifier>, deletes: Set<PersistentIdentifier>

    fileprivate init(context c: ModelContext, rows: SharedMediaNativeAppPendingRows, before: SharedMediaNativePendingState,
                     facts: SharedMediaNativeAppMetadataFacts, header: SharedMediaNativeAppEligibility.Header,
                     closure: SharedMediaNativePendingClosure, releasedPhase: String?) throws {
        self.facts = facts; profile = facts.profile; self.before = before; self.closure = closure
        self.header = try SharedMediaNativeAppMetadataFacts.successor(header); released = releasedPhase != nil
        contextID = ObjectIdentifier(c); inventoryIdentity = rows.inventory.persistentModelID
        guard let old = facts.packages[before.request.packageID], let oldMember = facts.members[before.request.packageID],
              try rows.state(before.request) == before else { throw SharedMediaStorageFailure.conflict }
        package = try old.successor(old.envelope, phase: releasedPhase ?? "needsAttention")
        member = released ? try oldMember.successor(SharedMediaNativeAppPendingRows.membership(before)) : oldMember
        let reservation: Set<PersistentIdentifier> = [rows.allocation.persistentModelID, rows.lease.persistentModelID, rows.work.persistentModelID]
        if released {
            guard before.closure == closure else { throw SharedMediaStorageFailure.conflict }
            updates = [inventoryIdentity, rows.package.persistentModelID, rows.member.persistentModelID, rows.receipt.persistentModelID]
            deletes = reservation
        } else {
            guard before.closure == nil else { throw SharedMediaStorageFailure.conflict }
            updates = reservation.union([inventoryIdentity, rows.package.persistentModelID]); deletes = []
        }
    }
    func validate(context c: ModelContext, inventory: SharedMediaInventoryRecord) throws {
        guard ObjectIdentifier(c) == contextID, inventory.persistentModelID == inventoryIdentity,
              c.insertedModelsArray.isEmpty, Set(c.deletedModelsArray.map(\.persistentModelID)) == deletes,
              Set(c.changedModelsArray.map(\.persistentModelID)).subtracting(deletes) == updates else { throw SharedMediaStorageFailure.conflict }
        try validateSaved(context: c, inventory: inventory)
    }
    func validateSaved(context c: ModelContext, inventory: SharedMediaInventoryRecord) throws {
        guard try SharedMediaNativeAppEligibility.profile(inventory) == profile,
              inventory.revision == header.inventory.revision else { throw SharedMediaStorageFailure.conflict }
        try facts.validatePairPlan(c, package: package, member: member)
        try SharedMediaNativeAppPendingRows.noAdoption(c, request: before.request)
        let request = before.request, id = request.operationID, asset = request.assetID
        if released {
            let receipt = try SharedMediaNativeAppPendingRows.one(c, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id }))
            guard case .released = try SharedMediaAcquisitionReceipt.read(receipt, expected: request),
                  try c.fetchCount(FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == asset })) == 0,
                  try c.fetchCount(FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == id || $0.allocationID == asset })) == 0,
                  try c.fetchCount(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == id || $0.assetID == asset })) == 0 else { throw SharedMediaStorageFailure.conflict }
        } else {
            let state = try SharedMediaNativeAppPendingRows(c, request: request).state(request)
            guard state == SharedMediaNativePendingState(request: request, receiptPhase: before.receiptPhase, receiptRevision: before.receiptRevision,
                inventoryRevision: header.inventory.revision, packageRevision: package.revision, membershipRevision: member.revision,
                membershipBytes: member.bytes, envelope: package.envelope, allocatedBytes: package.allocated,
                phase: package.phase, closure: closure) else { throw SharedMediaStorageFailure.conflict }
        }
    }
    func receivingBytes(_ consumer: SharedMediaConsumerRecord) throws -> Int64 { try facts.receivingBytes(consumer) }
}
