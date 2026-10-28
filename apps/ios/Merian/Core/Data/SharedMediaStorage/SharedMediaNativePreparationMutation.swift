import Foundation
import SwiftData

/// Envelope-only preparation reservation. The sealed repository supplies the
/// account/store authority. This transaction cannot load, process or write media.
@MainActor
final class SharedMediaNativePreparationMutation {
    private let container: ModelContainer
    private let context: ModelContext
    private let inventory: SharedMediaInventoryRecord
    private let package: PhotoPreparationRecord
    private let member: SharedMediaPendingMembershipRecord
    private enum Authority {
        case qualification(SharedMediaNativeMutationAuthority), app(SharedMediaNativeAppPreparationWitness)
        var ownerID: UUID { switch self { case .qualification(let value): value.ownerID; case .app(let value): value.authority.profile.ownerID } }
        var writerEpoch: UUID { switch self { case .qualification(let value): value.writerEpoch; case .app(let value): value.authority.writerEpoch } }
        @MainActor func validate(_ container: ModelContainer) throws {
            switch self { case .qualification(let value): try value.validate(); case .app(let value): try value.validate(container) }
        }
    }
    private let authority: Authority
    private var appAfter: SharedMediaNativeAppMetadataFacts?
    private var appRequest: SharedMediaNativePreparationAttempt?

    convenience init(container: ModelContainer, inventoryID: UUID, packageID: UUID, authority: SharedMediaNativeMutationAuthority) throws {
        try self.init(container: container, inventoryID: inventoryID, packageID: packageID, scope: .qualification(authority))
    }
    convenience init(container: ModelContainer, packageID: UUID, witness: SharedMediaNativeAppPreparationWitness) throws {
        try self.init(container: container, inventoryID: witness.authority.profile.inventoryID, packageID: packageID, scope: .app(witness))
    }
    private init(container: ModelContainer, inventoryID: UUID, packageID: UUID, scope authority: Authority) throws {
        try authority.validate(container)
        self.container = container; self.authority = authority
        context = ModelContext(container); context.autosaveEnabled = false
        inventory = try Self.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        switch authority {
        case .qualification(let value):
            guard !value.binding.initializing,
                  value.binding.bytes == (try JSONEncoder().encode(["nativeQualificationV1", inventory.id.uuidString, inventory.storeIdentity, inventory.rootIdentity])) else { throw SharedMediaStorageFailure.conflict }
            try SharedMediaNativeAcquisitionGraph.audit(context: context, inventoryID: inventoryID)
        case .app(let witness):
            guard try SharedMediaNativeAppEligibility.profile(inventory) == witness.authority.profile else { throw SharedMediaStorageFailure.conflict }
        }
        package = try Self.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        member = try Self.one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        guard package.ownerID == authority.ownerID, package.accountingTierRaw == "pending", !package.retirementRequested,
              member.ownerID == authority.ownerID, member.inventoryID == inventoryID,
              member.inventoryGeneration == inventory.generation, member.draftGeneration == package.draftGeneration else { throw SharedMediaStorageFailure.closed }
    }

