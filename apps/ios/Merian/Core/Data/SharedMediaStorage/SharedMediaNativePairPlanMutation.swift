import Foundation
import SwiftData

/// Native plan/save/ack boundary under the existing store fence. This owner
/// cannot reserve or create output files; its strict no-file plan may be abandoned.
@MainActor
final class SharedMediaNativePairPlanMutation {
    private let container: ModelContainer
    private let context: ModelContext
    private let inventory: SharedMediaInventoryRecord
    private let package: PhotoPreparationRecord
    private let member: SharedMediaPendingMembershipRecord
    private enum Authority {
        case qualification(SharedMediaNativeMutationAuthority), app(SharedMediaNativeAppPairPlanWitness)
        var ownerID: UUID {
            switch self {
            case .qualification(let a): a.ownerID
            case .app(let a): a.preparation.authority.profile.ownerID
            }
        }
        var fileEpoch: UUID {
            switch self {
            case .qualification(let a): a.binding.epoch
            case .app(let a): a.fileEpoch
            }
        }
        @MainActor func validate(_ container: ModelContainer) throws {
            switch self {
            case .qualification(let a): try a.validate()
            case .app(let a): try a.validate(container)
            }
        }
    }
    private let authority: Authority
    private var appAfter: SharedMediaNativeAppMetadataFacts?
    private let before: Witness
    private let pairID: UUID?

    private struct Witness: Equatable {
        let inventoryGeneration: UUID, inventoryRevision: Int64
        let draftGeneration: UUID, packageRevision: Int64, phase: String
        let envelope: Data, membershipRevision: Int64, membership: Data
        let plan: SharedMediaNativePairPlan?
    }

    convenience init(container: ModelContainer, inventoryID: UUID, packageID: UUID, authority: SharedMediaNativeMutationAuthority, pairID: UUID? = nil) throws {
        try self.init(container: container, inventoryID: inventoryID, packageID: packageID, scope: .qualification(authority), pairID: pairID)
    }
    convenience init(container: ModelContainer, witness: SharedMediaNativeAppPairPlanWitness, pairID: UUID) throws {
        try self.init(container: container, inventoryID: witness.preparation.authority.profile.inventoryID,
            packageID: witness.attempt.original.reference.packageID, scope: .app(witness), pairID: pairID)
    }
    private init(container: ModelContainer, inventoryID: UUID, packageID: UUID, scope authority: Authority, pairID: UUID?) throws {
        try authority.validate(container)
        self.container = container; self.authority = authority; self.pairID = pairID
        context = ModelContext(container); context.autosaveEnabled = false
        inventory = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        package = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        member = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        switch authority {
        case .qualification(let value):
            guard !value.binding.initializing,
                  value.binding.bytes == (try JSONEncoder().encode(["nativeQualificationV1", inventory.id.uuidString, inventory.storeIdentity, inventory.rootIdentity])) else { throw SharedMediaStorageFailure.closed }
            try SharedMediaNativeAcquisitionGraph.audit(context: context, inventoryID: inventoryID)
        case .app(let value):
            guard try SharedMediaNativeAppEligibility.profile(inventory) == value.preparation.authority.profile else { throw SharedMediaStorageFailure.closed }
        }
        guard package.ownerID == authority.ownerID, package.accountingTierRaw == "pending", !package.retirementRequested,
              member.ownerID == authority.ownerID, member.inventoryID == inventory.id,
              member.inventoryGeneration == inventory.generation, member.draftGeneration == package.draftGeneration else { throw SharedMediaStorageFailure.closed }
        before = try Self.witness(context: context, inventory: inventory, package: package, member: member, pairID: pairID)
    }

    func saved() throws -> SharedMediaNativePairPlan? { before.plan }

