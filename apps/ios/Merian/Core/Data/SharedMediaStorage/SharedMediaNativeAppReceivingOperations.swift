import Foundation
import SwiftData

/// An immutable, ordinary-photo intent. It is not a save or execution capability.
/// Capture integration must durably retain it before exposing submission.
struct SharedMediaNativeAppReceivingRequest: Sendable {
    let profile: SharedMediaNativeAppProfile
    let header: SharedMediaNativeAppEligibility.Header
    let package: SharedMediaNativeAppMetadataFacts.Package
    let member: SharedMediaNativeAppMetadataFacts.Member
    let freeze: SharedMediaNativeFreezeRequest
    let cohort: SharedMediaNativeConsumerCohort
    let timestamp: Date
    let eventID: String
    let metadata: String
    var jobID: String { "scan-ingestion:" + cohort.originQueueID }
    fileprivate init(profile: SharedMediaNativeAppProfile, header: SharedMediaNativeAppEligibility.Header,
                     package: SharedMediaNativeAppMetadataFacts.Package, member: SharedMediaNativeAppMetadataFacts.Member,
                     freeze: SharedMediaNativeFreezeRequest, queueID: UUID, observationID: UUID, bindingID: UUID,
                     generation: UUID, eventID: UUID, timestamp: Date) throws {
        self.profile = profile; self.header = header; self.package = package; self.member = member; self.freeze = freeze
        cohort = .init(format: .receiving, bindingID: bindingID, originQueueID: queueID.uuidString.lowercased(),
            observationID: observationID.uuidString.lowercased(), executionKind: "ordinaryV1", inferenceGeneration: generation,
            freeze: .init(bytes: try freeze.commit.encoded()), membership: member.bytes)
        self.timestamp = timestamp; self.eventID = eventID.uuidString.lowercased()
        let bytes = try SharedMediaNativeDraftEnvelope.bytes([
            "native_receiving_v1": try cohort.digest(), "inference_generation": generation.uuidString.lowercased(),
            "operation_id": freeze.commit.operationID.uuidString.lowercased(), "event_id": self.eventID])
        guard timestamp.timeIntervalSince1970.isFinite, let json = String(data: bytes, encoding: .utf8) else { throw SharedMediaStorageFailure.conflict }
        metadata = json
    }
    func frozenPackage() throws -> SharedMediaNativeAppMetadataFacts.Package {
        guard case .preparation(let value) = try SharedMediaNativeDraftEnvelope.decode(freeze.previousEnvelope) else { throw SharedMediaStorageFailure.conflict }
        let bytes = try SharedMediaNativeDraftEnvelope.V2(version: 2, contexts: value.contexts, presentation: value.presentation,
            sequence: value.sequence, attempt: nil, intents: value.intents, frozen: cohort.freeze).encoded()
        return try package.successor(bytes, phase: "preparedHeld")
    }
}

