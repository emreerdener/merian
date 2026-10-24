import Foundation
import SwiftData

/// One fresh app-scoped audit per transaction. Ready original lifecycle only;
/// consumer ownership and provider execution are never changed here.
@MainActor
final class SharedMediaNativeAppOriginalOperations {
    typealias Rows = SharedMediaNativeAppOriginalRows
    private let container: ModelContainer
    private let authority: SharedMediaNativeAppOperationAuthority
    private let header: SharedMediaNativeAppEligibility.Header
    private let facts: SharedMediaNativeAppMetadataFacts
    private let originals: [UUID: SharedMediaNativeOriginalAccounting.Snapshot]
    private let io: SharedMediaNativeOriginalIO
    private let binding: SharedMediaNativeBinding
    private let files: PhotoPreparationLockedFiles
    private let availableBytes: () throws -> Int64
    private let boundary: (SharedMediaNativeLifecycleBoundary) throws -> Void
    private var consumed = false

    private init(container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                 header: SharedMediaNativeAppEligibility.Header, facts: SharedMediaNativeAppMetadataFacts,
                 io: SharedMediaNativeOriginalIO, binding: SharedMediaNativeBinding, files: PhotoPreparationLockedFiles,
                 availableBytes: @escaping () throws -> Int64, boundary: @escaping (SharedMediaNativeLifecycleBoundary) throws -> Void) throws {
        self.container = container; self.authority = authority; self.header = header; self.facts = facts
        self.io = io; self.binding = binding; self.files = files; self.availableBytes = availableBytes; self.boundary = boundary
        let c = ModelContext(container); c.autosaveEnabled = false
        originals = try Rows.originalFacts(c, facts: facts)
    }
    static func audited(container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                        io: SharedMediaNativeOriginalIO, binding: SharedMediaNativeBinding, files: PhotoPreparationLockedFiles,
                        availableBytes: @escaping () throws -> Int64,
                        boundary: @escaping (SharedMediaNativeLifecycleBoundary) throws -> Void) async throws -> SharedMediaNativeAppOriginalOperations {
        let header = try authority.header(container)
        func check() throws { guard try authority.header(container) == header else { throw SharedMediaStorageFailure.stale } }
        _ = try await SharedMediaNativeScopedAudit(app: container, profile: authority.profile, expected: header.inventory,
            check: check, betweenPages: { await Task.yield() }).run()
        try check()
        let c = ModelContext(container); c.autosaveEnabled = false
        return try .init(container: container, authority: authority, header: header,
            facts: try SharedMediaNativeAppMetadataFacts.capture(c, profile: authority.profile), io: io,
            binding: binding, files: files, availableBytes: availableBytes, boundary: boundary)
    }
    func prepareShare(_ source: PhotoOriginalReference, packageID: UUID, generation: UUID) throws -> SharedMediaNativeAppOriginalRequest {
        try facts.requireMutable(source.packageID); try facts.requireNoIntent(packageID)
        try validate()
        let c = fresh(), rows = try ready(c, source), original = try audit(c, source.assetID)
        let ref = try Rows.reference(c, source: source, live: true).0
        try absentPackage(c, packageID)
        guard packageID != source.packageID else { throw SharedMediaStorageFailure.stale }
        let request = SharedMediaNativeShareRequest(source: source, inventoryID: facts.profile.inventoryID,
            inventoryGeneration: facts.profile.generation, inventoryRevision: header.inventory.revision,
            sourcePackageRevision: rows.package.revision, liveCount: original.liveCount, countRevision: original.countRevision,
            packageID: packageID, draftGeneration: generation, nonce: UUID(), envelope: try PhotoPreparationPolicy.encodeDraft(contexts: []))
        return .init(profile: facts.profile, source: source, package: .init(rows.package), member: .init(rows.member),
            original: original, ordinal: ref.ordinal, action: .share(request))
    }
    func prepareRemoval(_ source: PhotoOriginalReference) throws -> SharedMediaNativeAppOriginalRequest {
        try facts.requireNoIntent(source.packageID)
        try validate()
        let c = fresh(), rows = try ready(c, source), original = try audit(c, source.assetID)
        let ref = try Rows.reference(c, source: source, live: true).0
        try Rows.noPair(c, source: source)
        let before = try SharedMediaNativeDraftEnvelope.decode(rows.package.supportingContextData)
        let request = SharedMediaNativeRemovalRequest(source: source, inventoryID: facts.profile.inventoryID,
            inventoryGeneration: facts.profile.generation, inventoryRevision: header.inventory.revision,
            packageRevision: rows.package.revision, membershipRevision: rows.member.revision,
            membershipBytes: rows.member.membersData, previousEnvelope: rows.package.supportingContextData,
            envelope: try before.editing(contexts: before.contexts, presentation: before.presentation.filter { $0.referenceID != source.referenceID }),
            liveCount: original.liveCount, countRevision: original.countRevision, retirementID: UUID())
        return .init(profile: facts.profile, source: source, package: .init(rows.package), member: .init(rows.member),
            original: original, ordinal: ref.ordinal, action: .remove(request))
    }
    func share(_ request: SharedMediaNativeAppOriginalRequest) async throws -> PhotoOriginalReference {
        try facts.requireMutable(request.source.packageID)
        try validate(); try requestProfile(request)
        guard case .share(let share) = request.action else { throw SharedMediaStorageFailure.conflict }
        let destination = try share.destination()
        if try savedShare(request) { return destination }
        let c = fresh(), rows = try before(c, request)
        try absentPackage(c, destination.packageID); try Rows.absentReference(c, destination.referenceID)
        try SharedMediaNativeReleaseStageIdentity.requireFresh([destination.packageID, destination.referenceID], inventoryID: facts.profile.inventoryID, context: c)
        let inspection = try await io.inspect(request.original.file)
        try requireBefore(request)
        guard inspection.identity == (try rows.completed().1.descriptor), inspection.binding == binding.bytes,
              inspection.epoch == binding.epoch else { throw SharedMediaStorageFailure.conflict }
        let package = PhotoPreparationRecord(id: destination.packageID, ownerID: destination.ownerID,
            contractVersion: PhotoPreparationPolicy.contract, draftID: destination.packageID, draftGeneration: destination.draftGeneration,
            revision: 0, phaseRaw: "draftOwned", supportingContextData: share.envelope,
            allocatedByteCount: rows.asset.byteCount, retirementRequested: false)
        let member = try SharedMediaPendingMembershipRecord(packageID: package.id, inventoryID: facts.profile.inventoryID,
            inventoryGeneration: facts.profile.generation, ownerID: package.ownerID, draftGeneration: package.draftGeneration,
            membersData: Rows.shareMembership(destination, leaseID: rows.lease.id))
        let ref = PhotoPreparationReference(id: destination.referenceID, packageID: destination.packageID,
            assetID: destination.assetID, ownerID: destination.ownerID, roleRaw: "original", ordinal: 0, revision: 0, isLive: true)
        let edge = SharedMediaReferenceRecord(id: destination.referenceID, allocationID: destination.assetID,
            accountID: destination.ownerID, ownerID: destination.referenceID.uuidString.lowercased(),
            roleRaw: SharedMediaPhotoLedger.namespace, stateRaw: "live", revision: 0)
        c.insert(package); c.insert(member); c.insert(ref); c.insert(edge)
        let proof = try SharedMediaNativeAppOriginalPoststate(c, facts: facts, header: header, rows: rows,
            request: request, package: .init(package), member: .init(member), retirement: nil,
            inserts: [package.persistentModelID, member.persistentModelID, ref.persistentModelID, edge.persistentModelID])
        rows.count.liveCount = try plus(rows.count.liveCount); rows.count.revision = try plus(rows.count.revision)
        rows.inventory.revision = proof.header.inventory.revision
        let budget = try SharedMediaNativeAcquisitionBudget.evaluateOriginalPoststate(context: c, inventory: rows.inventory, proof: proof)
        try budget.totals.checkAvailable(availableBytes(), additionalReservation: budget.metadataByPackage[package.id] ?? 0)
        try save(c, rows: rows, proof: proof, before: { try self.requireBefore(request) }, seal: { try self.files.requireCurrentSharedInspection(inspection) })
        return destination
    }
    func remove(_ request: SharedMediaNativeAppOriginalRequest) async throws {
        try facts.requireNoIntent(request.source.packageID)
        try validate(); try requestProfile(request)
        guard case .remove(let removal) = request.action else { throw SharedMediaStorageFailure.conflict }
        if try savedRemoval(request) { return }
        let c = fresh(), rows = try before(c, request)
        try Rows.noPair(c, source: request.source)
        let (ref, edge) = try Rows.reference(c, source: request.source, live: true, ordinal: request.ordinal)
        let final = request.original.liveCount == 1
        let inspection = final ? try await io.inspect(request.original.file) : nil
        try requireBefore(request)
        let retirement: SharedMediaNativeRetirementIdentity?
        if let inspection {
            guard inspection.binding == binding.bytes, inspection.epoch == binding.epoch,
                  inspection.identity == (try rows.completed().1.descriptor) else { throw SharedMediaStorageFailure.conflict }
            retirement = try .init(retirementID: removal.retirementID, assetID: request.source.assetID,
                assetGeneration: request.source.assetGeneration, inventoryID: facts.profile.inventoryID,
                inventoryGeneration: facts.profile.generation, ownerID: facts.profile.ownerID, proof: inspection.identity)
        } else { retirement = nil }
        let member = try request.member.successor(rows.removalMember(c, source: request.source, final: final))
        let package = try request.package.successor(removal.envelope, allocated: final ? request.package.allocated : request.package.allocated - request.original.byteCount)
        let proof = try SharedMediaNativeAppOriginalPoststate(c, facts: facts, header: header, rows: rows,
            request: request, package: package, member: member, retirement: retirement,
            references: [ref.persistentModelID, edge.persistentModelID])
        if let retirement {
            ref.isLive = false; ref.revision = try plus(ref.revision); edge.stateRaw = "retired"; edge.revision = ref.revision
            rows.asset.cleanupStateRaw = "retiring"; rows.allocation.stateRaw = SharedMediaNativeRetirementIdentity.allocationState
            rows.allocation.physicalIdentity = try retirement.encoded(); rows.count.retirementID = retirement.retirementID
        } else { c.delete(ref); c.delete(edge) }
        rows.count.liveCount -= 1; rows.count.revision = try plus(rows.count.revision)
        rows.package.supportingContextData = package.envelope; rows.package.allocatedByteCount = package.allocated; rows.package.revision = package.revision
        rows.member.membersData = member.bytes; rows.member.revision = member.revision; rows.inventory.revision = proof.header.inventory.revision
        try save(c, rows: rows, proof: proof, before: { try self.requireBefore(request) }, seal: {
            if let inspection { try self.files.requireCurrentSharedInspection(inspection) }
        })
    }
    func recoverOne() async throws -> Bool {
        try validate()
        let c = fresh()
        var ids = Set<UUID>()
        for member in facts.members.values { ids.formUnion(try SharedMediaMembership.decode(member.bytes).ids(.asset)) }
        for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) {
            if try SharedMediaNativePairFileGraph.nativeWork(assetID: id, context: c) != nil { continue }
            let count = try Rows.one(c, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == id }))
            guard count.liveCount == 0 else { continue }
            let state = try retirementState(c, id: id)
            if facts.intents[state.reference.packageID] != nil { continue }
            let rows = try Rows(c, profile: facts.profile, source: state.reference)
            let disposal = SharedMediaNativeRetirement.app(SharedMediaNativeAppOriginalDisposalWitness(state: state, binding: binding))
            let absence = try await io.release(disposal)
            try requireRetirement(state)
            guard absence.retirement.state == state, absence.retirement.binding == binding.bytes,
                  absence.retirement.epoch == binding.epoch else { throw SharedMediaStorageFailure.conflict }
            let proof = try SharedMediaNativeAppOriginalReleasePoststate(c, facts: facts, header: header, rows: rows, state: state)
            try proof.apply(c, rows: rows)
            _ = try SharedMediaNativeAcquisitionBudget.evaluateOriginalReleasePoststate(context: c, inventory: rows.inventory, proof: proof)
            try boundary(.beforeReleaseSave); try proof.validate(context: c, inventory: rows.inventory); try requireRetirement(state)
            try files.requireNativeAbsence(state.file, retirement: state.identity, binding: binding)
            consumed = true
            do { try c.save(); try boundary(.afterReleaseSave); try acknowledgeRelease(proof) }
            catch { let failure = error; c.rollback(); do { try acknowledgeRelease(proof) } catch { throw failure } }
            return true
        }
        return false
    }
    private func retirementState(_ c: ModelContext, id: UUID) throws -> SharedMediaNativeRetirementState {
        let original = try audit(c, id)
        guard let retirement = original.retirement, original.liveCount == 0 else { throw SharedMediaStorageFailure.stale }
        let ref = try Rows.one(c, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.assetID == id }))
        guard ref.revision > 0, let package = facts.packages[ref.packageID], facts.consumers[ref.packageID] == nil else { throw SharedMediaStorageFailure.closed }
        let source = PhotoOriginalReference(ownerID: ref.ownerID, packageID: ref.packageID, referenceID: ref.id,
            assetID: id, assetGeneration: original.assetGeneration, draftGeneration: package.generation, referenceRevision: ref.revision - 1)
        let rows = try Rows(c, profile: facts.profile, source: source)
        try rows.readyPackage(source, facts: facts); try Rows.noPair(c, source: source)
        _ = try Rows.reference(c, source: source, live: false)
        let (request, result) = try rows.completed()
        guard result.descriptor == retirement.proof else { throw SharedMediaStorageFailure.conflict }
        return .init(request: request, file: original.file, identity: retirement, reference: source,
            inventoryRevision: header.inventory.revision, packageRevision: rows.package.revision,
            membershipRevision: rows.member.revision, countRevision: original.countRevision,
            membershipBytes: rows.member.membersData, envelope: rows.package.supportingContextData)
    }
    private func requireRetirement(_ state: SharedMediaNativeRetirementState) throws {
        try validate(); let c = fresh()
        guard try retirementState(c, id: state.file.assetID) == state,
              try SharedMediaNativeAppMetadataFacts.capture(c, profile: facts.profile) == facts,
              try Rows.originalFacts(c, facts: facts) == originals else { throw SharedMediaStorageFailure.stale }
    }
    private func acknowledgeRelease(_ proof: SharedMediaNativeAppOriginalReleasePoststate) throws {
        try boundary(.beforeReadback)
        guard try authority.header(container) == proof.header else { throw SharedMediaStorageFailure.stale }
        let c = fresh(), id = facts.profile.inventoryID
        let inventory = try Rows.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        try proof.validateSaved(context: c, inventory: inventory)
        var expected = try originals.mapValues { try $0.atInventoryRevision(proof.header.inventory.revision) }
        expected.removeValue(forKey: proof.assetID)
        guard try Rows.originalFacts(c, facts: SharedMediaNativeAppMetadataFacts.capture(c, profile: facts.profile)) == expected else { throw SharedMediaStorageFailure.stale }
        _ = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inventory, ownerID: facts.profile.ownerID, format: .appV2)
    }
    private func ready(_ c: ModelContext, _ source: PhotoOriginalReference) throws -> Rows {
        let rows = try Rows(c, profile: facts.profile, source: source)
        try rows.readyPackage(source, facts: facts); _ = try Rows.reference(c, source: source, live: true)
        let original = try audit(c, source.assetID)
        guard original.retirement == nil, original.liveCount > 0 else { throw SharedMediaStorageFailure.stale }
        _ = try rows.completed(); return rows
    }
    private func before(_ c: ModelContext, _ r: SharedMediaNativeAppOriginalRequest) throws -> Rows {
        try requestProfile(r)
        let rows = try ready(c, r.source)
        guard SharedMediaNativeAppMetadataFacts.Package(rows.package) == r.package,
              SharedMediaNativeAppMetadataFacts.Member(rows.member) == r.member,
              try audit(c, r.source.assetID) == r.original.atInventoryRevision(header.inventory.revision) else { throw SharedMediaStorageFailure.stale }
        _ = try Rows.reference(c, source: r.source, live: true, ordinal: r.ordinal)
        if case .remove = r.action { try Rows.noPair(c, source: r.source) }
        return rows
    }
    private func requireBefore(_ r: SharedMediaNativeAppOriginalRequest) throws {
        try validate(); let c = fresh(); _ = try before(c, r)
        guard try SharedMediaNativeAppMetadataFacts.capture(c, profile: facts.profile) == facts,
              try Rows.originalFacts(c, facts: facts) == originals else { throw SharedMediaStorageFailure.stale }
        if case .share(let share) = r.action {
            let destination = try share.destination()
            try absentPackage(c, share.packageID); try Rows.absentReference(c, destination.referenceID)
            try SharedMediaNativeReleaseStageIdentity.requireFresh([destination.packageID, destination.referenceID], inventoryID: facts.profile.inventoryID, context: c)
        }
    }
    private func savedShare(_ r: SharedMediaNativeAppOriginalRequest) throws -> Bool {
        guard case .share(let share) = r.action else { throw SharedMediaStorageFailure.conflict }
        let c = fresh(), id = share.packageID
        guard try c.fetchCount(FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id })) != 0 else { return false }
        try SharedMediaNativeAppOriginalPoststate.validateShare(c, request: r)
        return true
    }
    private func savedRemoval(_ r: SharedMediaNativeAppOriginalRequest) throws -> Bool {
        let c = fresh(), id = r.source.referenceID
        var q = FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == id }); q.fetchLimit = 2
        let values = try c.fetch(q)
        if values.count == 1, values[0].isLive, values[0].revision == r.source.referenceRevision { return false }
        // A fully released original has no removal-specific durable witness.
        // It is stale, not a successful replay inferred from missing rows.
        try SharedMediaNativeAppOriginalPoststate.validateRemoval(c, request: r)
        return true
    }
    private func requestProfile(_ r: SharedMediaNativeAppOriginalRequest) throws {
        try SharedMediaNativeAppOriginalPoststate.validateRequest(r)
        guard r.profile == facts.profile, r.source.ownerID == facts.profile.ownerID,
              r.package.id == r.source.packageID, r.member.id == r.source.packageID,
              r.package.generation == r.source.draftGeneration,
              r.original.assetID == r.source.assetID, r.original.assetGeneration == r.source.assetGeneration,
              r.original.retirement == nil, r.original.liveCount > 0 else { throw SharedMediaStorageFailure.stale }
    }
    private func absentPackage(_ c: ModelContext, _ id: UUID) throws {
        guard try c.fetchCount(FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id })) == 0,
              try c.fetchCount(FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id })) == 0,
              try SharedMediaConsumerLookup.one(c, packageID: id) == nil else { throw SharedMediaStorageFailure.stale }
    }
    private func save(_ c: ModelContext, rows: Rows, proof: SharedMediaNativeAppOriginalPoststate,
                      before: () throws -> Void, seal: () throws -> Void) throws {
        _ = try SharedMediaNativeAcquisitionBudget.evaluateOriginalPoststate(context: c, inventory: rows.inventory, proof: proof)
        try boundary(.beforeSave); try proof.validate(context: c, inventory: rows.inventory); try before(); try seal()
        consumed = true
        do { try c.save(); try boundary(.afterSave); try acknowledge(proof) }
        catch { let failure = error; c.rollback(); do { try acknowledge(proof) } catch { throw failure } }
    }
    private func acknowledge(_ proof: SharedMediaNativeAppOriginalPoststate) throws {
        try boundary(.beforeReadback)
        guard try authority.header(container) == proof.header else { throw SharedMediaStorageFailure.stale }
        let c = fresh(), id = facts.profile.inventoryID
        let inventory = try Rows.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        try proof.validateSaved(context: c, inventory: inventory)
        let r = proof.request, target = try audit(c, r.source.assetID)
        var expected = try originals.mapValues { try $0.atInventoryRevision(proof.header.inventory.revision) }
        let delta: Int64 = { if case .share = r.action { return 1 }; return -1 }()
        expected[r.source.assetID] = try r.original.atInventoryRevision(proof.header.inventory.revision,
            liveCount: r.original.liveCount + delta, countRevision: plus(r.original.countRevision), retirement: target.retirement)
        guard try Rows.originalFacts(c, facts: SharedMediaNativeAppMetadataFacts.capture(c, profile: facts.profile)) == expected else { throw SharedMediaStorageFailure.stale }
        _ = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inventory, ownerID: facts.profile.ownerID, format: .appV2)
    }
    #if DEBUG
    func setReleaseFault(_ fault: (@Sendable (SharedMediaPhotoReleaseBoundary) throws -> Void)?) async throws {
        try validate(); await io.setReleaseFault(fault); try validate()
    }
    #endif
    private func validate() throws {
        try Task.checkCancellation()
        guard !consumed, try authority.header(container) == header else { throw SharedMediaStorageFailure.stale }
    }
    private func audit(_ c: ModelContext, _ id: UUID) throws -> SharedMediaNativeOriginalAccounting.Snapshot {
        try SharedMediaNativeOriginalAccounting.audit(assetID: id, inventoryID: facts.profile.inventoryID, context: c)
    }
    private func fresh() -> ModelContext { let c = ModelContext(container); c.autosaveEnabled = false; return c }
    private func plus(_ value: Int64) throws -> Int64 { try SharedMediaStoragePolicy.add(value, 1) }
}

