import Foundation
import SwiftData

/// Removes only a never-started plan. The held file owner must prove both
/// destinations absent; this transaction cannot unlink, process or create files.
@MainActor
final class SharedMediaNativeAppPairPlanClosure {
    private let container: ModelContainer
    private let witness: SharedMediaNativeAppPairPlanClosureWitness
    private let context: ModelContext
    private let inventory: SharedMediaInventoryRecord
    private let package: PhotoPreparationRecord
    private let member: SharedMediaPendingMembershipRecord
    private var consumed = false

    init(container: ModelContainer, witness: SharedMediaNativeAppPairPlanClosureWitness) throws {
        try witness.validate(container)
        self.container = container; self.witness = witness
        context = ModelContext(container); context.autosaveEnabled = false
        let inventoryID = witness.state.plan.inventoryID, packageID = witness.state.plan.packageID
        inventory = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        package = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        member = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
    }

    static func state(_ container: ModelContainer, preparation: SharedMediaNativeAppPreparationWitness,
                      plan: SharedMediaNativePairPlan) throws -> SharedMediaNativePairFileState {
        try preparation.validate(container)
        guard preparation.action == .inspect, preparation.facts.consumers[plan.packageID] == nil,
              preparation.facts.packages[plan.packageID] != nil else { throw SharedMediaStorageFailure.closed }
        let context = ModelContext(container); context.autosaveEnabled = false
        let inventoryID = preparation.authority.profile.inventoryID, packageID = plan.packageID
        let inventory = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let package = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        let member = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        let pairID = try SharedMediaNativeDerivativeIntent.decode(plan.intent.bytes).pairID
        let state = try SharedMediaNativePairFileGraph.state(context: context, inventory: inventory, package: package, member: member, pairID: pairID)
        guard state.plan == plan, state.phase == "planned" else { throw SharedMediaStorageFailure.stale }
        _ = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: context, inventory: inventory,
            ownerID: preparation.authority.profile.ownerID, format: .appV2)
        return state
    }

    func close(beforeSave: () throws -> Void, afterSave: () throws -> Void, beforeReadback: () throws -> Void) throws {
        guard !consumed else { throw SharedMediaStorageFailure.closed }; consumed = true
        try witness.validate(container)
        let intent = try witness.state.intent(), pairID = intent.pairID
        let pair = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == pairID }))
        var deleted: Set<PersistentIdentifier> = [pair.persistentModelID]
        for id in [intent.ai.id, intent.display.id] {
            let work = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == id }))
            deleted.insert(work.persistentModelID); context.delete(work)
        }
        context.delete(pair)
        let successor = try SharedMediaNativeAppPairPlanClosurePoststate.successor(witness)
        inventory.revision = try SharedMediaStoragePolicy.add(inventory.revision, 1)
        package.supportingContextData = successor.0.envelope; package.phaseRaw = successor.0.phase
        package.revision = successor.0.revision
        member.membersData = successor.1.bytes; member.revision = successor.1.revision
        let proof = SharedMediaNativeAppPairPlanClosurePoststate(context: context, inventory: inventory,
            package: package, member: member, deleted: deleted, witness: witness, successor: successor)
        _ = try SharedMediaNativeAcquisitionBudget.evaluatePairClosurePoststate(context: context, inventory: inventory, proof: proof)
        try beforeSave(); try witness.validate(container)
        _ = try SharedMediaNativeAcquisitionBudget.evaluatePairClosurePoststate(context: context, inventory: inventory, proof: proof)
        // No suspension between rechecking both held destinations and persistence.
        try witness.verifyAbsent()
        do { try context.save(); try afterSave() }
        catch {
            let failure = error; context.rollback()
            do { try beforeReadback(); try acknowledge(proof) } catch { throw failure }
        }
        try beforeReadback(); try acknowledge(proof)
    }

    private func acknowledge(_ proof: SharedMediaNativeAppPairPlanClosurePoststate) throws {
        guard try witness.preparation.authority.header(container) == SharedMediaNativeAppMetadataFacts.successor(witness.preparation.expected) else {
            throw SharedMediaStorageFailure.stale
        }
        let read = ModelContext(container); read.autosaveEnabled = false
        try proof.validateSaved(read)
        let id = witness.state.plan.inventoryID
        let inventory = try SharedMediaNativePairPlanGraph.one(read, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        _ = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: read, inventory: inventory,
            ownerID: witness.preparation.authority.profile.ownerID, format: .appV2)
    }
}

