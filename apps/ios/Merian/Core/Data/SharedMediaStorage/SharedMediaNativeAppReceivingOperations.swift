import Foundation
import SwiftData
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
    private let verifyCompletion: (SharedMediaNativePairCompletion) throws -> Void
    private let received: (SharedMediaNativeReceivingIntentGraph.Row, SharedMediaNativeAppProfile) throws -> Void
    private var consumed = false
    private init(container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                 expected: SharedMediaNativeAppEligibility.Header, facts: SharedMediaNativeAppMetadataFacts,
                 io: SharedMediaNativeOriginalIO, binding: SharedMediaNativeBinding, availableBytes: @escaping () throws -> Int64,
                 boundary: @escaping (SharedMediaNativeMetadataBoundary) throws -> Void,
                 received: @escaping (SharedMediaNativeReceivingIntentGraph.Row, SharedMediaNativeAppProfile) throws -> Void,
                 verifyCompletion: @escaping (SharedMediaNativePairCompletion) throws -> Void,
                 verify: @escaping (SharedMediaPhotoRetirementInspection) throws -> Void) {
        self.container = container; self.authority = authority; self.expected = expected; self.facts = facts
        self.io = io; self.binding = binding; self.availableBytes = availableBytes; self.boundary = boundary; self.verify = verify; self.received = received
        self.verifyCompletion = verifyCompletion
    }
    static func audited(container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                        io: SharedMediaNativeOriginalIO, binding: SharedMediaNativeBinding, availableBytes: @escaping () throws -> Int64,
                        boundary: @escaping (SharedMediaNativeMetadataBoundary) throws -> Void,
                        received: @escaping (SharedMediaNativeReceivingIntentGraph.Row, SharedMediaNativeAppProfile) throws -> Void,
                        verifyCompletion: @escaping (SharedMediaNativePairCompletion) throws -> Void,
                        verify: @escaping (SharedMediaPhotoRetirementInspection) throws -> Void) async throws -> SharedMediaNativeAppReceivingOperations {
        let expected = try authority.header(container)
        _ = try await SharedMediaNativeScopedAudit(app: container, profile: authority.profile, expected: expected.inventory,
            check: { guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale } },
            betweenPages: { await Task.yield() }).run()
        guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
        let context = ModelContext(container); context.autosaveEnabled = false
        return .init(container: container, authority: authority, expected: expected,
            facts: try SharedMediaNativeAppMetadataFacts.capture(context, profile: authority.profile), io: io,
            binding: binding, availableBytes: availableBytes, boundary: boundary, received: received, verifyCompletion: verifyCompletion, verify: verify)
    }
    func request(packageID: UUID, pairIDs: [UUID], operationID: UUID, queueID: UUID, observationID: UUID,
                 bindingID: UUID, generation: UUID, eventID: UUID, timestamp: Date) async throws -> SharedMediaNativeAppReceivingRequest {
        try await prepareRequest(packageID: packageID, pairIDs: pairIDs, operationID: operationID, queueID: queueID,
            observationID: observationID, bindingID: bindingID, generation: generation, eventID: eventID, timestamp: timestamp).0
    }
    private func prepareRequest(packageID: UUID, pairIDs: [UUID], operationID: UUID, queueID: UUID, observationID: UUID,
                                bindingID: UUID, generation: UUID, eventID: UUID, timestamp: Date,
                                intentRevision: Int64? = nil, restagedFromSHA256: String? = nil, photoAdmission: SharedMediaNativePhotoAdmission? = nil) async throws
        -> (SharedMediaNativeAppReceivingRequest, [SharedMediaPhotoRetirementInspection]) {
        try validate(); try facts.requireMutable(packageID)
        let c = fresh(), cRows = try target(c, packageID), inventory = cRows.inventory, package = cRows.package, member = cRows.member
        let states = try SharedMediaNativeFreezeFacts.states(context: c, inventory: inventory, package: package, member: member, pairIDs: pairIDs)
        let proofs = try await SharedMediaNativeAppReceivingIO.inspect(states, io: io, check: validate, verify: verify)
        let freeze = try SharedMediaNativeFreezeFacts.request(context: c, inventory: inventory, package: package, member: member,
            binding: binding, operationID: operationID, pairIDs: pairIDs, proofs: proofs)
        let prepared = try SharedMediaNativeReceivingIntent.Prepared(profile: authority.profile,
            package: .init(package), member: .init(member), cohort: freeze.commit.cohort,
            operationID: operationID, queueID: queueID, observationID: observationID, bindingID: bindingID,
            generation: generation, eventID: eventID, timestamp: timestamp,
            intentRevision: intentRevision, restagedFromSHA256: restagedFromSHA256, photoAdmission: photoAdmission)
        let request = SharedMediaNativeAppReceivingRequest(try prepared.descriptorForTransaction(header: expected))
        _ = try SharedMediaNativeReceivingRows.read(request, in: fresh(), absent: true)
        try validate(); return (request, proofs)
    }
    /// The old unstaged entry point is recovery-only. Fresh receiving requires
    /// a persisted P2 slot; constructing an old descriptor grants no admission.
    func apply(_ request: SharedMediaNativeAppReceivingRequest) async throws -> SharedMediaNativeConsumerCohort {
        if request.cohort.format == .intentReceiving {
            return try await receivePrepared(.init(request))
        }
        try validate()
        guard request.profile == authority.profile else { throw SharedMediaStorageFailure.conflict }
        let saved = try readResult(request)
        try validate(); consumed = true
        return saved
    }
    func stage(packageID: UUID, draftGeneration: UUID, pairIDs: [UUID],
               identity: SharedMediaNativeReceivingStageIdentity,
               expectedMetadata: SharedMediaNativeAppMetadataRequest? = nil, photoAdmission: SharedMediaNativePhotoAdmission? = nil,
               beforeImmutableSave: () throws -> Void = {}) async throws -> SharedMediaNativeReceivingIntent.Prepared {
        try validate()
        let initial = fresh(), initialInventory = try target(initial, packageID).inventory
        let saved = try SharedMediaNativeReceivingPhaseGraph.pending(initial, inventory: initialInventory)[packageID]
        if let bytes = identity.savedBytes {
            guard let saved, saved.row.preparedData == bytes, case .prepared(let prepared) = saved.slot else {
                throw SharedMediaStorageFailure.stale
            }
            try prepared.requireSelection(draftGeneration: draftGeneration, pairIDs: pairIDs)
            try expectedMetadata?.requireReceivingSelection(prepared)
            try photoAdmission?.requireSaved(prepared.photoAdmission)
            consumed = true; return prepared
        }
        // A concurrent saved slot must be rediscovered with its own locks and IDs.
        guard saved == nil else { throw SharedMediaStorageFailure.stale }
        let (request, proofs) = try await prepareRequest(packageID: packageID, pairIDs: pairIDs,
            operationID: identity.operationID, queueID: identity.queueID, observationID: identity.observationID,
            bindingID: identity.bindingID, generation: identity.generation, eventID: identity.eventID, timestamp: identity.timestamp,
            intentRevision: 0, photoAdmission: photoAdmission)
        let prepared = try SharedMediaNativeReceivingIntent.Prepared(request)
        try prepared.requireSelection(draftGeneration: draftGeneration, pairIDs: pairIDs)
        try expectedMetadata?.requireReceivingSelection(prepared)
        let c = fresh(), cRows = try target(c, packageID), inventory = cRows.inventory, package = cRows.package, member = cRows.member
        try requirePrestate(request, context: c, package: package, member: member)
        let states = try SharedMediaNativeReceivingIntentGraph.currentCohort(prepared, context: c, inventory: inventory)
        let frozen = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes)
        let originals = try SharedMediaNativeAppReceivingIO.originalFacts(frozen, context: c, inventoryID: authority.profile.inventoryID)
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
        row.schemaVersion = prepared.version; row.revision = prepared.intentRevision ?? 0
        c.insert(row); inventory.revision = try SharedMediaStoragePolicy.add(expected.inventory.revision, 1)
        let proof = SharedMediaNativeAppStagingPoststate(facts: facts, header: expected,
            row: .init(row), inventory: inventory.persistentModelID, inserted: row.persistentModelID)
        let after = try SharedMediaNativeAcquisitionBudget.evaluateStagingPoststate(context: c, inventory: inventory, proof: proof)
        guard after.metadataByPackage[packageID] == projection.charged else { throw SharedMediaStorageFailure.conflict }
        try after.totals.checkAvailable(availableBytes(), additionalReservation: added)
        try boundary(.beforeSave); try validate(); try proof.validate(context: c, inventory: inventory)
        let current = fresh(), currentRows = try target(current, packageID), oldInventory = currentRows.inventory, oldPackage = currentRows.package, oldMember = currentRows.member
        try requirePrestate(request, context: current, package: oldPackage, member: oldMember)
        try requireFreshReceivingIdentity(prepared, context: current)
        guard try SharedMediaNativeFreezeFacts.request(context: current, inventory: oldInventory, package: oldPackage,
            member: oldMember, binding: binding, operationID: prepared.operationID, pairIDs: pairIDs, proofs: proofs) == request.freeze else {
            throw SharedMediaStorageFailure.stale
        }
        _ = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: current, inventory: oldInventory,
            ownerID: authority.profile.ownerID, format: .appV2)
        guard try SharedMediaNativeAppReceivingIO.originalFacts(frozen, context: current, inventoryID: authority.profile.inventoryID) == originals else { throw SharedMediaStorageFailure.stale }
        try after.totals.checkAvailable(availableBytes(), additionalReservation: added)
        for observation in proofs { try verify(observation) }
        // The final physical seals, current authorization and save are synchronous under retained locks.
        try beforeImmutableSave(); consumed = true
        do {
            try c.save(); try boundary(.afterSave)
            return try stagedResult(prepared)
        } catch {
            let failure = error; c.rollback()
            do { return try stagedResult(prepared) } catch { throw failure }
        }
    }
    private func requireFreshReceivingIdentity(_ prepared: SharedMediaNativeReceivingIntent.Prepared,
                                               context: ModelContext) throws {
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        try SharedMediaNativeTerminalScan.requireAbsent([prepared.operationID, prepared.queueID,
            prepared.observationID, prepared.bindingID, prepared.generation, prepared.eventID],
            container: context.container, inventoryID: prepared.profile.inventoryID)
    }
    private func stagedResult(_ prepared: SharedMediaNativeReceivingIntent.Prepared) throws -> SharedMediaNativeReceivingIntent.Prepared {
        try boundary(.beforeReadback)
        guard try authority.header(container) == SharedMediaNativeAppMetadataFacts.successor(expected) else {
            throw SharedMediaStorageFailure.stale
        }
        let c = fresh(), inventory = try target(c, prepared.package.id).inventory
        guard let found = try SharedMediaNativeReceivingPhaseGraph.pending(c, inventory: inventory)[prepared.package.id],
              found.row.preparedData == (try prepared.encoded()), case .prepared(let saved) = found.slot else {
            throw SharedMediaStorageFailure.conflict
        }
        try facts.validateStaging(c, adding: found.row)
        return saved
    }
    func readRetainedPhotos(_ prepared: SharedMediaNativeReceivingIntent.Prepared, role: SharedMediaNativeRetainedPhotoReadback.Role) async throws -> SharedMediaNativeRetainedPhotoReadback {
        try await SharedMediaNativeAppReceivingIO.readRetained(prepared, role: role, container: container, io: io, verify: verifyCompletion) {
            try self.boundary(.beforeReadback); try self.validate()
            guard prepared.profile == self.authority.profile else { throw SharedMediaStorageFailure.stale }
        }
    }
    func readReceivedPhotos(_ prepared: SharedMediaNativeReceivingIntent.Prepared) async throws -> SharedMediaNativeReceivedPhotoReadback {
        try await SharedMediaNativeAppReceivingIO.read(prepared, container: container, io: io, verify: verifyCompletion,
            current: originalPreviewAccess(prepared).current)
    }
    func originalPreviewAccess(_ prepared: SharedMediaNativeReceivingIntent.Prepared) -> SharedMediaNativeOriginalPreviewAccess {
        .init(prepared: prepared, io: io, verify: verify, current: {
            try Task.checkCancellation(); try self.boundary(.beforeReadback); try self.validate()
            guard prepared.profile == self.authority.profile, let value = try self.exactReceived(prepared) else { throw SharedMediaStorageFailure.stale }
            return value
        })
    }
    private func readResult(_ r: SharedMediaNativeAppReceivingRequest) throws -> SharedMediaNativeConsumerCohort {
        try boundary(.beforeReadback)
        let current = try authority.header(container), successor = try SharedMediaNativeAppMetadataFacts.successor(r.header)
        // Unrelated packages may advance the inventory. Recover the complete
        // saved set within the freshly audited scope, never an old global revision.
        guard current == expected, current.inventory.generation == successor.inventory.generation,
              current.inventory.revision >= successor.inventory.revision,
              current.inventory.phase == successor.inventory.phase, current.inventory.cursor == successor.inventory.cursor,
              current.bootstrapID == successor.bootstrapID, current.bootstrapGeneration == successor.bootstrapGeneration,
              current.bootstrapContract == successor.bootstrapContract, current.bootstrapRevision == successor.bootstrapRevision else {
            throw SharedMediaStorageFailure.stale
        }
        let c = fresh(), cRows = try target(c, r.package.id), package = cRows.package, member = cRows.member
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
    private struct Target {
        let inventory: SharedMediaInventoryRecord
        let package: PhotoPreparationRecord
        let member: SharedMediaPendingMembershipRecord
    }
    private func target(_ c: ModelContext, _ id: UUID) throws -> Target {
        let inventoryID = authority.profile.inventoryID
        return .init(inventory: try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID })),
            package: try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id })),
            member: try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id })))
    }
    private func fresh() -> ModelContext { let c = ModelContext(container); c.autosaveEnabled = false; return c }
    private func validate() throws {
        try Task.checkCancellation()
        guard !consumed, try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
    }
}
/// Only the receiving file can prove this one-insert/one-update transition.
@MainActor
struct SharedMediaNativeAppStagingPoststate {
    var allocationPeers: [UUID: SharedMediaNativePhotoAllocationPeer] { facts.allocationPeers }
    var predecessorRevision: Int64 { header.inventory.revision }
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
    func receivingBytes(_ consumer: SharedMediaConsumerRecord) throws -> Int64 { try facts.receivingBytes(consumer) }
}