    func request(original: PhotoOriginalReference, recipe: SharedMediaNativePreparationRecipe) throws -> SharedMediaNativePreparationAttempt {
        try original.validate(); try recipe.validate()
        let previous = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData)
        guard original.packageID == package.id, original.ownerID == package.ownerID, original.draftGeneration == package.draftGeneration,
              package.phaseRaw == "draftOwned", previous.attempt == nil else { throw SharedMediaStorageFailure.closed }
        switch authority {
        case .qualification:
            guard try context.fetchCount(FetchDescriptor<PhotoPreparationLease>()) == 0,
                  try context.fetchCount(FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.cleanupStateRaw != "ready" })) == 0 else { throw SharedMediaStorageFailure.closed }
            try SharedMediaNativePreparationGraph.requireNoUnfinished(context)
        case .app:
            try SharedMediaNativePreparationGraph.requireIdleFiles(context, scopedInventory: inventory)
            try SharedMediaNativePreparationGraph.requireNoUnfinished(context, inventory: inventory, targetPackageID: package.id)
        }
        guard previous.intents.count < 2,
              try !previous.intents.contains(where: { try SharedMediaNativeDerivativeIntent.decode($0.bytes).preparation.original.reference.referenceID == original.referenceID }) else {
            throw SharedMediaStorageFailure.closed
        }
        let id = original.referenceID, assetID = original.assetID
        let ref = try Self.one(context, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == id }))
        let asset = try Self.one(context, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID }))
        let receipt = try Self.one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == assetID }))
        guard ref.isLive, ref.packageID == original.packageID, ref.ownerID == original.ownerID, ref.assetID == assetID,
              ref.revision == original.referenceRevision, ref.roleRaw == "original", asset.generation == original.assetGeneration,
              case .completed(_, let result) = try SharedMediaAcquisitionReceipt.read(receipt) else { throw SharedMediaStorageFailure.stale }
        let request = SharedMediaNativePreparationAttempt(format: .attempt,
            sequence: try SharedMediaStoragePolicy.add(previous.sequence, 1), operationID: UUID(), writerEpoch: authority.writerEpoch,
            inventoryID: inventory.id, inventoryGeneration: inventory.generation, inventoryRevision: inventory.revision,
            packageRevision: package.revision, membershipRevision: member.revision, membershipBytes: member.membersData,
            previousEnvelope: package.supportingContextData,
            original: .init(reference: original, ordinal: ref.ordinal, token: asset.fileToken, byteCount: asset.byteCount,
                sha256: asset.sha256, contentType: asset.contentType, descriptor: result.descriptor), recipe: recipe)
        try request.validate(); return request
    }

    func result(_ request: SharedMediaNativePreparationAttempt) throws {
        try validateIdentity(request)
        guard inventory.revision == request.inventoryRevision + 1, package.revision == request.packageRevision + 1,
              package.phaseRaw == "preparing", package.supportingContextData == (try reservedEnvelope(request)) else {
            throw SharedMediaStorageFailure.stale
        }
        if case .app = authority {
            try SharedMediaNativePreparationGraph.validate(.decode(package.supportingContextData),
                package: package, context: context, scopedInventory: inventory)
            try SharedMediaNativePreparationGraph.requireNoUnfinished(context, inventory: inventory,
                targetPackageID: package.id, allowing: request)
        }
    }

    func reserve(_ request: SharedMediaNativePreparationAttempt, availableBytes: Int64,
                 beforeSave: () throws -> Void, afterSave: () throws -> Void) throws {
        if case .app(let witness) = authority { guard witness.action == .reserve else { throw SharedMediaStorageFailure.closed } }
        try requireBefore(request)
        package.supportingContextData = try reservedEnvelope(request)
        package.phaseRaw = "preparing"
        package.revision = request.packageRevision + 1; inventory.revision = request.inventoryRevision + 1
        try result(request)
        let budget = try budgetAfterTransition(request)
        // Metadata now represented in this unsaved context still needs free
        // bytes; the remaining metadata/output reservations are in totals.
        let growth = max(0, Int64(package.supportingContextData.count - request.previousEnvelope.count))
        try budget.totals.checkAvailable(availableBytes, additionalReservation: growth)
        try beforeSave()
        let current = try fresh()
        try current.requireBefore(request); try current.checkAppBudget()
        if case .app = authority {
            let refreshed = try budgetAfterTransition(request)
            try refreshed.totals.checkAvailable(availableBytes, additionalReservation: growth)
        }
        do { try context.save() } catch { context.rollback(); throw error }
        try afterSave()
    }

    func activeAttempt() throws -> SharedMediaNativePreparationAttempt? {
        try authority.validate(container)
        return try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData).attempt.map { try .decode($0.bytes) }
    }

    /// Called only by the serial registered owner, after its previous operation
    /// drained. No processor/file callback is exposed by this reservation API.
    func abandon(_ request: SharedMediaNativePreparationAttempt,
                 beforeSave: () throws -> Void, afterSave: () throws -> Void) throws {
        if case .app(let witness) = authority { guard witness.action == .abandon(request) else { throw SharedMediaStorageFailure.closed } }
        try result(request)
        guard case .preparation(let value) = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData),
              value.frozen == nil else { throw SharedMediaStorageFailure.closed }
        package.supportingContextData = try SharedMediaNativeDraftEnvelope.V2(version: 2, contexts: value.contexts,
            presentation: value.presentation, sequence: value.sequence, attempt: nil, intents: value.intents, frozen: nil).encoded()
        package.phaseRaw = "draftOwned"
        package.revision = request.packageRevision + 2; inventory.revision = request.inventoryRevision + 2
        _ = try budgetAfterTransition(request)
        try beforeSave()
        let current = try fresh()
        try current.result(request); try current.checkAppBudget()
        if case .app = authority { _ = try budgetAfterTransition(request) }
        do { try context.save() } catch { context.rollback(); throw error }
        try afterSave()
    }

    func abandonedResult(_ request: SharedMediaNativePreparationAttempt) throws {
        try validateIdentity(request)
        let previous = try SharedMediaNativeDraftEnvelope.decode(request.previousEnvelope)
        let expected = try SharedMediaNativeDraftEnvelope.V2(version: 2, contexts: previous.contexts, presentation: previous.presentation,
            sequence: request.sequence, attempt: nil, intents: previous.intents, frozen: nil).encoded()
        guard package.phaseRaw == "draftOwned", inventory.revision == request.inventoryRevision + 2,
              package.revision == request.packageRevision + 2, package.supportingContextData == expected else { throw SharedMediaStorageFailure.stale }
    }

    private func requireBefore(_ request: SharedMediaNativePreparationAttempt) throws {
        try validateIdentity(request)
        guard request.writerEpoch == authority.writerEpoch, inventory.revision == request.inventoryRevision,
              package.revision == request.packageRevision, package.phaseRaw == "draftOwned",
              package.supportingContextData == request.previousEnvelope else { throw SharedMediaStorageFailure.stale }
        let expected = try self.request(original: request.original.reference, recipe: request.recipe)
        guard expected.original == request.original, expected.sequence == request.sequence else { throw SharedMediaStorageFailure.stale }
    }
    private func validateIdentity(_ request: SharedMediaNativePreparationAttempt) throws {
        try authority.validate(container); try request.validate()
        if case .app = authority { try Self.validateOriginal(request, context: context) }
        guard request.inventoryID == inventory.id, request.inventoryGeneration == inventory.generation,
              request.original.reference.packageID == package.id, request.original.reference.ownerID == authority.ownerID,
              request.original.reference.draftGeneration == package.draftGeneration,
              member.revision == request.membershipRevision, member.membersData == request.membershipBytes else { throw SharedMediaStorageFailure.stale }
    }
    private func reservedEnvelope(_ request: SharedMediaNativePreparationAttempt) throws -> Data {
        let previous = try SharedMediaNativeDraftEnvelope.decode(request.previousEnvelope)
        guard previous.attempt == nil, request.sequence == (try SharedMediaStoragePolicy.add(previous.sequence, 1)) else { throw SharedMediaStorageFailure.stale }
        if case .preparation(let value) = previous {
            guard value.frozen == nil else { throw SharedMediaStorageFailure.closed }
        }
        return try SharedMediaNativeDraftEnvelope.V2(version: 2, contexts: previous.contexts, presentation: previous.presentation,
            sequence: request.sequence, attempt: .init(bytes: request.encoded()), intents: previous.intents, frozen: nil).encoded()
    }
    private func budgetAfterTransition(_ request: SharedMediaNativePreparationAttempt) throws -> SharedMediaNativeAcquisitionBudget.Snapshot {
        guard case .app(let witness) = authority else { return try SharedMediaNativeAcquisitionBudget.evaluate(context: context, inventory: inventory) }
        let proof = try SharedMediaNativeAppPreparationPoststate(context: context, inventory: inventory, package: package, witness: witness, request: request)
        let budget = try SharedMediaNativeAcquisitionBudget.evaluatePreparationPoststate(context: context, inventory: inventory, proof: proof)
        appRequest = request
        appAfter = try SharedMediaNativeAppMetadataFacts.preparationPoststate(context, inventory: inventory, proof: proof)
        return budget
    }
    private func checkAppBudget() throws {
        if case .app(let witness) = authority {
            _ = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: context, inventory: inventory,
                ownerID: witness.authority.profile.ownerID, format: .appV2)
        }
    }
    func acknowledgeApp() throws {
        guard case .app(let witness) = authority, let appAfter, let appRequest,
              try witness.authority.header(container) == SharedMediaNativeAppMetadataFacts.successor(witness.expected) else { throw SharedMediaStorageFailure.stale }
        let read = ModelContext(container); read.autosaveEnabled = false
        try Self.validateOriginal(appRequest, context: read)
        guard try SharedMediaNativeAppMetadataFacts.capture(read, profile: witness.authority.profile) == appAfter else { throw SharedMediaStorageFailure.conflict }
    }
    private static func validateOriginal(_ request: SharedMediaNativePreparationAttempt, context: ModelContext) throws {
        let original = request.original, refID = original.reference.referenceID, assetID = original.reference.assetID
        let ref = try one(context, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == refID }))
        let asset = try one(context, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID }))
        let receipt = try one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == assetID }))
        guard ref.isLive, ref.packageID == original.reference.packageID, ref.ownerID == original.reference.ownerID,
              ref.assetID == assetID, ref.roleRaw == "original", ref.ordinal == original.ordinal,
              ref.revision == original.reference.referenceRevision, asset.ownerID == ref.ownerID,
              asset.generation == original.reference.assetGeneration, asset.cleanupStateRaw == "ready",
              asset.fileToken == original.token, asset.byteCount == original.byteCount, asset.sha256 == original.sha256,
              asset.contentType == original.contentType, case .completed(_, let result) = try SharedMediaAcquisitionReceipt.read(receipt),
              result.descriptor == original.descriptor, result.byteCount == original.byteCount,
              result.sha256 == original.sha256, result.contentType == original.contentType else { throw SharedMediaStorageFailure.stale }
    }
    private func fresh() throws -> SharedMediaNativePreparationMutation {
        try .init(container: container, inventoryID: inventory.id, packageID: package.id, scope: authority)
    }
    private static func one<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>) throws -> T {
        var query = descriptor; query.fetchLimit = 2; let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first else { throw SharedMediaStorageFailure.conflict }; return row
    }
}