/// One held owner operation, one save attempt. Request construction is read-only;
/// exact recovery of an acknowledged set cannot mint dispatch or funding rights.
@MainActor
final class SharedMediaNativeAppReceivingOperations {
    private let container: ModelContainer
    private let authority: SharedMediaNativeAppOperationAuthority
    private let expected: SharedMediaNativeAppEligibility.Header
    private let facts: SharedMediaNativeAppMetadataFacts
    private let io: SharedMediaNativeOriginalIO
    private let binding: SharedMediaNativeBinding
    private let availableBytes: () throws -> Int64
    private let boundary: (SharedMediaNativeMetadataBoundary) throws -> Void
    private let verify: (SharedMediaPhotoRetirementInspection) throws -> Void
    private var consumed = false
    private init(container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                 expected: SharedMediaNativeAppEligibility.Header, facts: SharedMediaNativeAppMetadataFacts,
                 io: SharedMediaNativeOriginalIO, binding: SharedMediaNativeBinding, availableBytes: @escaping () throws -> Int64,
                 boundary: @escaping (SharedMediaNativeMetadataBoundary) throws -> Void,
                 verify: @escaping (SharedMediaPhotoRetirementInspection) throws -> Void) {
        self.container = container; self.authority = authority; self.expected = expected; self.facts = facts
        self.io = io; self.binding = binding; self.availableBytes = availableBytes; self.boundary = boundary; self.verify = verify
    }
    static func audited(container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                        io: SharedMediaNativeOriginalIO, binding: SharedMediaNativeBinding, availableBytes: @escaping () throws -> Int64,
                        boundary: @escaping (SharedMediaNativeMetadataBoundary) throws -> Void,
                        verify: @escaping (SharedMediaPhotoRetirementInspection) throws -> Void) async throws -> SharedMediaNativeAppReceivingOperations {
        let expected = try authority.header(container)
        _ = try await SharedMediaNativeScopedAudit(app: container, profile: authority.profile, expected: expected.inventory,
            check: { guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale } },
            betweenPages: { await Task.yield() }).run()
        guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
        let context = ModelContext(container); context.autosaveEnabled = false
        return .init(container: container, authority: authority, expected: expected,
            facts: try SharedMediaNativeAppMetadataFacts.capture(context, profile: authority.profile), io: io,
            binding: binding, availableBytes: availableBytes, boundary: boundary, verify: verify)
    }
    func request(packageID: UUID, pairIDs: [UUID], operationID: UUID, queueID: UUID, observationID: UUID,
                 bindingID: UUID, generation: UUID, eventID: UUID, timestamp: Date) async throws -> SharedMediaNativeAppReceivingRequest {
        try await prepareRequest(packageID: packageID, pairIDs: pairIDs, operationID: operationID, queueID: queueID,
            observationID: observationID, bindingID: bindingID, generation: generation, eventID: eventID, timestamp: timestamp).0
    }
    private func prepareRequest(packageID: UUID, pairIDs: [UUID], operationID: UUID, queueID: UUID, observationID: UUID,
                                bindingID: UUID, generation: UUID, eventID: UUID, timestamp: Date) async throws
        -> (SharedMediaNativeAppReceivingRequest, [SharedMediaPhotoRetirementInspection]) {
        try validate(); try facts.requireMutable(packageID)
        let c = fresh(), (inventory, package, member) = try target(c, packageID)
        let states = try SharedMediaNativeFreezeFacts.states(context: c, inventory: inventory, package: package, member: member, pairIDs: pairIDs)
        let proofs = try await inspect(states)
        let freeze = try SharedMediaNativeFreezeFacts.request(context: c, inventory: inventory, package: package, member: member,
            binding: binding, operationID: operationID, pairIDs: pairIDs, proofs: proofs)
        let request = try SharedMediaNativeAppReceivingRequest(profile: authority.profile, header: expected,
            package: .init(package), member: .init(member), freeze: freeze, queueID: queueID, observationID: observationID,
            bindingID: bindingID, generation: generation, eventID: eventID, timestamp: timestamp)
        _ = try SharedMediaNativeReceivingRows.read(request, in: fresh(), absent: true)
        try validate(); return (request, proofs)
    }
    func apply(_ request: SharedMediaNativeAppReceivingRequest) async throws -> SharedMediaNativeConsumerCohort {
        try validate(); try facts.requireMutable(request.package.id)
        guard request.profile == authority.profile else { throw SharedMediaStorageFailure.conflict }
        // Only the complete exact set resolves uncertain acknowledgement. A failed
        // readback still cannot pass fresh absence/prestate checks below.
        if let saved = try? readResult(request) { consumed = true; return saved }
        guard expected == request.header else { throw SharedMediaStorageFailure.stale }
        let c = fresh(), (inventory, package, member) = try target(c, request.package.id)
        try requirePrestate(request, context: c, package: package, member: member)
        let cohort = try SharedMediaNativeFrozenCohort.decode(request.freeze.commit.cohort.bytes)
        let pairIDs = try cohort.entries.map { try SharedMediaNativeDerivativeIntent.decode($0.intent.bytes).pairID }
        let states = try SharedMediaNativeFreezeFacts.states(context: c, inventory: inventory, package: package, member: member, pairIDs: pairIDs)
        let proofs = try await inspect(states)
        guard try SharedMediaNativeFreezeFacts.request(context: c, inventory: inventory, package: package, member: member,
            binding: binding, operationID: request.freeze.commit.operationID, pairIDs: pairIDs, proofs: proofs) == request.freeze else { throw SharedMediaStorageFailure.stale }
        let originals = try originalFacts(cohort, context: c)
        let frozen = try request.frozenPackage()
        package.supportingContextData = frozen.envelope; package.phaseRaw = frozen.phase; package.revision = frozen.revision
        inventory.revision = try request.freeze.commit.inventoryRevision
        let rows = try SharedMediaNativeReceivingRows.insert(request, in: c)
        let proof = SharedMediaNativeAppReceivingPoststate(request: request, facts: facts,
            inventory: inventory.persistentModelID, package: package.persistentModelID, inserted: rows.identities)
        let budget = try SharedMediaNativeAcquisitionBudget.evaluateReceivingPoststate(context: c, inventory: inventory, proof: proof)
        let added = try SharedMediaStoragePolicy.add(Int64(frozen.envelope.count - request.package.envelope.count), Int64(rows.consumer.cohortData.count))
        try budget.totals.checkAvailable(availableBytes(), additionalReservation: max(0, added))
        try boundary(.beforeSave); try validate(); try proof.validate(context: c, inventory: inventory)
        let current = fresh(), (oldInventory, oldPackage, oldMember) = try target(current, request.package.id)
        try requirePrestate(request, context: current, package: oldPackage, member: oldMember)
        guard try SharedMediaNativeFreezeFacts.request(context: current, inventory: oldInventory, package: oldPackage,
            member: oldMember, binding: binding, operationID: request.freeze.commit.operationID,
            pairIDs: pairIDs, proofs: proofs) == request.freeze else { throw SharedMediaStorageFailure.stale }
        _ = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: current, inventory: oldInventory,
            ownerID: authority.profile.ownerID, format: .appV2)
        try budget.totals.checkAvailable(availableBytes(), additionalReservation: max(0, added))
        try validate()
        guard try originalFacts(cohort, context: current) == originals else { throw SharedMediaStorageFailure.stale }
        for observation in proofs { try verify(observation) }
        // No await, callback or file operation separates the final seals and save.
        consumed = true
        do {
            try c.save(); try boundary(.afterSave); try boundary(.beforeReadback)
            let result = try readResult(request, immediate: true)
            try facts.validateReceiving(fresh(), request: request)
            return result
        } catch {
            let failure = error; c.rollback()
            do {
                try boundary(.beforeReadback)
                let result = try readResult(request, immediate: true)
                try facts.validateReceiving(fresh(), request: request)
                return result
            } catch { throw failure }
        }
    }
    func stage(packageID: UUID, draftGeneration: UUID, pairIDs: [UUID],
               identity: SharedMediaNativeReceivingStageIdentity) async throws -> SharedMediaNativeReceivingIntent.Prepared {
        try validate()
        let initial = fresh(), (initialInventory, _, _) = try target(initial, packageID)
        let saved = try SharedMediaNativeReceivingIntentGraph.read(initial, inventory: initialInventory)[packageID]
        if let bytes = identity.savedBytes {
            guard let saved, saved.row.preparedData == bytes else { throw SharedMediaStorageFailure.stale }
            try requireSelection(saved.prepared, draftGeneration: draftGeneration, pairIDs: pairIDs)
            consumed = true; return saved.prepared
        }
        // A concurrent saved slot must be rediscovered with its own locks and IDs.
        guard saved == nil else { throw SharedMediaStorageFailure.stale }
        let (request, proofs) = try await prepareRequest(packageID: packageID, pairIDs: pairIDs,
            operationID: identity.operationID, queueID: identity.queueID, observationID: identity.observationID,
            bindingID: identity.bindingID, generation: identity.generation, eventID: identity.eventID, timestamp: identity.timestamp)
        let prepared = try SharedMediaNativeReceivingIntent.Prepared(request)
        try requireSelection(prepared, draftGeneration: draftGeneration, pairIDs: pairIDs)
        let c = fresh(), (inventory, package, member) = try target(c, packageID)
        try requirePrestate(request, context: c, package: package, member: member)
        let states = try SharedMediaNativeReceivingIntentGraph.cohort(prepared, context: c, inventory: inventory)
        let frozen = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes)
        let originals = try originalFacts(frozen, context: c)
        let budget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inventory,
            ownerID: authority.profile.ownerID, format: .appV2)
        guard let beforeBytes = budget.metadataByPackage[packageID] else { throw SharedMediaStorageFailure.conflict }
        let projection = try SharedMediaNativeReceivingReservation.maximum(prepared, currentMetadata: beforeBytes, pairStates: states)
        let bytes = try prepared.encoded()
        // The poststate already includes receiving headroom in outstanding.
        // Only newly materialized bytes require immediate additional space.
        let added = Int64(bytes.count)
        let row = SharedMediaReceivingIntentRecord(packageID: packageID, inventoryID: authority.profile.inventoryID,
            inventoryGeneration: authority.profile.generation, ownerID: authority.profile.ownerID,
            draftGeneration: draftGeneration, operationID: prepared.operationID, preparedData: bytes,
            preparedSHA256: SharedMediaAcquisitionEncoding.digest(bytes))
        c.insert(row); inventory.revision = try SharedMediaStoragePolicy.add(expected.inventory.revision, 1)
        let proof = SharedMediaNativeAppStagingPoststate(facts: facts, header: expected,
            row: .init(row), inventory: inventory.persistentModelID, inserted: row.persistentModelID)
        let after = try SharedMediaNativeAcquisitionBudget.evaluateStagingPoststate(context: c, inventory: inventory, proof: proof)
        guard after.metadataByPackage[packageID] == projection.charged else { throw SharedMediaStorageFailure.conflict }
        try after.totals.checkAvailable(availableBytes(), additionalReservation: added)
        try boundary(.beforeSave); try validate(); try proof.validate(context: c, inventory: inventory)
        let current = fresh(), (oldInventory, oldPackage, oldMember) = try target(current, packageID)
        try requirePrestate(request, context: current, package: oldPackage, member: oldMember)
        guard try SharedMediaNativeFreezeFacts.request(context: current, inventory: oldInventory, package: oldPackage,
            member: oldMember, binding: binding, operationID: prepared.operationID, pairIDs: pairIDs, proofs: proofs) == request.freeze else {
            throw SharedMediaStorageFailure.stale
        }
        _ = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: current, inventory: oldInventory,
            ownerID: authority.profile.ownerID, format: .appV2)
        guard try originalFacts(frozen, context: current) == originals else { throw SharedMediaStorageFailure.stale }
        try after.totals.checkAvailable(availableBytes(), additionalReservation: added)
        for observation in proofs { try verify(observation) }
        // The final physical seals and save are synchronous under retained locks.
        consumed = true
        do {
            try c.save(); try boundary(.afterSave)
            return try stagedResult(prepared)
        } catch {
            let failure = error; c.rollback()
            do { return try stagedResult(prepared) } catch { throw failure }
        }
    }
    private func stagedResult(_ prepared: SharedMediaNativeReceivingIntent.Prepared) throws -> SharedMediaNativeReceivingIntent.Prepared {
        try boundary(.beforeReadback)
        guard try authority.header(container) == SharedMediaNativeAppMetadataFacts.successor(expected) else {
            throw SharedMediaStorageFailure.stale
        }
        let c = fresh(), (inventory, _, _) = try target(c, prepared.package.id)
        guard let found = try SharedMediaNativeReceivingIntentGraph.read(c, inventory: inventory)[prepared.package.id],
              found.row.preparedData == (try prepared.encoded()) else { throw SharedMediaStorageFailure.conflict }
        try facts.validateStaging(c, adding: found.row)
        return found.prepared
    }
    private func requireSelection(_ prepared: SharedMediaNativeReceivingIntent.Prepared,
                                  draftGeneration: UUID, pairIDs: [UUID]) throws {
        let cohort = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes)
        guard prepared.package.generation == draftGeneration,
              try cohort.entries.map({ try SharedMediaNativeDerivativeIntent.decode($0.intent.bytes).pairID }) == pairIDs else {
            throw SharedMediaStorageFailure.stale
        }
    }
    private func originalFacts(_ cohort: SharedMediaNativeFrozenCohort, context: ModelContext) throws -> [SharedMediaNativeOriginalAccounting.Snapshot] {
        try cohort.entries.map { entry in
            let original = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes).preparation.original
            return try SharedMediaNativeOriginalAccounting.audit(assetID: original.reference.assetID,
                inventoryID: authority.profile.inventoryID, context: context)
        }
    }
    private func inspect(_ states: [SharedMediaNativePairFileState]) async throws -> [SharedMediaPhotoRetirementInspection] {
        var proofs: [SharedMediaPhotoRetirementInspection] = []
        for state in states {
            let intent = try state.intent()
            for file in [intent.preparation.original.file, try state.file(intent.ai.id), try state.file(intent.display.id)] {
                try validate()
                let proof = try await io.inspect(file)
                try validate(); try verify(proof); proofs.append(proof)
            }
        }
        return proofs
    }
    private func readResult(_ r: SharedMediaNativeAppReceivingRequest, immediate: Bool = false) throws -> SharedMediaNativeConsumerCohort {
        try boundary(.beforeReadback)
        let current = try authority.header(container), successor = try SharedMediaNativeAppMetadataFacts.successor(r.header)
        if immediate {
            guard current == successor else { throw SharedMediaStorageFailure.stale }
        } else {
            // Unrelated packages may legitimately advance the shared inventory.
            // The complete exact saved set is recovered under this operation's
            // freshly audited stable scope, never a historical global revision.
            guard current == expected, current.inventory.generation == successor.inventory.generation,
                  current.inventory.revision >= successor.inventory.revision,
                  current.inventory.phase == successor.inventory.phase, current.inventory.cursor == successor.inventory.cursor,
                  current.bootstrapID == successor.bootstrapID, current.bootstrapGeneration == successor.bootstrapGeneration,
                  current.bootstrapContract == successor.bootstrapContract, current.bootstrapRevision == successor.bootstrapRevision else {
                throw SharedMediaStorageFailure.stale
            }
        }
        let c = fresh(), (_, package, member) = try target(c, r.package.id)
        guard SharedMediaNativeAppMetadataFacts.Package(package) == (try r.frozenPackage()),
              SharedMediaNativeAppMetadataFacts.Member(member) == r.member,
              let rows = try SharedMediaNativeReceivingRows.read(r, in: c, absent: false),
              try SharedMediaNativeConsumerGraph.validateScoped(rows.consumer, context: c, format: .appV2) == r.cohort else { throw SharedMediaStorageFailure.conflict }
        return r.cohort
    }
    private func requirePrestate(_ r: SharedMediaNativeAppReceivingRequest, context c: ModelContext,
                                 package: PhotoPreparationRecord, member: SharedMediaPendingMembershipRecord) throws {
        guard SharedMediaNativeAppMetadataFacts.Package(package) == r.package,
              SharedMediaNativeAppMetadataFacts.Member(member) == r.member,
              try SharedMediaNativeAppMetadataFacts.capture(c, profile: authority.profile) == facts,
              facts.consumers[r.package.id] == nil else { throw SharedMediaStorageFailure.stale }
        _ = try SharedMediaNativeReceivingRows.read(r, in: c, absent: true)
    }
    private func target(_ c: ModelContext, _ id: UUID) throws -> (SharedMediaInventoryRecord, PhotoPreparationRecord, SharedMediaPendingMembershipRecord) {
        let inventoryID = authority.profile.inventoryID
        return (try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID })),
            try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id })),
            try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id })))
    }
    private func fresh() -> ModelContext { let c = ModelContext(container); c.autosaveEnabled = false; return c }
    private func validate() throws {
        try Task.checkCancellation()
        guard !consumed, try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
    }
}