/// Three distinct exact transitions. Only this owner file can construct one;
/// there is no caller-selected generic dirty-context exemption.
@MainActor
struct SharedMediaNativeAppIntentPoststate {
    var allocationPeers: [UUID: SharedMediaNativePhotoAllocationPeer] { facts.allocationPeers }
    var predecessorRevision: Int64 { header.inventory.revision }
    fileprivate enum Transition {
        case receive(SharedMediaNativeAppReceivingRequest)
        case abandon(SharedMediaNativeReceivingIntent.Prepared, SharedMediaNativeReceivingIntent.Abandoned)
        case restage(SharedMediaNativeReceivingIntent.Prepared)
    }
    private let transition: Transition
    private let facts: SharedMediaNativeAppMetadataFacts
    private let header: SharedMediaNativeAppEligibility.Header
    private let row: SharedMediaNativeReceivingIntentGraph.Row
    private let inventoryID: PersistentIdentifier, packageID: PersistentIdentifier, slotID: PersistentIdentifier
    private let inserts: Set<PersistentIdentifier>
    var profile: SharedMediaNativeAppProfile { facts.profile }
    fileprivate init(transition: Transition, facts: SharedMediaNativeAppMetadataFacts,
                     header: SharedMediaNativeAppEligibility.Header, row: SharedMediaReceivingIntentRecord,
                     inventory: SharedMediaInventoryRecord, package: PhotoPreparationRecord,
                     inserts: Set<PersistentIdentifier> = []) {
        self.transition = transition; self.facts = facts; self.header = header; self.row = .init(row)
        inventoryID = inventory.persistentModelID; packageID = package.persistentModelID
        slotID = row.persistentModelID; self.inserts = inserts
    }
    func validate(context c: ModelContext, inventory: SharedMediaInventoryRecord) throws {
        try validateValues(context: c, inventory: inventory, checkWriteSet: true)
    }
    fileprivate func validatePersisted(context c: ModelContext, inventory: SharedMediaInventoryRecord) throws {
        guard !c.hasChanges else { throw SharedMediaStorageFailure.conflict }
        try validateValues(context: c, inventory: inventory, checkWriteSet: false)
    }
    private func validateValues(context c: ModelContext, inventory: SharedMediaInventoryRecord, checkWriteSet: Bool) throws {
        guard let before = facts.intents[row.id], let oldPackage = facts.packages[row.id],
              let current = try SharedMediaNativeReceivingPhaseGraph.row(row.id, in: c),
              SharedMediaNativeReceivingIntentGraph.Row(current) == row,
              current.persistentModelID == slotID, inventory.persistentModelID == inventoryID,
              try SharedMediaNativeAppEligibility.profile(inventory) == profile,
              inventory.revision == (try SharedMediaStoragePolicy.add(header.inventory.revision, 1)),
              c.deletedModelsArray.isEmpty else { throw SharedMediaStorageFailure.conflict }
        if checkWriteSet {
            guard Set(c.insertedModelsArray.map(\.persistentModelID)) == inserts,
                  c.insertedModelsArray.count == inserts.count else { throw SharedMediaStorageFailure.conflict }
        }
        let prior = try SharedMediaNativeReceivingSlot.decode(before, profile: profile)
        let next = try SharedMediaNativeReceivingSlot.decode(row, profile: profile)
        let expectedPackage: SharedMediaNativeAppMetadataFacts.Package
        let consumer: SharedMediaConsumerRecord?
        let updates: Set<PersistentIdentifier>
        switch transition {
        case .receive(let request):
            guard case .prepared(let prepared) = prior, prepared.version == 2,
                  case .received(_, _, let transaction) = next,
                  before.preparedData == row.preparedData,
                  try SharedMediaNativeReceivingIntent.canonicalRequest(transaction) == SharedMediaNativeReceivingIntent.canonicalRequest(.init(request)),
                  request.header == header, request.package == oldPackage,
                  let rows = try SharedMediaNativeReceivingRows.read(request, in: c, absent: false),
                  !checkWriteSet || rows.identities == inserts, inserts.count == 4 else { throw SharedMediaStorageFailure.conflict }
            // Inserted SwiftData identifiers may be promoted by save. The
            // persisted read above proves logical IDs and every row field;
            // identifier equality belongs only to the pre-save write set.
            expectedPackage = try request.frozenPackage(); consumer = rows.consumer
            updates = [inventoryID, packageID, slotID]
        case .abandon(let prepared, let result):
            guard case .prepared = prior, case .abandoned(let saved) = next,
                  before.preparedData == (try prepared.encoded()),
                  saved == result, result == (try .init(prepared: prepared, header: header)),
                  oldPackage == prepared.package, inserts.isEmpty else { throw SharedMediaStorageFailure.conflict }
            try SharedMediaNativeReceivingRows.requireAbsent(.init(prepared), in: c)
            expectedPackage = try oldPackage.successor(oldPackage.envelope); consumer = nil
            updates = [inventoryID, packageID, slotID]
        case .restage(let prepared):
            guard case .abandoned(let abandoned) = prior, case .prepared = next,
                  prepared.version == 2, prepared.package == oldPackage,
                  prepared.restagedFromSHA256 == (try SharedMediaAcquisitionEncoding.digest(abandoned.encoded())),
                  row.preparedData == (try prepared.encoded()),
                  row.revision == (try SharedMediaStoragePolicy.add(abandoned.revision, 1)), inserts.isEmpty,
                  Set([prepared.operationID, prepared.queueID, prepared.observationID, prepared.bindingID, prepared.generation, prepared.eventID])
                    .isDisjoint(with: [abandoned.operationID, abandoned.queueID, abandoned.observationID, abandoned.bindingID, abandoned.generation, abandoned.eventID]) else {
                throw SharedMediaStorageFailure.conflict
            }
            try SharedMediaNativeReceivingRows.requireAbsent(.init(prepared), in: c)
            expectedPackage = oldPackage; consumer = nil
            updates = [inventoryID, slotID]
        }
        guard !checkWriteSet || Set(c.changedModelsArray.map(\.persistentModelID)).subtracting(inserts) == updates else {
            throw SharedMediaStorageFailure.conflict
        }
        try facts.validateIntentTransition(c, row: row, package: expectedPackage, consumer: consumer)
    }
    func receivingBytes(_ consumer: SharedMediaConsumerRecord, context: ModelContext,
                        inventory: SharedMediaInventoryRecord) throws -> Int64 {
        if case .receive = transition, consumer.packageID == row.id {
            _ = try SharedMediaNativeConsumerGraph.validateIntentPoststate(consumer, context: context, inventory: inventory, proof: self)
            return Int64(consumer.cohortData.count)
        }
        return try facts.receivingBytes(consumer)
    }
}
@MainActor
private extension SharedMediaNativeAppReceivingOperations {
    typealias Intent = SharedMediaNativeReceivingIntent
    func requirePrepared(_ prepared: Intent.Prepared, context c: ModelContext,
                         inventory: SharedMediaInventoryRecord) throws -> SharedMediaReceivingIntentRecord {
        let id = prepared.package.id
        guard prepared.profile == authority.profile,
              let row = try SharedMediaNativeReceivingPhaseGraph.row(id, in: c),
              facts.intents[id] == .init(row),
              case .prepared = try SharedMediaNativeReceivingSlot.decode(.init(row), profile: authority.profile),
              row.preparedData == (try prepared.encoded()),
              try SharedMediaNativeAppMetadataFacts.capture(c, profile: authority.profile) == facts else {
            throw SharedMediaStorageFailure.stale
        }
        _ = try SharedMediaNativeReceivingIntentGraph.currentCohort(prepared, context: c, inventory: inventory)
        try SharedMediaNativeReceivingRows.requireAbsent(.init(prepared), in: c)
        return row
    }
    func exactReceived(_ prepared: Intent.Prepared) throws -> SharedMediaNativeConsumerCohort? {
        let c = fresh(), inventory = try target(c, prepared.package.id).inventory
        guard let row = try SharedMediaNativeReceivingPhaseGraph.row(prepared.package.id, in: c) else {
            throw SharedMediaStorageFailure.stale
        }
        let slot = try SharedMediaNativeReceivingSlot.decode(.init(row), profile: authority.profile)
        guard case .received(_, _, let transaction) = slot else { return nil }
        guard row.preparedData == (try prepared.encoded()) else { throw SharedMediaStorageFailure.stale }
        let rows = try SharedMediaNativeReceivingPhaseGraph.receivedRows(transaction, context: c)
        _ = try SharedMediaNativeConsumerGraph.validateScoped(rows.consumer, context: c, format: .appV2)
        guard inventory.revision >= (try transaction.freeze.commit.inventoryRevision) else { throw SharedMediaStorageFailure.stale }
        return transaction.cohort
    }
    func exactAbandoned(_ prepared: Intent.Prepared) throws -> Intent.Abandoned? {
        let c = fresh(), cRows = try target(c, prepared.package.id), inventory = cRows.inventory, package = cRows.package, member = cRows.member
        guard let row = try SharedMediaNativeReceivingPhaseGraph.row(prepared.package.id, in: c) else {
            throw SharedMediaStorageFailure.stale
        }
        guard case .abandoned(let result) = try SharedMediaNativeReceivingSlot.decode(.init(row), profile: authority.profile) else { return nil }
        guard result.preparedSHA256 == (try SharedMediaAcquisitionEncoding.digest(prepared.encoded())),
              result == (try Intent.Abandoned(prepared: prepared, header: result.preHeader)),
              inventory.revision >= (try SharedMediaStoragePolicy.add(result.preHeader.inventory.revision, 1)) else {
            throw SharedMediaStorageFailure.stale
        }
        try result.requireSuccessor(package: .init(package), member: .init(member))
        try SharedMediaNativeReceivingRows.requireAbsent(.init(result), in: c)
        return result
    }
    func afterIntentSave<T>(_ context: ModelContext, proof: SharedMediaNativeAppIntentPoststate, onAcknowledged: () -> Void = {},
                            recover: () throws -> T) throws -> T {
        consumed = true
        func readback() throws -> T {
            try boundary(.beforeReadback)
            guard try authority.header(container) == SharedMediaNativeAppMetadataFacts.successor(expected) else {
                throw SharedMediaStorageFailure.stale
            }
            let c = fresh(), id = authority.profile.inventoryID
            let inventory = try SharedMediaNativePairPlanGraph.one(c,
                FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
            // The original dirty write-set proof is checked before save; fresh
            // readback verifies exact persisted values through recover().
            guard inventory.revision == (try SharedMediaStoragePolicy.add(expected.inventory.revision, 1)) else {
                throw SharedMediaStorageFailure.stale
            }
            try proof.validatePersisted(context: c, inventory: inventory)
            return try recover()
        }
        do { try context.save(); try boundary(.afterSave); let result = try readback(); onAcknowledged(); return result } catch {
            let failure = error; context.rollback()
            do { return try readback() } catch { throw failure }
        }
    }
}
@MainActor
extension SharedMediaNativeAppReceivingOperations {
    func receivePrepared(_ prepared: SharedMediaNativeReceivingIntent.Prepared, onFresh: () -> Void = {}) async throws -> SharedMediaNativeConsumerCohort {
        try validate()
        guard prepared.version == 2, prepared.profile == authority.profile,
              prepared.intentRevision == 0 || prepared.restagedFromSHA256 != nil else { throw SharedMediaStorageFailure.closed }
        if let saved = try exactReceived(prepared) { try validate(); consumed = true; return saved }
        let c = fresh(), cRows = try target(c, prepared.package.id), inventory = cRows.inventory, package = cRows.package, member = cRows.member
        let slot = try requirePrepared(prepared, context: c, inventory: inventory)
        let transaction = try prepared.descriptorForTransaction(header: expected)
        let request = SharedMediaNativeAppReceivingRequest(transaction)
        let states = try SharedMediaNativeReceivingIntentGraph.currentCohort(prepared, context: c, inventory: inventory)
        let proofs = try await SharedMediaNativeAppReceivingIO.inspect(states, io: io, check: validate, verify: verify)
        let frozen = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes)
        let ids = try frozen.entries.map { try SharedMediaNativeDerivativeIntent.decode($0.intent.bytes).pairID }
        guard try SharedMediaNativeFreezeFacts.request(context: c, inventory: inventory, package: package, member: member,
            binding: binding, operationID: prepared.operationID, pairIDs: ids, proofs: proofs) == request.freeze else {
            throw SharedMediaStorageFailure.stale
        }
        let originals = try SharedMediaNativeAppReceivingIO.originalFacts(frozen, context: c, inventoryID: authority.profile.inventoryID)
        let before = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inventory,
            ownerID: authority.profile.ownerID, format: .appV2)
        guard let base = before.baseMetadataByPackage[prepared.package.id] else { throw SharedMediaStorageFailure.conflict }
        let reservation = try SharedMediaNativeReceivingReservation.maximum(prepared, currentMetadata: base, pairStates: states)
        let materialized = try SharedMediaNativeReceivingReservation.materialized(prepared, header: expected,
            currentMetadata: base, pairStates: states, reservation: reservation)
        let result = try SharedMediaNativeReceivingIntent.Received(prepared: prepared, request: request)
        let resultBytes = try result.encoded(prepared: prepared), nextPackage = try request.frozenPackage()
        package.supportingContextData = nextPackage.envelope; package.phaseRaw = nextPackage.phase; package.revision = nextPackage.revision
        slot.phaseRaw = "received"; slot.revision = try SharedMediaStoragePolicy.add(slot.revision, 1)
        slot.resultData = resultBytes; slot.resultSHA256 = SharedMediaAcquisitionEncoding.digest(resultBytes)
        inventory.revision = try SharedMediaStoragePolicy.add(expected.inventory.revision, 1)
        let rows = try SharedMediaNativeReceivingRows.insert(request, in: c)
        let proof = SharedMediaNativeAppIntentPoststate(transition: .receive(request), facts: facts, header: expected,
            row: slot, inventory: inventory, package: package, inserts: rows.identities)
        let after = try SharedMediaNativeAcquisitionBudget.evaluateIntentPoststate(context: c, inventory: inventory, proof: proof)
        guard after.metadataByPackage[prepared.package.id] == materialized else { throw SharedMediaStorageFailure.conflict }
        let added = try PhotoPreparationPolicy.add([Int64(resultBytes.count), Int64(rows.consumer.cohortData.count),
            Int64(request.metadata.utf8.count), Int64(request.metadata.utf8.count), Int64(nextPackage.envelope.count - prepared.package.envelope.count)])
        try after.totals.checkAvailable(availableBytes(), additionalReservation: added)
        try boundary(.beforeSave); try validate(); try proof.validate(context: c, inventory: inventory)
        let current = fresh(), currentRows = try target(current, prepared.package.id), oldInventory = currentRows.inventory, oldPackage = currentRows.package, oldMember = currentRows.member
        _ = try requirePrepared(prepared, context: current, inventory: oldInventory)
        guard try SharedMediaNativeFreezeFacts.request(context: current, inventory: oldInventory, package: oldPackage, member: oldMember,
            binding: binding, operationID: prepared.operationID, pairIDs: ids, proofs: proofs) == request.freeze,
              try SharedMediaNativeAppReceivingIO.originalFacts(frozen, context: current, inventoryID: authority.profile.inventoryID) == originals else { throw SharedMediaStorageFailure.stale }
        try after.totals.checkAvailable(availableBytes(), additionalReservation: added)
        for observation in proofs { try verify(observation) }
        var acknowledgedHere = false
        let saved = try afterIntentSave(c, proof: proof, onAcknowledged: { acknowledgedHere = true }) {
            guard let saved = try self.exactReceived(prepared) else { throw SharedMediaStorageFailure.conflict }
            return saved
        }
        guard let acknowledged = try SharedMediaNativeReceivingPhaseGraph.row(prepared.package.id, in: fresh()) else {
            throw SharedMediaStorageFailure.closed
        }
        try received(.init(acknowledged), authority.profile)
        if acknowledgedHere { onFresh() }; return saved
    }

    func abandonPrepared(_ prepared: SharedMediaNativeReceivingIntent.Prepared) throws -> SharedMediaNativeReceivingIntent.Abandoned {
        try validate()
        guard prepared.profile == authority.profile else { throw SharedMediaStorageFailure.conflict }
        if let saved = try exactAbandoned(prepared) { try validate(); consumed = true; return saved }
        let c = fresh(), cRows = try target(c, prepared.package.id), inventory = cRows.inventory, package = cRows.package
        let slot = try requirePrepared(prepared, context: c, inventory: inventory)
        let states = try SharedMediaNativeReceivingIntentGraph.currentCohort(prepared, context: c, inventory: inventory)
        let before = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inventory,
            ownerID: authority.profile.ownerID, format: .appV2)
        guard let base = before.baseMetadataByPackage[prepared.package.id] else { throw SharedMediaStorageFailure.conflict }
        let reservation = try SharedMediaNativeReceivingReservation.maximum(prepared, currentMetadata: base, pairStates: states)
        let materialized = try SharedMediaNativeReceivingReservation.materializedAbandoned(prepared, header: expected,
            currentMetadata: base, pairStates: states, reservation: reservation)
        let result = try SharedMediaNativeReceivingIntent.Abandoned(prepared: prepared, header: expected)
        let bytes = try result.encoded()
        package.revision = result.package.revision
        slot.phaseRaw = "abandoned"; slot.revision = result.revision; slot.preparedData = nil
        slot.resultData = bytes; slot.resultSHA256 = SharedMediaAcquisitionEncoding.digest(bytes)
        inventory.revision = try SharedMediaStoragePolicy.add(expected.inventory.revision, 1)
        let proof = SharedMediaNativeAppIntentPoststate(transition: .abandon(prepared, result), facts: facts,
            header: expected, row: slot, inventory: inventory, package: package)
        let after = try SharedMediaNativeAcquisitionBudget.evaluateIntentPoststate(context: c, inventory: inventory, proof: proof)
        guard after.metadataByPackage[prepared.package.id] == materialized else { throw SharedMediaStorageFailure.conflict }
        let added = max(0, Int64(bytes.count) - Int64(try prepared.encoded().count))
        try after.totals.checkAvailable(availableBytes(), additionalReservation: added)
        try boundary(.beforeSave); try validate(); try proof.validate(context: c, inventory: inventory)
        let current = fresh(), oldInventory = try target(current, prepared.package.id).inventory
        _ = try requirePrepared(prepared, context: current, inventory: oldInventory)
        try after.totals.checkAvailable(availableBytes(), additionalReservation: added)
        return try afterIntentSave(c, proof: proof) {
            guard let saved = try self.exactAbandoned(prepared) else { throw SharedMediaStorageFailure.conflict }
            return saved
        }
    }
}
@MainActor
extension SharedMediaNativeAppReceivingOperations {
    func restage(_ identity: NativeReceivingRestageIdentity, draftGeneration: UUID,
                 pairIDs: [UUID]) async throws -> SharedMediaNativeReceivingIntent.Prepared {
        try validate()
        let packageID = identity.predecessor.package.id
        guard identity.predecessor.profile == authority.profile, facts.intents[packageID] == identity.observed else {
            throw SharedMediaStorageFailure.stale
        }
        if let saved = identity.savedSuccessor {
            let c = fresh(), inventory = try target(c, packageID).inventory
            guard let witness = try SharedMediaNativeReceivingPhaseGraph.pending(c, inventory: inventory)[packageID],
                  witness.row == identity.observed, case .prepared(let prepared) = witness.slot,
                  try prepared.encoded() == saved.encoded() else { throw SharedMediaStorageFailure.stale }
            try prepared.requireSelection(draftGeneration: draftGeneration, pairIDs: pairIDs)
            try validate(); consumed = true; return prepared
        }
        guard case .abandoned(let predecessor) = try SharedMediaNativeReceivingSlot.decode(identity.observed, profile: authority.profile),
              predecessor == identity.predecessor else { throw SharedMediaStorageFailure.stale }
        let ids = identity.identity
        let (request, proofs) = try await prepareRequest(packageID: packageID, pairIDs: pairIDs,
            operationID: ids.operationID, queueID: ids.queueID, observationID: ids.observationID, bindingID: ids.bindingID,
            generation: ids.generation, eventID: ids.eventID, timestamp: ids.timestamp,
            intentRevision: SharedMediaStoragePolicy.add(predecessor.revision, 1),
            restagedFromSHA256: SharedMediaAcquisitionEncoding.digest(predecessor.encoded()))
        let prepared = try SharedMediaNativeReceivingIntent.Prepared(request)
        try prepared.requireSelection(draftGeneration: draftGeneration, pairIDs: pairIDs)
        let c = fresh(), cRows = try target(c, packageID), inventory = cRows.inventory, package = cRows.package, member = cRows.member
        try requirePrestate(request, context: c, package: package, member: member)
        guard let slot = try SharedMediaNativeReceivingPhaseGraph.row(packageID, in: c),
              SharedMediaNativeReceivingIntentGraph.Row(slot) == identity.observed else { throw SharedMediaStorageFailure.stale }
        let states = try SharedMediaNativeReceivingIntentGraph.currentCohort(prepared, context: c, inventory: inventory)
        let frozen = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes)
        let originals = try SharedMediaNativeAppReceivingIO.originalFacts(frozen, context: c, inventoryID: authority.profile.inventoryID)
        let before = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inventory,
            ownerID: authority.profile.ownerID, format: .appV2)
        guard let base = before.baseMetadataByPackage[packageID] else { throw SharedMediaStorageFailure.conflict }
        let reservation = try SharedMediaNativeReceivingReservation.maximum(prepared, currentMetadata: base, pairStates: states)
        let bytes = try prepared.encoded()
        slot.phaseRaw = "prepared"; slot.schemaVersion = 2; slot.revision = try SharedMediaStoragePolicy.add(predecessor.revision, 1)
        slot.operationID = prepared.operationID; slot.draftGeneration = draftGeneration
        slot.preparedData = bytes; slot.preparedSHA256 = SharedMediaAcquisitionEncoding.digest(bytes)
        slot.resultData = nil; slot.resultSHA256 = nil
        inventory.revision = try SharedMediaStoragePolicy.add(expected.inventory.revision, 1)
        let proof = SharedMediaNativeAppIntentPoststate(transition: .restage(prepared), facts: facts, header: expected,
            row: slot, inventory: inventory, package: package)
        let after = try SharedMediaNativeAcquisitionBudget.evaluateIntentPoststate(context: c, inventory: inventory, proof: proof)
        guard after.metadataByPackage[packageID] == reservation.charged else { throw SharedMediaStorageFailure.conflict }
        let added = max(0, Int64(bytes.count) - Int64(try predecessor.encoded().count))
        try after.totals.checkAvailable(availableBytes(), additionalReservation: added)
        try boundary(.beforeSave); try validate(); try proof.validate(context: c, inventory: inventory)
        let current = fresh(), currentRows = try target(current, packageID), oldInventory = currentRows.inventory, oldPackage = currentRows.package, oldMember = currentRows.member
        try requirePrestate(request, context: current, package: oldPackage, member: oldMember)
        try requireFreshReceivingIdentity(prepared, context: current)
        guard try SharedMediaNativeFreezeFacts.request(context: current, inventory: oldInventory, package: oldPackage, member: oldMember,
            binding: binding, operationID: prepared.operationID, pairIDs: pairIDs, proofs: proofs) == request.freeze,
              try SharedMediaNativeAppReceivingIO.originalFacts(frozen, context: current, inventoryID: authority.profile.inventoryID) == originals else { throw SharedMediaStorageFailure.stale }
        try after.totals.checkAvailable(availableBytes(), additionalReservation: added)
        for observation in proofs { try verify(observation) }
        return try afterIntentSave(c, proof: proof) {
            let fresh = self.fresh(), inventory = try self.target(fresh, packageID).inventory
            guard let witness = try SharedMediaNativeReceivingPhaseGraph.pending(fresh, inventory: inventory)[packageID],
                  witness.row.preparedData == bytes, case .prepared(let saved) = witness.slot else {
                throw SharedMediaStorageFailure.conflict
            }
            return saved
        }
    }
}
