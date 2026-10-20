import Foundation
import SwiftData

/// One audited app operation. Each transaction receives a sealed witness for
/// exactly one header and request; an uncertain save never renews that witness.
@MainActor
final class SharedMediaNativeAppAcquisitionOperations {
    private let container: ModelContainer
    private let authority: SharedMediaNativeAppAcquisitionAuthority
    private let io: SharedMediaNativeOriginalIO
    private let availableBytes: () throws -> Int64
    private let boundary: (SharedMediaNativeAcquisitionBoundary) throws -> Void
    private let entry: SharedMediaNativeAppEligibility.Header
    private let entryFacts: SharedMediaNativeAppMetadataFacts
    private var copyProof: SharedMediaPhotoRetirementInspection?
    private var expected: SharedMediaNativeAppEligibility.Header
    private var facts: SharedMediaNativeAppMetadataFacts
    private var consumed = false
    private var freshRequest: SharedMediaAcquisitionIntent?

    private init(container: ModelContainer, authority: SharedMediaNativeAppAcquisitionAuthority,
                 io: SharedMediaNativeOriginalIO, expected: SharedMediaNativeAppEligibility.Header,
                 facts: SharedMediaNativeAppMetadataFacts, availableBytes: @escaping () throws -> Int64,
                 boundary: @escaping (SharedMediaNativeAcquisitionBoundary) throws -> Void) {
        self.container = container; self.authority = authority; self.io = io; self.expected = expected
        entry = expected; entryFacts = facts
        self.facts = facts; self.availableBytes = availableBytes; self.boundary = boundary
    }
    static func audited(container: ModelContainer, authority: SharedMediaNativeAppAcquisitionAuthority,
                        io: SharedMediaNativeOriginalIO, request: SharedMediaAcquisitionIntent?,
                        availableBytes: @escaping () throws -> Int64,
                        boundary: @escaping (SharedMediaNativeAcquisitionBoundary) throws -> Void) async throws -> SharedMediaNativeAppAcquisitionOperations {
        guard authority.settlementRequest == nil else { throw SharedMediaStorageFailure.closed }
        let expected = try authority.header(container)
        func check() throws {
            guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
        }
        _ = try await SharedMediaNativeScopedAudit(app: container, profile: authority.profile, expected: expected.inventory,
            check: check, betweenPages: { await Task.yield() }).run()
        try check()
        let context = ModelContext(container); context.autosaveEnabled = false
        let facts = try SharedMediaNativeAppMetadataFacts.capture(context, profile: authority.profile)
        let result = SharedMediaNativeAppAcquisitionOperations(container: container, authority: authority, io: io,
            expected: expected, facts: facts, availableBytes: availableBytes, boundary: boundary)
        if let request, try result.receipt(request) == nil {
            guard request.writerEpoch == authority.writerEpoch, request.expectedInventoryRevision == expected.inventory.revision else { throw SharedMediaStorageFailure.stale }
            try await SharedMediaNativeAppAcquisitionIdentity.audit(request, container: container, check: check)
            result.freshRequest = request
        }
        try check(); return result
    }
    func request(packageID: UUID, draftGeneration: UUID, ordinal: Int64, kind: SharedMediaAcquisitionIntent.Kind) throws -> SharedMediaAcquisitionIntent {
        try validate()
        let context = fresh(), id = packageID
        var query = FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id }); query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
        if let package = rows.first {
            guard facts.members[id] != nil, package.ownerID == authority.profile.ownerID,
                  package.draftGeneration == draftGeneration, package.accountingTierRaw == "pending",
                  package.phaseRaw == "draftOwned", !package.retirementRequested, facts.consumers[id] == nil else { throw SharedMediaStorageFailure.closed }
        } else { guard facts.members[id] == nil else { throw SharedMediaStorageFailure.conflict } }
        let value = SharedMediaAcquisitionIntent(operationID: UUID(), inventoryID: authority.profile.inventoryID,
            inventoryGeneration: authority.profile.generation, ownerID: authority.profile.ownerID,
            expectedInventoryRevision: expected.inventory.revision, packageID: id, draftGeneration: draftGeneration,
            packageExpectation: rows.first.map { .revision($0.revision) } ?? .absent,
            assetID: UUID(), assetGeneration: UUID(), referenceID: UUID(), ordinal: ordinal, kind: kind,
            writerEpoch: authority.writerEpoch, maximumBytes: PhotoPreparationPolicy.original)
        try value.validate(); return value
    }
    func receipt(_ request: SharedMediaAcquisitionIntent) throws -> SharedMediaAcquisitionReceipt? {
        _ = try authority.header(container)
        try boundary(.beforeReadback)
        guard request.inventoryID == authority.profile.inventoryID, request.inventoryGeneration == authority.profile.generation,
              request.ownerID == authority.profile.ownerID else { throw SharedMediaStorageFailure.conflict }
        let context = fresh(), id = request.operationID, inventoryID = request.inventoryID
        var query = FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id }); query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
        guard let row = rows.first else { return nil }
        let inventory = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        _ = try SharedMediaAcquisitionReceipt.read(row, expected: request)
        return try SharedMediaNativeAcquisitionGraph.scopedReceipt(row, inventory: inventory, context: context, format: .appV2)
    }
    func settlement(_ request: SharedMediaAcquisitionIntent) throws -> SharedMediaNativeAppAcquisitionSettlement {
        guard freshRequest == request else { throw SharedMediaStorageFailure.closed }
        return .init(profile: authority.profile, request: request, entry: entry, facts: entryFacts, proof: copyProof)
    }
    func acquire(_ request: SharedMediaAcquisitionIntent, load: @escaping @Sendable () async throws -> Data,
                 writerState: (Bool) -> Void, didStartLoader: () -> Void) async throws -> SharedMediaAcquisitionResult {
        try validate()
        guard freshRequest == request else { throw SharedMediaStorageFailure.closed }
        try transition(request, completing: nil)
        try validate()
        guard case .reserved = try receipt(request) else { throw SharedMediaStorageFailure.conflict }
        didStartLoader()
        let data: Data
        do { writerState(true); defer { writerState(false) }; data = try await io.load(load) }
        try validate()
        guard case .reserved = try receipt(request) else { throw SharedMediaStorageFailure.conflict }
        let proof: SharedMediaPhotoRetirementInspection
        do { writerState(true); defer { writerState(false) }; proof = try await io.write(data, request: request) }
        copyProof = proof
        try validate(); try boundary(.afterOriginalWrite)
        guard case .reserved = try receipt(request) else { throw SharedMediaStorageFailure.conflict }
        // Verify the exact descriptor again immediately before completion.
        let current = try await io.inspect(proof.file)
        try validate()
        guard current.identity == proof.identity, current.binding == proof.binding, current.epoch == proof.epoch else { throw SharedMediaStorageFailure.conflict }
        try transition(request, completing: proof)
        guard case .completed(_, let result) = try receipt(request) else { throw SharedMediaStorageFailure.conflict }
        consumed = true; return result
    }
    private func transition(_ request: SharedMediaAcquisitionIntent, completing proof: SharedMediaPhotoRetirementInspection?) throws {
        try validate()
        let old = expected, before = facts
        let witness = SharedMediaNativeAppAcquisitionWitness(authority: authority, expected: old, facts: before, request: request)
        let mutation: SharedMediaNativeAcquisitionMutation
        if let proof { mutation = try .complete(container: container, witness: witness, proof: proof) }
        else { mutation = try .reserve(container: container, witness: witness, availableBytes: availableBytes()) }
        consumed = true
        do {
            try boundary(proof == nil ? .beforeReservationSave : .beforeCompletionSave)
            try mutation.save()
            try boundary(proof == nil ? .afterReservationSave : .afterCompletionSave)
        } catch { /* Only exact acknowledgement below can advance this operation. */ }
        let next = try SharedMediaNativeAppMetadataFacts.successor(old)
        guard try authority.header(container) == next else { throw SharedMediaStorageFailure.stale }
        let saved = try receipt(request)
        if proof == nil { guard case .reserved = saved else { throw SharedMediaStorageFailure.conflict } }
        else { guard case .completed = saved else { throw SharedMediaStorageFailure.conflict } }
        let after = try mutation.acknowledgeApp()
        if let proof {
            guard case .completed(_, let result) = saved, result.descriptor == proof.identity,
                  result.sha256 == proof.file.sha256, result.byteCount == proof.file.byteCount,
                  result.contentType == proof.file.contentType else { throw SharedMediaStorageFailure.conflict }
        }
        expected = next; facts = after
        consumed = false
    }
    /// Called only by the repository with a distinct post-writer settlement
    /// grant. No loader, file writer, reservation or completion is reachable.
    static func settle(container: ModelContainer, authority: SharedMediaNativeAppAcquisitionAuthority,
                       ticket: SharedMediaNativeAppAcquisitionSettlement, loaderStarted: Bool,
                       boundary: (SharedMediaNativeAcquisitionBoundary) throws -> Void) throws -> SharedMediaAcquisitionResult? {
        let request = ticket.request
        guard authority.settlementRequest == request, authority.profile == ticket.profile else { throw SharedMediaStorageFailure.closed }
        func fresh() -> ModelContext { let value = ModelContext(container); value.autosaveEnabled = false; return value }
        func read() throws -> SharedMediaAcquisitionReceipt? {
            _ = try authority.header(container); try boundary(.beforeReadback)
            let context = fresh(), id = request.operationID, inventoryID = request.inventoryID
            var query = FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id }); query.fetchLimit = 2
            let rows = try context.fetch(query)
            guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }; guard let row = rows.first else { return nil }
            _ = try SharedMediaAcquisitionReceipt.read(row, expected: request)
            let inventory = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
            return try SharedMediaNativeAcquisitionGraph.scopedReceipt(row, inventory: inventory, context: context, format: .appV2)
        }
        let reserved = try SharedMediaNativeAppMetadataFacts.successor(ticket.entry)
        let terminal = try SharedMediaNativeAppMetadataFacts.successor(reserved)
        let header = try authority.header(container)
        guard let saved = try read() else {
            guard !loaderStarted, header == ticket.entry,
                  try SharedMediaNativeAppMetadataFacts.capture(fresh(), profile: ticket.profile) == ticket.facts else { throw SharedMediaStorageFailure.conflict }
            return nil
        }
        try ticket.validateTarget(fresh(), saved: saved)
        switch saved {
        case .completed(_, let result):
            guard header == terminal else { throw SharedMediaStorageFailure.stale }; return result
        case .held:
            guard header == terminal else { throw SharedMediaStorageFailure.stale }; return nil
        case .reserved:
            guard header == reserved else { throw SharedMediaStorageFailure.stale }
            let facts = try SharedMediaNativeAppMetadataFacts.capture(fresh(), profile: ticket.profile)
            let witness = SharedMediaNativeAppAcquisitionWitness(authority: authority, expected: reserved, facts: facts, request: request)
            let mutation = try SharedMediaNativeAcquisitionMutation.hold(container: container, witness: witness)
            do { try boundary(.beforeHeldSave); try mutation.save(); try boundary(.afterHeldSave) } catch { /* Exact acknowledgement only. */ }
            guard try authority.header(container) == terminal, case .held = try read() else { throw SharedMediaStorageFailure.conflict }
            _ = try mutation.acknowledgeApp()
            try ticket.validateTarget(fresh(), saved: .held(request))
            return nil
        case .released: throw SharedMediaStorageFailure.conflict
        }
    }
    private func validate() throws {
        guard !consumed, try authority.header(container) == expected,
              try SharedMediaNativeAppMetadataFacts.capture(fresh(), profile: authority.profile) == facts else { throw SharedMediaStorageFailure.stale }
    }
    private func fresh() -> ModelContext {
        let context = ModelContext(container); context.autosaveEnabled = false; return context
    }
}