/// Only the audited app lifecycle can mint current physical-disposal authority.
struct SharedMediaNativeAppOriginalDisposalWitness: Sendable {
    let state: SharedMediaNativeRetirementState
    let binding: SharedMediaNativeBinding
    fileprivate init(state: SharedMediaNativeRetirementState, binding: SharedMediaNativeBinding) { self.state = state; self.binding = binding }
}

/// Closed typed write set. This proof cannot grant a generic dirty-context audit.
@MainActor
struct SharedMediaNativeAppOriginalPoststate {
    var predecessorRevision: Int64 { header.inventory.revision - 1 }
    typealias Rows = SharedMediaNativeAppOriginalRows
    let profile: SharedMediaNativeAppProfile
    let header: SharedMediaNativeAppEligibility.Header
    let request: SharedMediaNativeAppOriginalRequest
    private let facts: SharedMediaNativeAppMetadataFacts
    private let package: SharedMediaNativeAppMetadataFacts.Package
    private let member: SharedMediaNativeAppMetadataFacts.Member
    private let contextID: ObjectIdentifier, inventoryID: PersistentIdentifier
    private let inserts: Set<PersistentIdentifier>, updates: Set<PersistentIdentifier>, deletes: Set<PersistentIdentifier>

    fileprivate init(_ c: ModelContext, facts: SharedMediaNativeAppMetadataFacts, header: SharedMediaNativeAppEligibility.Header,
         rows: Rows, request: SharedMediaNativeAppOriginalRequest, package: SharedMediaNativeAppMetadataFacts.Package,
         member: SharedMediaNativeAppMetadataFacts.Member, retirement: SharedMediaNativeRetirementIdentity?,
         inserts: Set<PersistentIdentifier> = [], references: Set<PersistentIdentifier> = []) throws {
        self.facts = facts; profile = facts.profile; self.header = try SharedMediaNativeAppMetadataFacts.successor(header)
        self.request = request; self.package = package; self.member = member
        contextID = ObjectIdentifier(c); inventoryID = rows.inventory.persistentModelID; self.inserts = inserts
        try Self.validateRequest(request)
        switch request.action {
        case .share:
            guard inserts.count == 4, references.isEmpty, retirement == nil else { throw SharedMediaStorageFailure.conflict }
            updates = [inventoryID, rows.count.persistentModelID]; deletes = []
        case .remove:
            guard inserts.isEmpty, references.count == 2 else { throw SharedMediaStorageFailure.conflict }
            var changed: Set<PersistentIdentifier> = [inventoryID, rows.package.persistentModelID, rows.member.persistentModelID, rows.count.persistentModelID]
            if request.original.liveCount == 1 {
                guard let retirement, case .remove(let removal) = request.action,
                      retirement.retirementID == removal.retirementID else { throw SharedMediaStorageFailure.conflict }
                changed.formUnion(references); changed.formUnion([rows.asset.persistentModelID, rows.allocation.persistentModelID])
                deletes = []
            } else {
                guard retirement == nil else { throw SharedMediaStorageFailure.conflict }
                deletes = references
            }
            updates = changed
        }
    }
    func validate(context c: ModelContext, inventory: SharedMediaInventoryRecord) throws {
        guard ObjectIdentifier(c) == contextID, inventory.persistentModelID == inventoryID,
              Set(c.insertedModelsArray.map(\.persistentModelID)) == inserts,
              Set(c.deletedModelsArray.map(\.persistentModelID)) == deletes,
              Set(c.changedModelsArray.map(\.persistentModelID)).subtracting(inserts).subtracting(deletes) == updates else { throw SharedMediaStorageFailure.conflict }
        try validateSaved(context: c, inventory: inventory)
    }
    func validateSaved(context c: ModelContext, inventory: SharedMediaInventoryRecord) throws {
        guard try SharedMediaNativeAppEligibility.profile(inventory) == profile,
              inventory.revision == header.inventory.revision else { throw SharedMediaStorageFailure.conflict }
        switch request.action {
        case .share:
            try facts.validateAcquisition(c, packageID: package.id, hasMember: true)
            try Self.validateShare(c, request: request)
        case .remove:
            try facts.validatePairPlan(c, package: package, member: member)
            try Self.validateRemoval(c, request: request)
        }
    }
    func receivingBytes(_ consumer: SharedMediaConsumerRecord) throws -> Int64 { try facts.receivingBytes(consumer) }

