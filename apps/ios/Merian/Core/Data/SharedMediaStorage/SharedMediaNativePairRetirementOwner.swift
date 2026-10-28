import Foundation
import SwiftData

/// Exact saved closure precedes file disposal; final absence precedes release.
/// Qualification and app callers share row mechanics, never mutation authority.
@MainActor
final class SharedMediaNativePairRetirementOwner {
    @MainActor private enum Authority {
        case qualification(SharedMediaNativeMutationAuthority), app(SharedMediaNativeAppPairRetirementWitness)
        var binding: SharedMediaNativeBinding {
            switch self { case .qualification(let value): return value.binding; case .app(let value): return value.binding }
        }
        func validate(_ container: ModelContainer) throws {
            switch self { case .qualification(let value): try value.validate(); case .app(let value): try value.validate(container) }
        }
    }
    private let container: ModelContainer, context: ModelContext
    private let authority: Authority
    private let inventory: SharedMediaInventoryRecord, package: PhotoPreparationRecord
    private let member: SharedMediaPendingMembershipRecord, pair: SharedMediaDerivativePairRecord
    private let before: SharedMediaNativePairFileState
    private var consumed = false, applying = false
    private var appClosure: SharedMediaNativePairClosure?

    convenience init(container: ModelContainer, inventoryID: UUID, packageID: UUID,
                     authority: SharedMediaNativeMutationAuthority, pairID: UUID) throws {
        try self.init(container: container, inventoryID: inventoryID, packageID: packageID, authority: .qualification(authority), pairID: pairID)
    }
    convenience init(container: ModelContainer, witness: SharedMediaNativeAppPairRetirementWitness) throws {
        try self.init(container: container, inventoryID: witness.state.plan.inventoryID,
            packageID: witness.state.plan.packageID, authority: .app(witness), pairID: witness.state.intent().pairID)
    }
    private init(container: ModelContainer, inventoryID: UUID, packageID: UUID, authority: Authority, pairID: UUID) throws {
        try authority.validate(container)
        self.container = container; self.authority = authority
        context = ModelContext(container); context.autosaveEnabled = false
        inventory = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        package = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        member = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        if case .qualification(let value) = authority {
            guard !value.binding.initializing, package.ownerID == value.ownerID,
                  value.binding.bytes == (try JSONEncoder().encode(["nativeQualificationV1", inventory.id.uuidString, inventory.storeIdentity, inventory.rootIdentity])) else { throw SharedMediaStorageFailure.closed }
            try SharedMediaNativeAcquisitionGraph.audit(context: context, inventoryID: inventoryID)
        }
        before = try SharedMediaNativePairFileGraph.state(context: context, inventory: inventory, package: package, member: member, pairID: pairID)
        pair = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == pairID }))
    }
    func state() -> SharedMediaNativePairFileState { before }
    func applyApp(beforeSave: () throws -> Void, afterSave: () throws -> Void) throws -> SharedMediaNativePairFileState? {
        guard case .app(let witness) = authority, !consumed else { throw SharedMediaStorageFailure.closed }
        consumed = true; applying = true; defer { applying = false }
        switch witness.action {
        case .retire(let proofs): return try retire(before, proofs: proofs, beforeSave: beforeSave, afterSave: afterSave)
        case .release(let proofs): try release(proofs, beforeSave: beforeSave, afterSave: afterSave); return nil
        case .inspect: throw SharedMediaStorageFailure.closed
        }
    }
    private func requireAppEntry() throws {
        if case .app = authority, !applying { throw SharedMediaStorageFailure.closed }
    }
    func requireRetirementAdmission() throws {
        if case .app(let witness) = authority {
            try witness.validate(container)
            guard case .preparation(let envelope) = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData),
                  envelope.attempt == nil, envelope.frozen == nil else { throw SharedMediaStorageFailure.closed }
            return
        }
        if before.phase == "ready" {
            guard case .preparation(let envelope) = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData),
                  envelope.frozen == nil else { throw SharedMediaStorageFailure.closed }
            try SharedMediaNativePreparationGraph.requireNoUnfinished(context)
            // Ready pairs own no lease. Any remaining lease belongs to an
            // unfinished acquisition or another lifecycle and must settle first.
            guard try context.fetchCount(FetchDescriptor<PhotoPreparationLease>()) == 0 else { throw SharedMediaStorageFailure.closed }
        }
    }

    func retire(_ expected: SharedMediaNativePairFileState, proofs: [SharedMediaNativePairInspection],
                beforeSave: () throws -> Void, afterSave: () throws -> Void) throws -> SharedMediaNativePairFileState {
        try requireAppEntry()
        guard expected == before, ["writing", "ready"].contains(before.phase), proofs.count == 2,
              Set(proofs.map(\.workID)) == Set(before.work.map(\.id)) else { throw SharedMediaStorageFailure.stale }
        try requireRetirementAdmission()
        let entries = try before.work.map { work -> SharedMediaNativePairClosure.Entry in
            guard let proof = proofs.first(where: { $0.workID == work.id }), proof.state == before else { throw SharedMediaStorageFailure.conflict }
            try binding(proof.binding, proof.epoch)
            let mode: SharedMediaNativePairClosure.Mode = work.device != nil ? .bound : proof.identity.partial == "absent" ? .unboundAbsent : .unboundPartial
            return .init(work: work, mode: mode, identity: proof.identity)
        }
        let afterMembership = try SharedMediaNativePairClosure.retirementMembership(before)
        let closure = SharedMediaNativePairClosure(version: 1, retirementID: UUID(), pairID: pair.id,
            inventoryID: inventory.id, inventoryGeneration: inventory.generation, packageID: package.id,
            draftGeneration: package.draftGeneration, writerEpoch: before.plan.writerEpoch,
            beforeHash: SharedMediaNativePairClosure.digest(try SharedMediaNativeDraftEnvelope.bytes(before)),
            intentHash: SharedMediaNativePairClosure.digest(before.plan.intent.bytes),
            envelopeHash: SharedMediaNativePairClosure.digest(before.plan.envelope),
            afterMembershipHash: SharedMediaNativePairClosure.digest(afterMembership),
            afterMembershipRevision: try SharedMediaStoragePolicy.add(member.revision, afterMembership == member.membersData ? 0 : 1),
            previous: .init(inventoryRevision: inventory.revision, packageRevision: package.revision,
                membershipRevision: member.revision, membership: member.membersData, phase: before.phase,
                publishedRevision: before.publishedRevision, allocatedBytes: package.allocatedByteCount), entries: entries)
        appClosure = closure
        try SharedMediaNativePairRetirementRows.apply(context: context, package: package, pair: pair,
            before: before, closure: closure)
        package.phaseRaw = "needsAttention"
        try advance(); return try save(beforeSave, afterSave)
    }

    /// Only this fenced owner mints disposal after exact persisted readback.
    func disposal(_ expected: SharedMediaNativePairFileState) throws -> SharedMediaNativePairDisposal {
        if case .app(let witness) = authority {
            guard case .inspect = witness.action, !consumed else { throw SharedMediaStorageFailure.closed }
            consumed = true
        }
        guard expected == before, before.phase == "retiring" else { throw SharedMediaStorageFailure.stale }
        try authority.validate(container)
        return .init(state: before, binding: authority.binding.bytes, epoch: authority.binding.epoch)
    }

    func release(_ proofs: [SharedMediaNativePairAbsence], beforeSave: () throws -> Void, afterSave: () throws -> Void) throws {
        try requireAppEntry()
        guard before.phase == "retiring", proofs.count == 2, Set(proofs.map(\.workID)) == Set(before.work.map(\.id)) else { throw SharedMediaStorageFailure.stale }
        for proof in proofs {
            try binding(proof.binding, proof.epoch)
            guard proof.state == before else { throw SharedMediaStorageFailure.stale }
        }
        try SharedMediaNativePairRemovalRows.apply(context: context, package: package, pair: pair, before: before)
        guard case .preparation(let envelope) = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData) else { throw SharedMediaStorageFailure.conflict }
        package.supportingContextData = try SharedMediaNativeDraftEnvelope.V2(version: 2, contexts: envelope.contexts,
            presentation: envelope.presentation, sequence: envelope.sequence, attempt: nil, intents: envelope.intents.filter { $0 != before.plan.intent }, frozen: nil).encoded()
        package.phaseRaw = "draftOwned"; try advance()
        if case .app(let witness) = authority {
            _ = try saveApp(witness, beforeSave, afterSave); return
        }
        _ = try SharedMediaNativeAcquisitionBudget.evaluate(context: context, inventory: inventory)
        let expected = try releaseWitness(context)
        try beforeSave(); try authority.validate(container)
        guard try fresh().before == before else { throw SharedMediaStorageFailure.stale }
        func result() throws -> Data {
            let fresh = ModelContext(container); fresh.autosaveEnabled = false
            try SharedMediaNativeAcquisitionGraph.audit(context: fresh, inventoryID: inventory.id)
            return try releaseWitness(fresh)
        }
        do { try context.save(); try afterSave() }
        catch {
            let failure = error; context.rollback()
            guard (try? result()) == expected else { throw failure }
        }
        guard try result() == expected else { throw SharedMediaStorageFailure.stale }
    }

    private func releaseWitness(_ queryContext: ModelContext) throws -> Data {
        let inventoryID = inventory.id, packageID = package.id
        let inv = try SharedMediaNativePairPlanGraph.one(queryContext, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let pkg = try SharedMediaNativePairPlanGraph.one(queryContext, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        let mem = try SharedMediaNativePairPlanGraph.one(queryContext, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        return try SharedMediaNativeDraftEnvelope.bytes([inv.generation.uuidString, String(inv.revision), pkg.id.uuidString,
            pkg.draftGeneration.uuidString, String(pkg.revision), pkg.phaseRaw, String(pkg.allocatedByteCount),
            pkg.supportingContextData.base64EncodedString(), String(mem.revision), mem.membersData.base64EncodedString()])
    }

    private func rows(_ id: UUID) throws -> (SharedMediaDerivativeWorkRecord, SharedMediaDerivativeInput) {
        let (_, input) = try before.selected(id)
        return (try one(FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == id })), input)
    }
    private func one<T: PersistentModel>(_ query: FetchDescriptor<T>) throws -> T { try SharedMediaNativePairPlanGraph.one(context, query) }
    private func binding(_ bytes: Data, _ epoch: UUID) throws {
        try authority.validate(container)
        guard bytes == authority.binding.bytes, epoch == authority.binding.epoch else { throw SharedMediaStorageFailure.closed }
    }
    private func advance() throws {
        inventory.revision = try SharedMediaStoragePolicy.add(inventory.revision, 1)
        package.revision = try SharedMediaStoragePolicy.add(package.revision, 1)
        let bytes: Data
        if case .app(let witness) = authority { bytes = try SharedMediaNativeAppPairRetirementPoststate.membership(witness) }
        else { bytes = try SharedMediaPendingGraph.derive(in: context, inventory: inventory).membership(packageID: package.id).encoded() }
        if member.membersData != bytes { member.membersData = bytes; member.revision = try SharedMediaStoragePolicy.add(member.revision, 1) }
    }
    private func fresh() throws -> SharedMediaNativePairRetirementOwner {
        guard case .qualification(let value) = authority else { throw SharedMediaStorageFailure.closed }
        return try .init(container: container, inventoryID: inventory.id, packageID: package.id, authority: value, pairID: pair.id)
    }
    private func save(_ beforeSave: () throws -> Void, _ afterSave: () throws -> Void) throws -> SharedMediaNativePairFileState {
        if case .app(let witness) = authority {
            guard let state = try saveApp(witness, beforeSave, afterSave) else { throw SharedMediaStorageFailure.conflict }; return state
        }
        let expected = try SharedMediaNativePairFileGraph.state(context: context, inventory: inventory, package: package, member: member, pairID: pair.id)
        _ = try SharedMediaNativeAcquisitionBudget.evaluate(context: context, inventory: inventory)
        try beforeSave(); try authority.validate(container)
        guard try fresh().before == before else { throw SharedMediaStorageFailure.stale }
        do { try context.save(); try afterSave() }
        catch {
            let failure = error; context.rollback()
            guard (try? fresh().before) == expected else { throw failure }
        }
        guard try fresh().before == expected else { throw SharedMediaStorageFailure.stale }; return expected
    }
    private func saveApp(_ witness: SharedMediaNativeAppPairRetirementWitness, _ beforeSave: () throws -> Void,
                         _ afterSave: () throws -> Void) throws -> SharedMediaNativePairFileState? {
        let proof = try SharedMediaNativeAppPairRetirementPoststate(context: context, inventory: inventory,
            package: package, member: member, witness: witness, closure: appClosure)
        func budget() throws {
            _ = try SharedMediaNativeAcquisitionBudget.evaluatePairRetirementPoststate(context: context, inventory: inventory, proof: proof)
        }
        try budget(); try beforeSave(); try witness.validate(container); try budget(); try witness.seal()
        func acknowledge() throws -> SharedMediaNativePairFileState? {
            try witness.beforeReadback()
            guard try witness.preparation.authority.header(container) == SharedMediaNativeAppMetadataFacts.successor(witness.preparation.expected) else { throw SharedMediaStorageFailure.stale }
            let read = ModelContext(container); read.autosaveEnabled = false
            try proof.validateSaved(read)
            let id = inventory.id
            let inv = try SharedMediaNativePairPlanGraph.one(read, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
            _ = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: read, inventory: inv, ownerID: proof.profile.ownerID, format: .appV2)
            return proof.expected
        }
        do { try context.save(); try afterSave() }
        catch { let failure = error; context.rollback(); do { return try acknowledge() } catch { throw failure } }
        return try acknowledge()
    }
}