/// Only the audited operation can mint a transaction witness. It has no file,
/// loader, settlement or general-purpose save capability.
@MainActor
struct SharedMediaNativeAppAcquisitionWitness {
    let authority: SharedMediaNativeAppAcquisitionAuthority
    let expected: SharedMediaNativeAppEligibility.Header
    let facts: SharedMediaNativeAppMetadataFacts
    let request: SharedMediaAcquisitionIntent
    fileprivate init(authority: SharedMediaNativeAppAcquisitionAuthority, expected: SharedMediaNativeAppEligibility.Header,
                     facts: SharedMediaNativeAppMetadataFacts, request: SharedMediaAcquisitionIntent) {
        self.authority = authority; self.expected = expected; self.facts = facts; self.request = request
    }
    func validate(_ container: ModelContainer) throws {
        guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
        let context = ModelContext(container); context.autosaveEnabled = false
        guard try SharedMediaNativeAppMetadataFacts.capture(context, profile: authority.profile) == facts else { throw SharedMediaStorageFailure.stale }
    }
}

/// Value-only recovery anchor minted before the first save attempt. It cannot
/// grant work; the registered owner separately proves actual writer termination.
struct SharedMediaNativeAppAcquisitionSettlement {
    let profile: SharedMediaNativeAppProfile
    let request: SharedMediaAcquisitionIntent
    let entry: SharedMediaNativeAppEligibility.Header
    let facts: SharedMediaNativeAppMetadataFacts
    private let proof: SharedMediaPhotoRetirementInspection?
    fileprivate init(profile: SharedMediaNativeAppProfile, request: SharedMediaAcquisitionIntent,
                     entry: SharedMediaNativeAppEligibility.Header, facts: SharedMediaNativeAppMetadataFacts, proof: SharedMediaPhotoRetirementInspection?) {
        self.profile = profile; self.request = request; self.entry = entry; self.facts = facts; self.proof = proof
    }
    @MainActor func validateTarget(_ context: ModelContext, saved: SharedMediaAcquisitionReceipt) throws {
        try facts.validateAcquisition(context, packageID: request.packageID, hasMember: true)
        let current = try SharedMediaNativeAppMetadataFacts.capture(context, profile: profile)
        guard let package = current.packages[request.packageID], let member = current.members[request.packageID] else { throw SharedMediaStorageFailure.conflict }
        let old = facts.packages[request.packageID], oldMember = facts.members[request.packageID]
        let terminal: Bool, completed: Bool, bytes: Int64
        switch saved {
        case .reserved(let exact):
            guard exact == request else { throw SharedMediaStorageFailure.conflict }; terminal = false; completed = false; bytes = 0
        case .held(let exact):
            guard exact == request else { throw SharedMediaStorageFailure.conflict }; terminal = true; completed = false; bytes = 0
        case .completed(let exact, let result):
            guard exact == request, let proof, result.descriptor == proof.identity,
                  result.sha256 == proof.file.sha256, result.byteCount == proof.file.byteCount,
                  result.contentType == proof.file.contentType else { throw SharedMediaStorageFailure.conflict }
            terminal = true; completed = true; bytes = result.byteCount
        case .released: throw SharedMediaStorageFailure.conflict
        }
        let baseRevision = try old.map { try SharedMediaStoragePolicy.add($0.revision, 1) } ?? 0
        let baseMember = try oldMember.map { try SharedMediaStoragePolicy.add($0.revision, 1) } ?? 0
        let envelope = try old?.envelope ?? PhotoPreparationPolicy.encodeDraft(contexts: [])
        guard package.id == request.packageID, package.ownerID == request.ownerID, package.draftID == request.packageID,
              package.generation == request.draftGeneration, package.contract == PhotoPreparationPolicy.contract,
              package.tier == "pending", !package.retiring, package.envelope == envelope,
              package.phase == (terminal ? (completed ? "draftOwned" : "needsAttention") : "acquiring"),
              package.revision == (try SharedMediaStoragePolicy.add(baseRevision, terminal ? 1 : 0)),
              package.allocated == (try SharedMediaStoragePolicy.add(old?.allocated ?? 0, bytes)),
              member.inventoryID == request.inventoryID, member.inventoryGeneration == request.inventoryGeneration,
              member.ownerID == request.ownerID, member.draftGeneration == request.draftGeneration,
              member.revision == (try SharedMediaStoragePolicy.add(baseMember, completed ? 1 : 0)) else { throw SharedMediaStorageFailure.conflict }
        let prior = try oldMember.map { try SharedMediaMembership.decode($0.bytes) } ?? SharedMediaMembership(groups: [])
        var groups = Dictionary(uniqueKeysWithValues: prior.groups.map { ($0.kind, Set($0.ids)) })
        groups[.allocation, default: []].insert(request.assetID)
        groups[.lease, default: []].insert(request.operationID)
        if completed {
            groups[.asset, default: []].insert(request.assetID)
            groups[.reference, default: []].insert(request.referenceID)
            groups[.edge, default: []].insert(request.referenceID)
        } else { groups[.work, default: []].insert(request.operationID) }
        let expected = try SharedMediaMembership(groups: groups.filter { !$0.value.isEmpty }.map { kind, ids in
            .init(kind: kind, ids: ids.sorted { $0.uuidString < $1.uuidString })
        }.sorted { $0.kind.rawValue < $1.kind.rawValue })
        guard member.bytes == (try expected.encoded()) else { throw SharedMediaStorageFailure.conflict }
    }

}