    func plan(_ outputs: SharedMediaNativePreparedOutputs, availableBytes: Int64,
              beforeSave: () throws -> Void, afterSave: () throws -> Void) throws -> SharedMediaNativePairPlan {
        let attempt = outputs.attempt, intent = outputs.intent
        switch authority {
        case .qualification(let value):
            try SharedMediaNativePreparationMutation(container: container, inventoryID: inventory.id, packageID: package.id, authority: value).result(attempt)
        case .app(let value):
            guard value.attempt == attempt, attempt.writerEpoch == value.preparation.authority.writerEpoch, pairID == intent.pairID else { throw SharedMediaStorageFailure.stale }
            try value.validate(container)
        }
        try intent.preparation.requireMatch(attempt)
        try SharedMediaDerivativeWorkFiles.validate(outputs.ai, input: intent.ai)
        try SharedMediaDerivativeWorkFiles.validate(outputs.display, input: intent.display)
        guard before.plan == nil, intent.previousPairID == nil,
              case .preparation(let envelope) = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData),
              envelope.intents.count < 2, envelope.frozen == nil, envelope.attempt?.bytes == (try attempt.encoded()) else {
            throw SharedMediaStorageFailure.closed
        }
        try requireFreshOutputIDs(intent)
        let blob = SharedMediaNativePreparationBlob(bytes: try intent.encoded()), original = attempt.original.reference
        let row = SharedMediaDerivativePairRecord(id: intent.pairID, nonce: intent.nonce, inventoryID: inventory.id,
            inventoryGeneration: inventory.generation, expectedInventoryRevision: inventory.revision,
            ownerID: original.ownerID, packageID: package.id, draftGeneration: package.draftGeneration,
            originalReferenceID: original.referenceID, originalReferenceRevision: original.referenceRevision,
            originalAssetID: original.assetID, originalAssetGeneration: original.assetGeneration, ordinal: attempt.original.ordinal,
            expectedPackageRevision: package.revision, aiWorkID: intent.ai.id, displayWorkID: intent.display.id)
        row.contractVersion = SharedMediaNativePairPlanGraph.contract
        context.insert(row)
        for input in [intent.ai, intent.display] {
            context.insert(SharedMediaDerivativeWorkRecord(id: input.id, pairID: row.id, roleRaw: input.role,
                assetID: input.assetID, assetGeneration: input.assetGeneration, referenceID: input.referenceID,
                leaseID: input.leaseID, writerEpoch: authority.fileEpoch, byteCount: input.byteCount,
                sha256: input.sha256, contentType: input.contentType))
        }
        package.supportingContextData = try SharedMediaNativeDraftEnvelope.V2(version: 2, contexts: envelope.contexts,
            presentation: envelope.presentation, sequence: envelope.sequence, attempt: nil, intents: envelope.intents + [blob], frozen: nil).encoded()
        package.phaseRaw = "needsAttention"
        try advance(intent: intent)
        let budget = try budgetAfterPlan(intent)
        try budget.totals.checkAvailable(availableBytes,
            additionalReservation: max(0, Int64(package.supportingContextData.count - before.envelope.count)))
        guard let expected = try Self.witness(context: context, inventory: inventory, package: package, member: member, pairID: pairID).plan else {
            throw SharedMediaStorageFailure.conflict
        }
        if case .app(let value) = authority {
            try beforeSave(); try value.validate(container)
            let budget = try budgetAfterPlan(intent)
            try budget.totals.checkAvailable(availableBytes,
                additionalReservation: max(0, Int64(package.supportingContextData.count - before.envelope.count)))
            try requireFreshOutputIDs(intent)
            // The physical seal is the final synchronous check before persistence.
            try value.verifyOriginal()
            do { try context.save(); try afterSave() } catch {
                let failure = error; context.rollback()
                do { try acknowledgeApp(expected) } catch { throw failure }
            }
            try acknowledgeApp(expected)
        } else { try save(beforeSave: beforeSave, afterSave: afterSave) }
        return expected
    }

    private func requireFreshOutputIDs(_ intent: SharedMediaNativeDerivativeIntent) throws {
        guard case .app = authority else { return }
        let c = ModelContext(container); c.autosaveEnabled = false
        let ids = [intent.pairID] + [intent.ai, intent.display].flatMap { [$0.id, $0.assetID, $0.referenceID, $0.leaseID] }
        try SharedMediaNativeReleaseStageIdentity.requireFresh(ids, inventoryID: inventory.id, context: c)
        try authority.validate(container)
    }

    func abandon(_ plan: SharedMediaNativePairPlan, beforeSave: () throws -> Void, afterSave: () throws -> Void) throws {
        guard case .qualification = authority else { throw SharedMediaStorageFailure.closed }
        guard before.plan == plan,
              case .preparation(let envelope) = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData) else {
            throw SharedMediaStorageFailure.stale
        }
        // A planned row is audited to have neither file allocations nor leases.
        // The complete namespace inspection at the serial owner rejects stray
        // files before this transition; no physical absence is inferred from age.
        let intent = try SharedMediaNativeDerivativeIntent.decode(plan.intent.bytes), pairID = intent.pairID
        let pair = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == pairID }))
        guard pair.phaseRaw == "planned" else { throw SharedMediaStorageFailure.closed }
        for id in [intent.ai.id, intent.display.id] {
            context.delete(try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == id })))
        }
        context.delete(pair)
        package.supportingContextData = try SharedMediaNativeDraftEnvelope.V2(version: 2, contexts: envelope.contexts,
            presentation: envelope.presentation, sequence: envelope.sequence, attempt: nil, intents: envelope.intents.filter { $0 != plan.intent }, frozen: nil).encoded()
        package.phaseRaw = "draftOwned"
        try advance()
        _ = try SharedMediaNativeAcquisitionBudget.evaluate(context: context, inventory: inventory)
        try save(beforeSave: beforeSave, afterSave: afterSave)
    }

    private func advance(intent: SharedMediaNativeDerivativeIntent? = nil) throws {
        inventory.revision = try SharedMediaStoragePolicy.add(inventory.revision, 1)
        package.revision = try SharedMediaStoragePolicy.add(package.revision, 1)
        let bytes: Data
        if case .app = authority {
            guard let intent else { throw SharedMediaStorageFailure.closed }
            bytes = try SharedMediaNativeAppPairPlanPoststate.membership(before.membership, intent: intent)
        } else { bytes = try SharedMediaPendingGraph.derive(in: context, inventory: inventory).membership(packageID: package.id).encoded() }
        if member.membersData != bytes {
            member.membersData = bytes
            member.revision = try SharedMediaStoragePolicy.add(member.revision, 1)
        }
    }

    private func save(beforeSave: () throws -> Void, afterSave: () throws -> Void) throws {
        let expected = try Self.witness(context: context, inventory: inventory, package: package, member: member, pairID: pairID)
        try beforeSave()
        guard try fresh().before == before else { throw SharedMediaStorageFailure.stale }
        do {
            try context.save()
            try afterSave()
        } catch {
            let failure = error
            context.rollback()
            guard (try? fresh().before) == expected else { throw failure }
        }
        guard try fresh().before == expected else { throw SharedMediaStorageFailure.stale }
    }
    private func fresh() throws -> SharedMediaNativePairPlanMutation {
        guard case .qualification(let value) = authority else { throw SharedMediaStorageFailure.closed }
        return try .init(container: container, inventoryID: inventory.id, packageID: package.id, authority: value, pairID: pairID)
    }
    private func budgetAfterPlan(_ intent: SharedMediaNativeDerivativeIntent) throws -> SharedMediaNativeAcquisitionBudget.Snapshot {
        guard case .app(let value) = authority else { return try SharedMediaNativeAcquisitionBudget.evaluate(context: context, inventory: inventory) }
        let proof = try SharedMediaNativeAppPairPlanPoststate(context: context, inventory: inventory, package: package, member: member, witness: value, intent: intent)
        let budget = try SharedMediaNativeAcquisitionBudget.evaluatePairPlanPoststate(context: context, inventory: inventory, proof: proof)
        appAfter = try SharedMediaNativeAppMetadataFacts.pairPlanPoststate(context, inventory: inventory, proof: proof)
        return budget
    }
    private func acknowledgeApp(_ expected: SharedMediaNativePairPlan) throws {
        guard case .app(let value) = authority, let appAfter else { throw SharedMediaStorageFailure.closed }
        try value.beforeReadback()
        guard try value.preparation.authority.header(container) == SharedMediaNativeAppMetadataFacts.successor(value.preparation.expected) else { throw SharedMediaStorageFailure.stale }
        let read = ModelContext(container); read.autosaveEnabled = false
        guard try SharedMediaNativeAppMetadataFacts.capture(read, profile: value.preparation.authority.profile) == appAfter else { throw SharedMediaStorageFailure.conflict }
        let inventoryID = inventory.id, packageID = package.id
        let currentInventory = try SharedMediaNativePairPlanGraph.one(read, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let currentPackage = try SharedMediaNativePairPlanGraph.one(read, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        let currentMember = try SharedMediaNativePairPlanGraph.one(read, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        guard try SharedMediaNativePairPlanGraph.state(context: read, inventory: currentInventory, package: currentPackage, member: currentMember, pairID: pairID) == expected else { throw SharedMediaStorageFailure.stale }
        _ = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: read, inventory: currentInventory, ownerID: value.preparation.authority.profile.ownerID, format: .appV2)
    }
    private static func witness(context: ModelContext, inventory: SharedMediaInventoryRecord,
                                package: PhotoPreparationRecord, member: SharedMediaPendingMembershipRecord, pairID: UUID?) throws -> Witness {
        let envelope = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData)
        let plan: SharedMediaNativePairPlan?
        if case .preparation(let value) = envelope, try SharedMediaNativePairPlanGraph.select(value, pairID: pairID) != nil {
            plan = try SharedMediaNativePairPlanGraph.state(context: context, inventory: inventory, package: package, member: member, pairID: pairID)
        } else { plan = nil }
        return .init(inventoryGeneration: inventory.generation, inventoryRevision: inventory.revision,
            draftGeneration: package.draftGeneration, packageRevision: package.revision, phase: package.phaseRaw,
            envelope: package.supportingContextData, membershipRevision: member.revision, membership: member.membersData, plan: plan)
    }
}

