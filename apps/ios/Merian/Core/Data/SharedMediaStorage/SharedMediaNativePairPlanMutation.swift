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
    private let authority: SharedMediaNativeMutationAuthority
    private let before: Witness

    private struct Witness: Equatable {
        let inventoryGeneration: UUID, inventoryRevision: Int64
        let draftGeneration: UUID, packageRevision: Int64, phase: String
        let envelope: Data, membershipRevision: Int64, membership: Data
        let plan: SharedMediaNativePairPlan?
    }

    init(container: ModelContainer, inventoryID: UUID, packageID: UUID, authority: SharedMediaNativeMutationAuthority) throws {
        try authority.validate()
        self.container = container; self.authority = authority
        context = ModelContext(container); context.autosaveEnabled = false
        inventory = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        package = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        member = try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        guard !authority.binding.initializing,
              authority.binding.bytes == (try JSONEncoder().encode(["nativeQualificationV1", inventory.id.uuidString, inventory.storeIdentity, inventory.rootIdentity])),
              package.ownerID == authority.ownerID, package.accountingTierRaw == "pending", !package.retirementRequested,
              member.ownerID == authority.ownerID, member.inventoryID == inventory.id,
              member.inventoryGeneration == inventory.generation, member.draftGeneration == package.draftGeneration else {
            throw SharedMediaStorageFailure.closed
        }
        try SharedMediaNativeAcquisitionGraph.audit(context: context, inventoryID: inventoryID)
        before = try Self.witness(context: context, inventory: inventory, package: package, member: member)
    }

    func saved() throws -> SharedMediaNativePairPlan? { before.plan }

    func plan(_ outputs: SharedMediaNativePreparedOutputs, availableBytes: Int64,
              beforeSave: () throws -> Void, afterSave: () throws -> Void) throws -> SharedMediaNativePairPlan {
        let attempt = outputs.attempt, intent = outputs.intent
        try SharedMediaNativePreparationMutation(container: container, inventoryID: inventory.id, packageID: package.id,
            authority: authority).result(attempt)
        try intent.preparation.requireMatch(attempt)
        try SharedMediaDerivativeWorkFiles.validate(outputs.ai, input: intent.ai)
        try SharedMediaDerivativeWorkFiles.validate(outputs.display, input: intent.display)
        guard before.plan == nil, intent.previousPairID == nil,
              case .preparation(let envelope) = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData),
              envelope.intents.isEmpty, envelope.frozen == nil, envelope.attempt?.bytes == (try attempt.encoded()) else {
            throw SharedMediaStorageFailure.closed
        }
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
                leaseID: input.leaseID, writerEpoch: authority.binding.epoch, byteCount: input.byteCount,
                sha256: input.sha256, contentType: input.contentType))
        }
        package.supportingContextData = try SharedMediaNativeDraftEnvelope.V2(version: 2, contexts: envelope.contexts,
            presentation: envelope.presentation, sequence: envelope.sequence, attempt: nil, intents: [blob], frozen: nil).encoded()
        package.phaseRaw = "needsAttention"
        try advance()
        let budget = try SharedMediaNativeAcquisitionBudget.evaluate(context: context, inventory: inventory)
        try budget.totals.checkAvailable(availableBytes,
            additionalReservation: max(0, Int64(package.supportingContextData.count - before.envelope.count)))
        guard let expected = try Self.witness(context: context, inventory: inventory, package: package, member: member).plan else {
            throw SharedMediaStorageFailure.conflict
        }
        try save(beforeSave: beforeSave, afterSave: afterSave)
        return expected
    }

    func abandon(_ plan: SharedMediaNativePairPlan, beforeSave: () throws -> Void, afterSave: () throws -> Void) throws {
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
            presentation: envelope.presentation, sequence: envelope.sequence, attempt: nil, intents: [], frozen: nil).encoded()
        package.phaseRaw = "draftOwned"
        try advance()
        _ = try SharedMediaNativeAcquisitionBudget.evaluate(context: context, inventory: inventory)
        try save(beforeSave: beforeSave, afterSave: afterSave)
    }

    private func advance() throws {
        inventory.revision = try SharedMediaStoragePolicy.add(inventory.revision, 1)
        package.revision = try SharedMediaStoragePolicy.add(package.revision, 1)
        let bytes = try SharedMediaPendingGraph.derive(in: context, inventory: inventory).membership(packageID: package.id).encoded()
        if member.membersData != bytes {
            member.membersData = bytes
            member.revision = try SharedMediaStoragePolicy.add(member.revision, 1)
        }
    }

    private func save(beforeSave: () throws -> Void, afterSave: () throws -> Void) throws {
        let expected = try Self.witness(context: context, inventory: inventory, package: package, member: member)
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
        try .init(container: container, inventoryID: inventory.id, packageID: package.id, authority: authority)
    }
    private static func witness(context: ModelContext, inventory: SharedMediaInventoryRecord,
                                package: PhotoPreparationRecord, member: SharedMediaPendingMembershipRecord) throws -> Witness {
        let envelope = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData)
        let plan: SharedMediaNativePairPlan?
        if case .preparation(let value) = envelope, !value.intents.isEmpty {
            plan = try SharedMediaNativePairPlanGraph.state(context: context, inventory: inventory, package: package, member: member)
        } else { plan = nil }
        return .init(inventoryGeneration: inventory.generation, inventoryRevision: inventory.revision,
            draftGeneration: package.draftGeneration, packageRevision: package.revision, phase: package.phaseRaw,
            envelope: package.supportingContextData, membershipRevision: member.revision, membership: member.membersData, plan: plan)
    }
}