/// Only the receiving owner can mint this exact two-update/four-insert proof.
@MainActor
struct SharedMediaNativeAppReceivingPoststate {
    let request: SharedMediaNativeAppReceivingRequest
    private let facts: SharedMediaNativeAppMetadataFacts
    private let inventoryIdentity: PersistentIdentifier, packageIdentity: PersistentIdentifier
    private let inserted: Set<PersistentIdentifier>
    var profile: SharedMediaNativeAppProfile { request.profile }
    fileprivate init(request: SharedMediaNativeAppReceivingRequest, facts: SharedMediaNativeAppMetadataFacts,
                     inventory: PersistentIdentifier, package: PersistentIdentifier, inserted: Set<PersistentIdentifier>) {
        self.request = request; self.facts = facts; inventoryIdentity = inventory; packageIdentity = package; self.inserted = inserted
    }
    func validate(context c: ModelContext, inventory: SharedMediaInventoryRecord) throws {
        let updates = Set(c.changedModelsArray.map(\.persistentModelID))
        guard c.deletedModelsArray.isEmpty, c.insertedModelsArray.count == 4,
              Set(c.insertedModelsArray.map(\.persistentModelID)) == inserted,
              updates.subtracting(inserted) == Set([inventoryIdentity, packageIdentity]),
              inventory.persistentModelID == inventoryIdentity,
              try SharedMediaNativeAppEligibility.profile(inventory) == profile,
              inventory.revision == (try request.freeze.commit.inventoryRevision),
              let rows = try SharedMediaNativeReceivingRows.read(request, in: c, absent: false), rows.identities == inserted else { throw SharedMediaStorageFailure.conflict }
        try facts.validateReceiving(c, request: request)
    }
    func receivingBytes(_ consumer: SharedMediaConsumerRecord, context: ModelContext, inventory: SharedMediaInventoryRecord) throws -> Int64 {
        _ = try SharedMediaNativeConsumerGraph.validateReceivingPoststate(consumer, context: context, inventory: inventory, proof: self)
        return Int64(consumer.cohortData.count)
    }
}