    static func validateRequest(_ r: SharedMediaNativeAppOriginalRequest) throws {
        try r.source.validate()
        guard r.source.ownerID == r.profile.ownerID, r.package.id == r.source.packageID, r.member.id == r.source.packageID,
              r.package.ownerID == r.profile.ownerID, r.package.generation == r.source.draftGeneration,
              r.member.inventoryID == r.profile.inventoryID, r.member.inventoryGeneration == r.profile.generation,
              r.member.ownerID == r.profile.ownerID, r.member.draftGeneration == r.source.draftGeneration,
              r.original.assetID == r.source.assetID, r.original.assetGeneration == r.source.assetGeneration,
              r.original.inventoryID == r.profile.inventoryID, r.original.inventoryGeneration == r.profile.generation,
              r.original.ownerID == r.profile.ownerID, r.original.liveCount > 0, r.original.retirement == nil,
              r.package.phase == "draftOwned", r.package.tier == "pending", !r.package.retiring,
              [r.package.revision, r.member.revision, r.original.countRevision, r.original.liveCount].allSatisfy({ $0 >= 0 && $0 < Int64.max }),
              (0..<2).contains(r.ordinal) else { throw SharedMediaStorageFailure.stale }
        switch r.action {
        case .share(let s):
            let envelope = try PhotoPreparationPolicy.decodeDraft(s.envelope)
            guard s.source == r.source, s.inventoryID == r.profile.inventoryID, s.inventoryGeneration == r.profile.generation,
                  s.inventoryRevision == r.original.inventoryRevision, s.sourcePackageRevision == r.package.revision,
                  s.liveCount == r.original.liveCount, s.countRevision == r.original.countRevision,
                  s.packageID != r.source.packageID, envelope.contexts.isEmpty, envelope.presentation.isEmpty else { throw SharedMediaStorageFailure.conflict }
        case .remove(let d):
            let before = try SharedMediaNativeDraftEnvelope.decode(r.package.envelope)
            let next = try SharedMediaNativeDraftEnvelope.decode(d.envelope)
            try before.validateMetadataTransition(to: d.envelope)
            guard d.source == r.source, d.inventoryID == r.profile.inventoryID, d.inventoryGeneration == r.profile.generation,
                  d.inventoryRevision == r.original.inventoryRevision, d.packageRevision == r.package.revision,
                  d.membershipRevision == r.member.revision, d.membershipBytes == r.member.bytes,
                  d.previousEnvelope == r.package.envelope, d.liveCount == r.original.liveCount, d.countRevision == r.original.countRevision,
                  next.contexts == before.contexts,
                  try SharedMediaNativeDraftEnvelope.bytes(next.presentation) == SharedMediaNativeDraftEnvelope.bytes(
                    before.presentation.filter { $0.referenceID != r.source.referenceID }) else { throw SharedMediaStorageFailure.conflict }
        }
    }
    static func validateShare(_ c: ModelContext, request r: SharedMediaNativeAppOriginalRequest) throws {
        try validateRequest(r)
        guard case .share(let s) = r.action else { throw SharedMediaStorageFailure.conflict }
        let rows = try Rows(c, profile: r.profile, source: r.source), destination = try s.destination(), id = destination.packageID
        try noConsumer(c, r.source.packageID); try noConsumer(c, id)
        guard SharedMediaNativeAppMetadataFacts.Package(rows.package) == r.package,
              SharedMediaNativeAppMetadataFacts.Member(rows.member) == r.member else { throw SharedMediaStorageFailure.stale }
        _ = try Rows.reference(c, source: r.source, live: true, ordinal: r.ordinal)
        _ = try Rows.reference(c, source: destination, live: true, ordinal: 0)
        let package = try Rows.one(c, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id }))
        let member = try Rows.one(c, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
        guard package.ownerID == r.profile.ownerID, package.draftID == id, package.draftGeneration == destination.draftGeneration,
              package.contractVersion == PhotoPreparationPolicy.contract, package.accountingTierRaw == "pending",
              package.phaseRaw == "draftOwned", !package.retirementRequested, package.revision == 0,
              package.supportingContextData == s.envelope, package.allocatedByteCount == r.original.byteCount,
              member.inventoryID == r.profile.inventoryID, member.inventoryGeneration == r.profile.generation,
              member.ownerID == r.profile.ownerID, member.draftGeneration == destination.draftGeneration, member.revision == 0,
              member.membersData == (try Rows.shareMembership(destination, leaseID: r.original.leaseID)) else { throw SharedMediaStorageFailure.stale }
        try original(rows, expected: r.original, count: SharedMediaStoragePolicy.add(r.original.liveCount, 1), retirement: nil)
    }
    static func validateRemoval(_ c: ModelContext, request r: SharedMediaNativeAppOriginalRequest) throws {
        try validateRequest(r)
        guard case .remove(let removal) = r.action else { throw SharedMediaStorageFailure.conflict }
        let rows = try Rows(c, profile: r.profile, source: r.source)
        try noConsumer(c, r.source.packageID); try Rows.noPair(c, source: r.source)
        let final = r.original.liveCount == 1
        let expectedPackage = try r.package.successor(removal.envelope, allocated: final ? r.package.allocated : r.package.allocated - r.original.byteCount)
        let expectedBytes: Data, retirement: SharedMediaNativeRetirementIdentity?
        if final {
            _ = try Rows.reference(c, source: r.source, live: false, ordinal: r.ordinal)
            expectedBytes = r.member.bytes
            retirement = try .init(retirementID: removal.retirementID, assetID: r.source.assetID, assetGeneration: r.source.assetGeneration,
                inventoryID: r.profile.inventoryID, inventoryGeneration: r.profile.generation, ownerID: r.profile.ownerID,
                proof: rows.completed().1.descriptor)
        } else {
            try Rows.absentReference(c, r.source.referenceID)
            let packageID = r.source.packageID, assetID = r.source.assetID
            let remaining = try c.fetchCount(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.packageID == packageID && $0.assetID == assetID }))
            expectedBytes = try SharedMediaNativeLifecycleMembership.removing(r.member.bytes, referenceID: r.source.referenceID,
                assetID: assetID, leaseID: r.original.leaseID, removeAsset: remaining == 0)
            retirement = nil
        }
        guard SharedMediaNativeAppMetadataFacts.Package(rows.package) == expectedPackage,
              SharedMediaNativeAppMetadataFacts.Member(rows.member) == (try r.member.successor(expectedBytes)) else { throw SharedMediaStorageFailure.stale }
        try original(rows, expected: r.original, count: r.original.liveCount - 1, retirement: retirement)
    }
    private static func noConsumer(_ c: ModelContext, _ packageID: UUID) throws {
        guard try SharedMediaConsumerLookup.one(c, packageID: packageID) == nil else { throw SharedMediaStorageFailure.closed }
    }
    private static func original(_ rows: Rows, expected: SharedMediaNativeOriginalAccounting.Snapshot,
                                 count: Int64, retirement: SharedMediaNativeRetirementIdentity?) throws {
        let identity = try retirement?.encoded() ?? expected.physicalIdentity
        guard rows.asset.generation == expected.assetGeneration, rows.asset.ownerID == expected.ownerID,
              rows.asset.fileToken == expected.fileToken, rows.asset.byteCount == expected.byteCount,
              rows.asset.sha256 == expected.sha256, rows.asset.contentType == expected.contentType,
              rows.asset.cleanupStateRaw == (retirement == nil ? "ready" : "retiring"),
              rows.allocation.inventoryID == expected.inventoryID, rows.allocation.accountID == expected.ownerID,
              rows.allocation.namespaceRaw == SharedMediaPhotoLedger.namespace, rows.allocation.poolRaw == "durable",
              rows.allocation.materializedBytes == expected.byteCount, rows.allocation.reservedBytes == 0,
              rows.allocation.fileToken == expected.fileToken, rows.allocation.physicalIdentity == identity,
              rows.allocation.stateRaw == (retirement == nil ? "p1Materialized" : SharedMediaNativeRetirementIdentity.allocationState),
              rows.lease.id == expected.leaseID, rows.lease.processEpoch == expected.leaseEpoch,
              rows.lease.purposeRaw == "p1AcquireV1", rows.lease.stateRaw == "closed",
              rows.count.inventoryID == expected.inventoryID, rows.count.inventoryGeneration == expected.inventoryGeneration,
              rows.count.assetGeneration == expected.assetGeneration, rows.count.ownerID == expected.ownerID,
              rows.count.liveCount == count, rows.count.revision == (try SharedMediaStoragePolicy.add(expected.countRevision, 1)),
              rows.count.retirementID == retirement?.retirementID else { throw SharedMediaStorageFailure.stale }
        _ = try rows.completed()
    }
}