/// Sole dirty-context entry for exact plan closure: three updates and three
/// deletions. The unchanged original and receiving liabilities stay auditable.
@MainActor
struct SharedMediaNativeAppPairPlanClosurePoststate {
    let profile: SharedMediaNativeAppProfile
    private let contextID: ObjectIdentifier
    private let inventoryID: PersistentIdentifier, packageID: PersistentIdentifier, memberID: PersistentIdentifier
    private let deleted: Set<PersistentIdentifier>
    private let witness: SharedMediaNativeAppPairPlanClosureWitness
    private let package: SharedMediaNativeAppMetadataFacts.Package
    private let member: SharedMediaNativeAppMetadataFacts.Member

    fileprivate init(context: ModelContext, inventory: SharedMediaInventoryRecord, package: PhotoPreparationRecord,
                     member: SharedMediaPendingMembershipRecord, deleted: Set<PersistentIdentifier>,
                     witness: SharedMediaNativeAppPairPlanClosureWitness,
                     successor: (SharedMediaNativeAppMetadataFacts.Package, SharedMediaNativeAppMetadataFacts.Member)) {
        profile = witness.preparation.authority.profile; contextID = ObjectIdentifier(context)
        inventoryID = inventory.persistentModelID; packageID = package.persistentModelID; memberID = member.persistentModelID
        self.deleted = deleted; self.witness = witness; self.package = successor.0; self.member = successor.1
    }
    fileprivate static func successor(_ witness: SharedMediaNativeAppPairPlanClosureWitness) throws
        -> (SharedMediaNativeAppMetadataFacts.Package, SharedMediaNativeAppMetadataFacts.Member) {
        let plan = witness.state.plan, intent = try witness.state.intent(), facts = witness.preparation.facts
        guard let old = facts.packages[plan.packageID], let member = facts.members[plan.packageID],
              old.envelope == plan.envelope, member.bytes == plan.membership,
              case .preparation(let envelope) = try SharedMediaNativeDraftEnvelope.decode(old.envelope),
              envelope.attempt == nil, envelope.frozen == nil,
              envelope.intents.filter({ $0 == plan.intent }).count == 1 else { throw SharedMediaStorageFailure.conflict }
        let bytes = try SharedMediaNativeDraftEnvelope.V2(version: 2, contexts: envelope.contexts,
            presentation: envelope.presentation, sequence: envelope.sequence, attempt: nil,
            intents: envelope.intents.filter { $0 != plan.intent }, frozen: nil).encoded()
        let current = try SharedMediaMembership.decode(member.bytes)
        var groups = Dictionary(uniqueKeysWithValues: current.groups.map { ($0.kind, Set($0.ids)) })
        guard groups[.pair, default: []].remove(intent.pairID) != nil,
              groups[.derivative, default: []].remove(intent.ai.id) != nil,
              groups[.derivative, default: []].remove(intent.display.id) != nil else { throw SharedMediaStorageFailure.conflict }
        let membership = try SharedMediaMembership(groups: groups.filter { !$0.value.isEmpty }.map { kind, ids in
            .init(kind: kind, ids: ids.sorted { $0.uuidString < $1.uuidString })
        }.sorted { $0.kind.rawValue < $1.kind.rawValue }).encoded()
        return try (old.successor(bytes, phase: "draftOwned"), member.successor(membership))
    }
    func validate(context: ModelContext, inventory: SharedMediaInventoryRecord) throws {
        guard ObjectIdentifier(context) == contextID, inventory.persistentModelID == inventoryID,
              try SharedMediaNativeAppEligibility.profile(inventory) == profile,
              inventory.revision == (try SharedMediaNativeAppMetadataFacts.successor(witness.preparation.expected)).inventory.revision,
              context.insertedModelsArray.isEmpty, deleted.count == 3,
              context.deletedModelsArray.count == 3, Set(context.deletedModelsArray.map(\.persistentModelID)) == deleted,
              Set(context.changedModelsArray.map(\.persistentModelID)).subtracting(deleted) == Set([inventoryID, packageID, memberID]) else {
            throw SharedMediaStorageFailure.conflict
        }
        try validateSaved(context)
    }
    fileprivate func validateSaved(_ context: ModelContext) throws {
        try witness.preparation.facts.validatePairPlan(context, package: package, member: member)
        let intent = try witness.state.intent(), id = intent.pairID
        var pairs = FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == id })
        pairs.fetchLimit = 1; pairs.includePendingChanges = true
        guard try context.fetch(pairs).isEmpty else { throw SharedMediaStorageFailure.conflict }
        for id in [intent.ai.id, intent.display.id] {
            var works = FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == id })
            works.fetchLimit = 1; works.includePendingChanges = true
            guard try context.fetch(works).isEmpty else { throw SharedMediaStorageFailure.conflict }
        }
    }
    func receivingBytes(_ consumer: SharedMediaConsumerRecord) throws -> Int64 { try witness.preparation.facts.receivingBytes(consumer) }
}