struct SharedMediaNativePairDisposal: Sendable {
    let state: SharedMediaNativePairFileState
    let binding: Data
    let epoch: UUID
    private let heldPermit: SharedMediaNativePairUnlinkPermit?
    @MainActor static func held(_ capability: SharedMediaNativeReleasePairRemovalCapability) throws -> Self {
        try capability.requireDisposal()
        return .init(state: capability.state, binding: capability.binding.bytes, epoch: capability.binding.epoch, heldPermit: capability.permit)
    }
    fileprivate init(state: SharedMediaNativePairFileState, binding: Data, epoch: UUID, heldPermit: SharedMediaNativePairUnlinkPermit? = nil) {
        self.state = state; self.binding = binding; self.epoch = epoch; self.heldPermit = heldPermit
    }
    /// The held permit cannot be stripped by routing through ordinary release.
    /// Its fileprivate constructor is the only place this distinction is set.
    func withCurrent<T>(workID: UUID, body: () throws -> T) throws -> T {
        if let heldPermit { return try heldPermit.withCurrent(self, workID: workID, body: body) }
        return try body()
    }
}


/// Only this owner can mint a dirty projection. No generic mutation callback or
/// unscoped accounting bypass is exposed to retirement callers.
@MainActor
struct SharedMediaNativeAppPairRetirementPoststate {
    var allocationPeers: [UUID: SharedMediaNativePhotoAllocationPeer] { witness.preparation.facts.allocationPeers }
    var predecessorRevision: Int64 { witness.state.plan.inventoryRevision }
    let profile: SharedMediaNativeAppProfile
    let expected: SharedMediaNativePairFileState?
    private let witness: SharedMediaNativeAppPairRetirementWitness
    private let contextID: ObjectIdentifier, inventoryID: PersistentIdentifier
    private let updates: Set<PersistentIdentifier>, inserts: Set<PersistentIdentifier>, deletes: Set<PersistentIdentifier>
    private let package: SharedMediaNativeAppMetadataFacts.Package
    private let member: SharedMediaNativeAppMetadataFacts.Member
    private let released: Bool