/// Only this typed plan transaction can attest its three updates and three
/// inserted rows. The app projection never accepts a generic dirty context.
@MainActor
struct SharedMediaNativeAppPairPlanPoststate {
    var allocationPeers: [UUID: SharedMediaNativePhotoAllocationPeer] { facts.allocationPeers }
    var predecessorRevision: Int64 { expected.inventory.revision - 1 }
    let profile: SharedMediaNativeAppProfile
    private let contextID: ObjectIdentifier
    private let inventoryID: PersistentIdentifier, packageID: PersistentIdentifier, memberID: PersistentIdentifier
    private let inserted: Set<PersistentIdentifier>
    private let expected: SharedMediaNativeAppEligibility.Header
    private let facts: SharedMediaNativeAppMetadataFacts
    private let package: SharedMediaNativeAppMetadataFacts.Package
    private let member: SharedMediaNativeAppMetadataFacts.Member
    private let intent: SharedMediaNativeDerivativeIntent
    private let fileEpoch: UUID
    fileprivate init(context: ModelContext, inventory: SharedMediaInventoryRecord, package row: PhotoPreparationRecord,
                     member: SharedMediaPendingMembershipRecord, witness: SharedMediaNativeAppPairPlanWitness,
                     intent: SharedMediaNativeDerivativeIntent) throws {
        profile = witness.preparation.authority.profile; contextID = ObjectIdentifier(context)
        inventoryID = inventory.persistentModelID; packageID = row.persistentModelID; memberID = member.persistentModelID
        expected = try SharedMediaNativeAppMetadataFacts.successor(witness.preparation.expected)
        facts = witness.preparation.facts; self.intent = intent; fileEpoch = witness.fileEpoch
        try intent.preparation.requireMatch(witness.attempt)
        guard let old = facts.packages[row.id], let oldMember = facts.members[row.id],
              case .preparation(let prior) = try SharedMediaNativeDraftEnvelope.decode(old.envelope),
              prior.attempt?.bytes == (try witness.attempt.encoded()), prior.frozen == nil,
              intent.previousPairID == nil, intent.preparation.original.reference.packageID == row.id else { throw SharedMediaStorageFailure.conflict }
        let bytes = try SharedMediaNativeDraftEnvelope.V2(version: 2, contexts: prior.contexts, presentation: prior.presentation,
            sequence: prior.sequence, attempt: nil, intents: prior.intents + [.init(bytes: intent.encoded())], frozen: nil).encoded()
        package = try old.successor(bytes, phase: "needsAttention")
        self.member = try oldMember.successor(Self.membership(oldMember.bytes, intent: intent))
        let pairID = intent.pairID
        let pair = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == pairID }))
        var identities: Set<PersistentIdentifier> = [pair.persistentModelID]
        for input in [intent.ai, intent.display] {
            let id = input.id
            let work = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == id }))
            guard work.writerEpoch == fileEpoch else { throw SharedMediaStorageFailure.conflict }
            identities.insert(work.persistentModelID)
        }
        inserted = identities
        try validate(context: context, inventory: inventory)
    }
    static func membership(_ old: Data, intent: SharedMediaNativeDerivativeIntent) throws -> Data {
        let current = try SharedMediaMembership.decode(old)
        var groups = Dictionary(uniqueKeysWithValues: current.groups.map { ($0.kind, Set($0.ids)) })
        guard groups[.pair, default: []].insert(intent.pairID).inserted,
              groups[.derivative, default: []].insert(intent.ai.id).inserted,
              groups[.derivative, default: []].insert(intent.display.id).inserted else { throw SharedMediaStorageFailure.conflict }
        return try SharedMediaMembership(groups: groups.map { kind, ids in
            .init(kind: kind, ids: ids.sorted { $0.uuidString < $1.uuidString })
        }.sorted { $0.kind.rawValue < $1.kind.rawValue }).encoded()
    }
    func validate(context: ModelContext, inventory: SharedMediaInventoryRecord) throws {
        guard ObjectIdentifier(context) == contextID, inventory.persistentModelID == inventoryID,
              try SharedMediaNativeAppEligibility.profile(inventory) == profile, inventory.revision == expected.inventory.revision,
              context.deletedModelsArray.isEmpty, inserted.count == 3,
              context.insertedModelsArray.count == 3, Set(context.insertedModelsArray.map(\.persistentModelID)) == inserted,
              Set(context.changedModelsArray.map(\.persistentModelID)).subtracting(inserted) == Set([inventoryID, packageID, memberID]) else { throw SharedMediaStorageFailure.conflict }
        try facts.validatePairPlan(context, package: package, member: member)
        let id = package.id
        let row = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id }))
        let membership = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
        let state = try SharedMediaNativePairPlanGraph.state(context: context, inventory: inventory, package: row, member: membership, pairID: intent.pairID)
        guard state.intent.bytes == (try intent.encoded()), state.writerEpoch == fileEpoch else { throw SharedMediaStorageFailure.conflict }
    }
    func receivingBytes(_ consumer: SharedMediaConsumerRecord) throws -> Int64 { try facts.receivingBytes(consumer) }
}