enum SharedMediaNativePreparationBoundary: Equatable, Sendable {
    #if DEBUG
    case afterPhotoReadbackSeal
    #endif
    case beforeSave, afterSave, beforeReadback, beforePairSave, afterPairSave
    case beforePlanClosureSave, afterPlanClosureSave
    case beforeFreezeSave, afterFreezeSave
    case beforeFileReserve, afterFileReserve, beforeFileIdentity, afterFileIdentity
    case beforeFileCompletion, afterFileCompletion, beforeFilePublish, afterFilePublish
    case beforeFileRetire, afterFileRetire, beforeFileRelease, afterFileRelease
}

/// Only the typed preparation mutation can admit this exact two-row dirty state.
/// Membership, originals, consumers and sibling packages must remain unchanged.
@MainActor
struct SharedMediaNativeAppPreparationPoststate {
    var allocationPeers: [UUID: SharedMediaNativePhotoAllocationPeer] { facts.allocationPeers }
    var predecessorRevision: Int64 { expected.inventory.revision - 1 }
    let profile: SharedMediaNativeAppProfile
    private let contextID: ObjectIdentifier
    private let inventoryID: PersistentIdentifier, packageID: PersistentIdentifier
    private let expected: SharedMediaNativeAppEligibility.Header
    private let facts: SharedMediaNativeAppMetadataFacts
    private let successor: SharedMediaNativeAppMetadataFacts.Package
    fileprivate init(context: ModelContext, inventory: SharedMediaInventoryRecord, package: PhotoPreparationRecord,
                     witness: SharedMediaNativeAppPreparationWitness, request: SharedMediaNativePreparationAttempt) throws {
        profile = witness.authority.profile; contextID = ObjectIdentifier(context)
        inventoryID = inventory.persistentModelID; packageID = package.persistentModelID
        expected = try SharedMediaNativeAppMetadataFacts.successor(witness.expected); facts = witness.facts
        guard let old = facts.packages[package.id], let member = facts.members[package.id],
              request.inventoryID == profile.inventoryID, request.inventoryGeneration == profile.generation,
              request.original.reference.packageID == old.id, request.original.reference.ownerID == old.ownerID,
              request.original.reference.draftGeneration == old.generation,
              member.revision == request.membershipRevision, member.bytes == request.membershipBytes else { throw SharedMediaStorageFailure.conflict }
        let prior = try SharedMediaNativeDraftEnvelope.decode(request.previousEnvelope)
        let reserved = try SharedMediaNativeDraftEnvelope.V2(version: 2, contexts: prior.contexts, presentation: prior.presentation,
            sequence: request.sequence, attempt: .init(bytes: request.encoded()), intents: prior.intents, frozen: nil).encoded()
        switch witness.action {
        case .reserve:
            guard request.writerEpoch == witness.authority.writerEpoch, old.revision == request.packageRevision,
                  old.phase == "draftOwned", old.envelope == request.previousEnvelope,
                  witness.expected.inventory.revision == request.inventoryRevision else { throw SharedMediaStorageFailure.stale }
            successor = try old.successor(reserved, phase: "preparing")
        case .abandon(let exact):
            guard exact == request, old.envelope == reserved, old.phase == "preparing",
                  old.revision == (try SharedMediaStoragePolicy.add(request.packageRevision, 1)),
                  witness.expected.inventory.revision == (try SharedMediaStoragePolicy.add(request.inventoryRevision, 1)) else { throw SharedMediaStorageFailure.stale }
            let closed = try SharedMediaNativeDraftEnvelope.V2(version: 2, contexts: prior.contexts, presentation: prior.presentation,
                sequence: request.sequence, attempt: nil, intents: prior.intents, frozen: nil).encoded()
            successor = try old.successor(closed, phase: "draftOwned")
        case .inspect: throw SharedMediaStorageFailure.closed
        }
        try validate(context: context, inventory: inventory)
    }
    func validate(context: ModelContext, inventory: SharedMediaInventoryRecord) throws {
        guard ObjectIdentifier(context) == contextID, inventory.persistentModelID == inventoryID,
              try SharedMediaNativeAppEligibility.profile(inventory) == profile,
              inventory.revision == expected.inventory.revision else { throw SharedMediaStorageFailure.conflict }
        try SharedMediaNativeAppMetadataFacts.requireWriteSet(context, inventory: inventoryID, package: packageID)
        try facts.validatePreparation(context, package: successor)
    }
    func receivingBytes(_ consumer: SharedMediaConsumerRecord) throws -> Int64 { try facts.receivingBytes(consumer) }
}