    fileprivate init(context: ModelContext, inventory: SharedMediaInventoryRecord, package row: PhotoPreparationRecord,
                     member: SharedMediaPendingMembershipRecord, witness: SharedMediaNativeAppPairRetirementWitness,
                     closure: SharedMediaNativePairClosure?) throws {
        self.witness = witness; profile = witness.preparation.authority.profile
        contextID = ObjectIdentifier(context); inventoryID = inventory.persistentModelID
        let before = witness.state, intent = try before.intent(), facts = witness.preparation.facts
        guard let old = facts.packages[row.id], let oldMember = facts.members[row.id], old.envelope == before.plan.envelope,
              oldMember.bytes == before.plan.membership, old.allocated == before.allocatedBytes else { throw SharedMediaStorageFailure.conflict }
        let bytes = try Self.membership(witness)
        self.member = bytes == oldMember.bytes ? oldMember : try oldMember.successor(bytes)
        var changed: Set<PersistentIdentifier> = [inventory.persistentModelID, row.persistentModelID]
        if bytes != oldMember.bytes { changed.insert(member.persistentModelID) }
        var added = Set<PersistentIdentifier>(), removed = Set<PersistentIdentifier>()
        func one<T: PersistentModel>(_ q: FetchDescriptor<T>) throws -> T { try SharedMediaNativePairPlanGraph.one(context, q) }
        switch witness.action {
        case .retire:
            released = false
            guard let closure, closure.previous.phase == before.phase,
                  closure.beforeHash == SharedMediaNativePairClosure.digest(try SharedMediaNativeDraftEnvelope.bytes(before)) else { throw SharedMediaStorageFailure.conflict }
            let id = intent.pairID
            changed.insert(try one(FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == id })).persistentModelID)
            for input in [intent.ai, intent.display] {
                let id = input.id, asset = input.assetID, lease = input.leaseID, reference = input.referenceID
                changed.insert(try one(FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == id })).persistentModelID)
                changed.insert(try one(FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == asset })).persistentModelID)
                let local = try one(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == lease })).persistentModelID
                let shared = try one(FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == lease })).persistentModelID
                if before.phase == "ready" { added.formUnion([local, shared]) }
                else {
                    changed.insert(local)
                    if try before.selected(id).0.finalIdentity == nil { changed.insert(shared) }
                }
                if try before.selected(id).0.finalIdentity != nil {
                    changed.insert(try one(FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == asset })).persistentModelID)
                    changed.insert(try one(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == reference })).persistentModelID)
                    changed.insert(try one(FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == reference })).persistentModelID)
                    changed.insert(try one(FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == asset })).persistentModelID)
                }
            }
            package = try old.successor(old.envelope, phase: "needsAttention")
            let plan = before.plan
            let next = SharedMediaNativePairPlan(intent: plan.intent, writerEpoch: plan.writerEpoch, inventoryID: plan.inventoryID,
                inventoryGeneration: plan.inventoryGeneration, inventoryRevision: try SharedMediaStoragePolicy.add(plan.inventoryRevision, 1),
                packageID: plan.packageID, draftGeneration: plan.draftGeneration, packageRevision: package.revision,
                envelope: plan.envelope, membershipRevision: self.member.revision, membership: bytes)
            expected = .init(plan: next, phase: "retiring", publishedRevision: nil, allocatedBytes: old.allocated,
                work: try before.work.map { work in
                    guard let entry = closure.entries.first(where: { $0.work == work }) else { throw SharedMediaStorageFailure.conflict }
                    return .init(id: work.id, writerEpoch: work.writerEpoch, phase: "retiring", writerState: "closed",
                        device: work.device, inode: work.inode, finalIdentity: work.finalIdentity, retirementID: closure.retirementID,
                        retirementPartial: entry.identity.partial, retirementFinal: entry.identity.final,
                        retirementParent: entry.identity.parent, retirementNamespace: entry.identity.namespace,
                        closure: work.id == intent.ai.id ? try closure.encoded() : try closure.siblingMarker())
                })
        case .release:
            released = true; expected = nil
            guard closure == nil, case .preparation(let envelope) = try SharedMediaNativeDraftEnvelope.decode(old.envelope),
                  envelope.attempt == nil, envelope.frozen == nil, envelope.intents.filter({ $0 == before.plan.intent }).count == 1 else { throw SharedMediaStorageFailure.conflict }
            let encoded = try SharedMediaNativeDraftEnvelope.V2(version: 2, contexts: envelope.contexts, presentation: envelope.presentation,
                sequence: envelope.sequence, attempt: nil, intents: envelope.intents.filter { $0 != before.plan.intent }, frozen: nil).encoded()
            let releasedBytes = try before.work.filter { $0.finalIdentity != nil }.reduce(Int64(0)) {
                try SharedMediaStoragePolicy.add($0, before.selected($1.id).1.byteCount)
            }
            guard old.allocated >= releasedBytes else { throw SharedMediaStorageFailure.conflict }
            package = try old.successor(encoded, phase: "draftOwned", allocated: old.allocated - releasedBytes)
            let all = context.deletedModelsArray
            func deleted<T: PersistentModel>(_ type: T.Type, ids: Set<UUID>, id: KeyPath<T, UUID>) throws {
                let rows = all.compactMap { $0 as? T }
                guard rows.count == ids.count, Set(rows.map { $0[keyPath: id] }) == ids else { throw SharedMediaStorageFailure.conflict }
                removed.formUnion(rows.map(\.persistentModelID))
            }
            let inputs = [intent.ai, intent.display]
            let completed = try inputs.filter { try before.selected($0.id).0.finalIdentity != nil }
            try deleted(SharedMediaDerivativePairRecord.self, ids: [intent.pairID], id: \.id)
            try deleted(SharedMediaDerivativeWorkRecord.self, ids: Set(inputs.map(\.id)), id: \.id)
            try deleted(SharedMediaAllocationRecord.self, ids: Set(inputs.map(\.assetID)), id: \.id)
            try deleted(PhotoPreparationLease.self, ids: Set(inputs.map(\.leaseID)), id: \.id)
            try deleted(SharedMediaLeaseRecord.self, ids: Set(inputs.map(\.leaseID)), id: \.id)
            try deleted(PhotoPreparationAsset.self, ids: Set(completed.map(\.assetID)), id: \.id)
            try deleted(PhotoPreparationReference.self, ids: Set(completed.map(\.referenceID)), id: \.id)
            try deleted(SharedMediaReferenceRecord.self, ids: Set(completed.map(\.referenceID)), id: \.id)
            try deleted(SharedMediaAssetReferenceCountRecord.self, ids: Set(completed.map(\.assetID)), id: \.id)
        case .inspect: throw SharedMediaStorageFailure.closed
        }
        updates = changed; inserts = added; deletes = removed
        try validate(context: context, inventory: inventory)
    }
    fileprivate static func membership(_ witness: SharedMediaNativeAppPairRetirementWitness) throws -> Data {
        switch witness.action {
        case .retire: return try SharedMediaNativePairClosure.retirementMembership(witness.state)
        case .inspect: throw SharedMediaStorageFailure.closed
        case .release: break
        }
        let before = witness.state, intent = try before.intent()
        var groups = Dictionary(uniqueKeysWithValues: try SharedMediaMembership.decode(before.plan.membership).groups.map { ($0.kind, Set($0.ids)) })
        func remove(_ kind: SharedMediaMembership.Kind, _ id: UUID) throws {
            guard groups[kind, default: []].remove(id) != nil else { throw SharedMediaStorageFailure.conflict }
        }
        try remove(.pair, intent.pairID)
        for input in [intent.ai, intent.display] {
            try remove(.derivative, input.id); try remove(.allocation, input.assetID)
            try remove(.work, input.leaseID); try remove(.lease, input.leaseID)
            if try before.selected(input.id).0.finalIdentity != nil {
                try remove(.asset, input.assetID); try remove(.reference, input.referenceID); try remove(.edge, input.referenceID)
            }
        }
        return try SharedMediaMembership(groups: groups.filter { !$0.value.isEmpty }.map { kind, ids in
            .init(kind: kind, ids: ids.sorted { $0.uuidString < $1.uuidString })
        }.sorted { $0.kind.rawValue < $1.kind.rawValue }).encoded()
    }
    func validate(context: ModelContext, inventory: SharedMediaInventoryRecord) throws {
        guard ObjectIdentifier(context) == contextID, inventory.persistentModelID == inventoryID,
              try SharedMediaNativeAppEligibility.profile(inventory) == profile,
              inventory.revision == (try SharedMediaStoragePolicy.add(witness.state.plan.inventoryRevision, 1)),
              context.insertedModelsArray.count == inserts.count, Set(context.insertedModelsArray.map(\.persistentModelID)) == inserts,
              context.deletedModelsArray.count == deletes.count, Set(context.deletedModelsArray.map(\.persistentModelID)) == deletes,
              Set(context.changedModelsArray.map(\.persistentModelID)).subtracting(inserts).subtracting(deletes) == updates else { throw SharedMediaStorageFailure.conflict }
        try validateSaved(context)
    }
    fileprivate func validateSaved(_ context: ModelContext) throws {
        try witness.preparation.facts.validatePairPlan(context, package: package, member: member)
        let intent = try witness.state.intent()
        if released {
            func absent<T: PersistentModel>(_ q: FetchDescriptor<T>) throws {
                var query = q; query.fetchLimit = 1; query.includePendingChanges = true
                guard try context.fetch(query).isEmpty else { throw SharedMediaStorageFailure.conflict }
            }
            let id = intent.pairID
            try absent(FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == id }))
            for input in [intent.ai, intent.display] {
                let id = input.id, asset = input.assetID, lease = input.leaseID, reference = input.referenceID
                try absent(FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == id }))
                try absent(FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == asset }))
                try absent(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == lease }))
                try absent(FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == lease }))
                try absent(FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == asset }))
                try absent(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == reference }))
                try absent(FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == reference }))
                try absent(FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == asset }))
            }
        } else {
            let inventoryID = witness.state.plan.inventoryID, packageID = package.id
            let inv = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
            let pkg = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
            let mem = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
            guard try SharedMediaNativePairFileGraph.state(context: context, inventory: inv, package: pkg, member: mem, pairID: intent.pairID) == expected else { throw SharedMediaStorageFailure.conflict }
        }
    }
    func receivingBytes(_ consumer: SharedMediaConsumerRecord) throws -> Int64 { try witness.preparation.facts.receivingBytes(consumer) }
}