/// Only the receiving file can prove this one-insert/one-update transition.
@MainActor
struct SharedMediaNativeAppStagingPoststate {
    let profile: SharedMediaNativeAppProfile
    private let facts: SharedMediaNativeAppMetadataFacts
    private let header: SharedMediaNativeAppEligibility.Header
    private let row: SharedMediaNativeReceivingIntentGraph.Row
    private let inventoryIdentity: PersistentIdentifier, inserted: PersistentIdentifier
    fileprivate init(facts: SharedMediaNativeAppMetadataFacts, header: SharedMediaNativeAppEligibility.Header,
                     row: SharedMediaNativeReceivingIntentGraph.Row, inventory: PersistentIdentifier, inserted: PersistentIdentifier) {
        self.facts = facts; profile = facts.profile; self.header = header; self.row = row
        inventoryIdentity = inventory; self.inserted = inserted
    }
    func validate(context: ModelContext, inventory: SharedMediaInventoryRecord) throws {
        let changed = Set(context.changedModelsArray.map(\.persistentModelID))
        guard context.deletedModelsArray.isEmpty, context.insertedModelsArray.count == 1,
              Set(context.insertedModelsArray.map(\.persistentModelID)) == [inserted],
              changed.subtracting([inserted]) == [inventoryIdentity], inventory.persistentModelID == inventoryIdentity,
              try SharedMediaNativeAppEligibility.profile(inventory) == profile,
              inventory.revision == (try SharedMediaStoragePolicy.add(header.inventory.revision, 1)) else {
            throw SharedMediaStorageFailure.conflict
        }
        try facts.validateStaging(context, adding: row)
    }
}