/// Six physical/reference deletions plus the exact four accounting/receipt
/// updates. A stripped acquisition receipt is never removal-replay authority.
@MainActor
struct SharedMediaNativeAppOriginalReleasePoststate {
    var predecessorRevision: Int64 { state.inventoryRevision }
    typealias Rows = SharedMediaNativeAppOriginalRows
    let profile: SharedMediaNativeAppProfile
    let header: SharedMediaNativeAppEligibility.Header
    private let facts: SharedMediaNativeAppMetadataFacts
    private let state: SharedMediaNativeRetirementState
    var assetID: UUID { state.file.assetID }
    private let package: SharedMediaNativeAppMetadataFacts.Package
    private let member: SharedMediaNativeAppMetadataFacts.Member
    private let contextID: ObjectIdentifier, inventoryID: PersistentIdentifier
    private let updates: Set<PersistentIdentifier>, deletes: Set<PersistentIdentifier>

    fileprivate init(_ c: ModelContext, facts: SharedMediaNativeAppMetadataFacts, header: SharedMediaNativeAppEligibility.Header,
         rows: Rows, state: SharedMediaNativeRetirementState) throws {
        self.facts = facts; profile = facts.profile; self.header = try SharedMediaNativeAppMetadataFacts.successor(header); self.state = state
        contextID = ObjectIdentifier(c); inventoryID = rows.inventory.persistentModelID
        guard let old = facts.packages[state.reference.packageID], let oldMember = facts.members[state.reference.packageID],
              old.revision == state.packageRevision, oldMember.revision == state.membershipRevision,
              old.envelope == state.envelope, oldMember.bytes == state.membershipBytes,
              state.request.operationID == rows.receipt.id, state.request.operationID == rows.lease.id,
              rows.count.liveCount == 0, rows.count.revision == state.countRevision,
              rows.count.retirementID == state.identity.retirementID else { throw SharedMediaStorageFailure.conflict }
        let (ref, edge) = try Rows.reference(c, source: state.reference, live: false)
        package = try old.successor(old.envelope, allocated: old.allocated - state.file.byteCount)
        guard package.allocated >= 0 else { throw SharedMediaStorageFailure.conflict }
        member = try oldMember.successor(SharedMediaNativeLifecycleMembership.removing(oldMember.bytes,
            referenceID: state.reference.referenceID, assetID: state.file.assetID, leaseID: rows.lease.id, removeAsset: true))
        updates = [inventoryID, rows.package.persistentModelID, rows.member.persistentModelID, rows.receipt.persistentModelID]
        deletes = [ref.persistentModelID, edge.persistentModelID, rows.asset.persistentModelID,
            rows.allocation.persistentModelID, rows.count.persistentModelID, rows.lease.persistentModelID]
    }
    func apply(_ c: ModelContext, rows: Rows) throws {
        guard ObjectIdentifier(c) == contextID, rows.inventory.persistentModelID == inventoryID else { throw SharedMediaStorageFailure.conflict }
        let (ref, edge) = try Rows.reference(c, source: state.reference, live: false)
        c.delete(ref); c.delete(edge); c.delete(rows.asset); c.delete(rows.allocation); c.delete(rows.count); c.delete(rows.lease)
        rows.receipt.phaseRaw = "terminal"; rows.receipt.revision = 2; rows.receipt.terminalOutcomeRaw = "released"
        rows.receipt.requestData = nil; rows.receipt.resultData = nil; rows.receipt.packageID = nil; rows.receipt.assetID = nil
        rows.package.allocatedByteCount = package.allocated; rows.package.revision = package.revision
        rows.member.membersData = member.bytes; rows.member.revision = member.revision; rows.inventory.revision = header.inventory.revision
    }
    func validate(context c: ModelContext, inventory: SharedMediaInventoryRecord) throws {
        guard ObjectIdentifier(c) == contextID, inventory.persistentModelID == inventoryID,
              c.insertedModelsArray.isEmpty, Set(c.deletedModelsArray.map(\.persistentModelID)) == deletes,
              Set(c.changedModelsArray.map(\.persistentModelID)).subtracting(deletes) == updates else { throw SharedMediaStorageFailure.conflict }
        try validateSaved(context: c, inventory: inventory)
    }
    func validateSaved(context c: ModelContext, inventory: SharedMediaInventoryRecord) throws {
        guard try SharedMediaNativeAppEligibility.profile(inventory) == profile,
              inventory.revision == header.inventory.revision else { throw SharedMediaStorageFailure.conflict }
        try facts.validatePairPlan(c, package: package, member: member)
        let id = state.request.operationID, assetID = state.file.assetID
        let receipt = try Rows.one(c, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id }))
        guard case .released = try SharedMediaAcquisitionReceipt.read(receipt, expected: state.request),
              try c.fetchCount(FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID })) == 0,
              try c.fetchCount(FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == assetID })) == 0,
              try c.fetchCount(FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID })) == 0,
              try c.fetchCount(FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.allocationID == assetID })) == 0,
              try c.fetchCount(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.assetID == assetID })) == 0,
              try c.fetchCount(FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.allocationID == assetID })) == 0,
              try c.fetchCount(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.assetID == assetID })) == 0 else { throw SharedMediaStorageFailure.conflict }
    }
    func receivingBytes(_ consumer: SharedMediaConsumerRecord) throws -> Int64 { try facts.receivingBytes(consumer) }
}
