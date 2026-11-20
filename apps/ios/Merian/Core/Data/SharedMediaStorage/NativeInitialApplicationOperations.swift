import Foundation
import SwiftData

/// Original-result application within the existing receiving/account operation.
/// No provider executor, new admission, path export or History selection owner.
@MainActor
final class NativeInitialApplicationOperations {
    private typealias Snapshot = SharedMediaNativePhotoAllocationSnapshot
    private typealias Poststate = NativePhotoAllocationPoststate
    private let container: ModelContainer
    private let authority: SharedMediaNativeAppOperationAuthority
    private let io: SharedMediaNativeOriginalIO
    private let seal: (SharedMediaPhotoRetirementInspection, SharedMediaNativePairCompletion?) throws -> Void
    private let expected: SharedMediaNativeAppEligibility.Header
    private let availableBytes: () throws -> Int64
    private let boundary: (SharedMediaNativeMetadataBoundary) throws -> Void
    private var attempted = false

    init(container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority, io: SharedMediaNativeOriginalIO,
         seal: @escaping (SharedMediaPhotoRetirementInspection, SharedMediaNativePairCompletion?) throws -> Void,
         expected: SharedMediaNativeAppEligibility.Header, availableBytes: @escaping () throws -> Int64,
         boundary: @escaping (SharedMediaNativeMetadataBoundary) throws -> Void) {
        self.container = container; self.authority = authority; self.io = io; self.seal = seal
        self.expected = expected; self.availableBytes = availableBytes; self.boundary = boundary
    }

    func apply(_ prepared: SharedMediaNativeReceivingIntent.Prepared,
               readOriginal: @MainActor (InitialCompletionDocuments.CpmAdmission, @escaping @MainActor @Sendable () throws -> Void) async throws -> InitialCompletionDocuments.CpmAcquisition?) async throws -> SharedMediaNativeConsumerCohort.AppliedInitial? {
        guard !attempted, prepared.profile == authority.profile else { throw SharedMediaStorageFailure.closed }
        attempted = true; try validate()
        if let applied = try applied(prepared) { try validate(); return applied }
        let context = fresh(), inventory = try inventory(context)
        let before = try Snapshot.initialCandidate(prepared, context: context, inventory: inventory)
        guard let pin = before.initialPin, let completed = pin.completion else { throw SharedMediaStorageFailure.closed }
        try Poststate.ApplicationCapacity.preliminary(before: before, context: context,
            inventory: inventory, availableBytes: availableBytes)
        let check: @MainActor @Sendable () throws -> Void = {
            try self.validate(); try before.requireCurrent(context: self.fresh())
        }
        let states = try states(before, context: context, inventory: inventory)
        let proofs = try await SharedMediaNativeAppReceivingIO.inspect(states, io: io, check: check) { try self.seal($0, nil) }
        try check()
        guard let acquisition = try await readOriginal(pin.admission, check) else { try check(); return nil }
        try check()
        guard acquisition.record == completed else { throw SharedMediaStorageFailure.conflict }
        let scalars = try Self.scalars(acquisition, prepared: prepared)
        // Injected callbacks stay outside the nonrecursive deletion/review lock.
        // The context and model are constructed only after this final boundary.
        try boundary(.beforeSave); try check()
        let cohort = try ConfirmedSpeciesReviewPersistence.transaction {
            try check(); for proof in proofs { try seal(proof, nil) }
            let current = fresh(), inventory = try self.inventory(current)
            guard let row = try SharedMediaNativeReceivingPhaseGraph.row(before.row.id, in: current) else {
                throw SharedMediaStorageFailure.stale
            }
            let snapshot = try Snapshot.readInitial(.init(row), inventory: inventory, context: current)
            guard snapshot.row == before.row, snapshot.header == before.header else { throw SharedMediaStorageFailure.stale }
            let poststate = try Poststate.Application(before: snapshot, row: row, inventory: inventory,
                scalars: scalars, acquisition: acquisition, context: current, availableBytes: availableBytes)
            do {
                try poststate.stage(current); try poststate.validate(current)
                try check(); for proof in proofs { try seal(proof, nil) }
                do { try current.save() } catch { current.rollback() }
                // A thrown save is acknowledged only by its complete exact
                // successor. A predecessor/partial state stays held; no retry.
                try poststate.requireSaved(fresh())
                return poststate.cohort
            } catch { current.rollback(); throw error }
        }
        // Lost acknowledgement may recover the same retained state. No model,
        // mutable display or provider attempt is reconstructed on this path.
        do { try boundary(.afterSave) } catch { /* Require retained readback below. */ }
        try boundary(.beforeReadback)
        let successor = try SharedMediaNativeAppMetadataFacts.successor(expected)
        guard try authority.header(container) == successor,
              try applied(prepared) == cohort, try authority.header(container) == successor else { throw SharedMediaStorageFailure.stale }
        return cohort
    }

    func acknowledgeHistory(_ prepared: SharedMediaNativeReceivingIntent.Prepared,
                            readOriginal: @MainActor (InitialCompletionDocuments.CpmAdmission, @escaping @MainActor @Sendable () throws -> Void) async throws -> InitialCompletionDocuments.CpmAcquisition?) async throws -> SharedMediaNativeConsumerCohort.AppliedInitial? {
        guard !attempted, prepared.profile == authority.profile else { throw SharedMediaStorageFailure.closed }
        attempted = true; try validate()
        guard let before = try retained(prepared) else { throw SharedMediaStorageFailure.closed }
        if before.cohort.format == .history { try validate(); return before.cohort }
        guard let baseline = try NativeInitialHistoryBaseline.read(prepared, context: fresh()) else { try validate(); return nil }
        let association = baseline.association
        let after = try SharedMediaNativeConsumerCohort.AppliedInitial(acknowledging: before.cohort, association: association)
        try historyCapacity(before, after: after, context: fresh())
        let check: @MainActor @Sendable () throws -> Void = {
            try self.validate(); try before.requireCurrent(context: self.fresh())
            guard try NativeInitialHistoryBaseline.read(prepared, context: self.fresh())?.association == association else {
                throw SharedMediaStorageFailure.stale
            }
        }
        try check()
        guard let acquisition = try await readOriginal(before.admission, check) else { try check(); return nil }
        try check()
        guard acquisition.record == before.completion else { throw SharedMediaStorageFailure.conflict }
        try Self.compareOriginal(acquisition, before: before, baseline: baseline)
        try boundary(.beforeSave); try check()
        try ConfirmedSpeciesReviewPersistence.transaction {
            try check()
            let context = fresh(), inventory = try self.inventory(context)
            try historyCapacity(before, after: after, context: context)
            let consumer = try SharedMediaNativeReceivingRows.appliedConsumer(prepared, in: context)
            let packageID = prepared.package.id
            let package = try SharedMediaNativePairPlanGraph.one(context,
                FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
            guard let row = try SharedMediaNativeReceivingPhaseGraph.row(packageID, in: context) else { throw SharedMediaStorageFailure.stale }
            let packageBefore = SharedMediaNativeAppMetadataFacts.Package(package)
            let inventoryBefore = SharedMediaNativeReleaseStagePoststate.Inventory(inventory)
            let image = try Poststate.consumerImage(consumer, cohort: after)
            let updated: Set<PersistentIdentifier> = [consumer.persistentModelID, inventory.persistentModelID]
            guard updated.count == 2 else { throw SharedMediaStorageFailure.conflict }
            do {
                consumer.contractVersion = after.format.rawValue; consumer.cohortData = try after.encoded()
                consumer.cohortSHA256 = try after.digest(); consumer.revision = after.consumerRevision
                inventory.revision = try SharedMediaStoragePolicy.add(inventory.revision, 1)
                guard context.insertedModelsArray.isEmpty, context.deletedModelsArray.isEmpty,
                      Set(context.changedModelsArray.map(\.persistentModelID)) == updated,
                      SharedMediaNativeAppMetadataFacts.Consumer(consumer) == image,
                      SharedMediaNativeAppMetadataFacts.Package(package) == packageBefore,
                      SharedMediaNativeReceivingIntentGraph.Row(row) == before.row else { throw SharedMediaStorageFailure.conflict }
                try inventoryBefore.requireSuccessor(inventory)
                try check()
                do { try context.save() } catch { context.rollback() }
                let saved = fresh(), savedInventory = try self.inventory(saved)
                try inventoryBefore.requireSuccessor(savedInventory)
                guard let successor = try retained(prepared), successor.row == before.row, successor.cohort == after else {
                    throw SharedMediaStorageFailure.stale
                }
            } catch { context.rollback(); throw error }
        }
        do { try boundary(.afterSave) } catch { /* Exact retained successor required below. */ }
        try boundary(.beforeReadback)
        let successor = try SharedMediaNativeAppMetadataFacts.successor(expected)
        guard try authority.header(container) == successor, try applied(prepared) == after,
              try authority.header(container) == successor else { throw SharedMediaStorageFailure.stale }
        return after
    }

    private func historyCapacity(_ before: Snapshot.Applied, after: SharedMediaNativeConsumerCohort.AppliedInitial,
                                 context: ModelContext) throws {
        try Task.checkCancellation(); try before.requireCurrent(context: context)
        guard before.cohort.historyHandoffRemainingAdvances == 1, after.historyHandoffRemainingAdvances == 0,
              try NativeInitialHistoryBaseline.read(before.prepared, context: context)?.association == after.historyBaseline else {
            throw SharedMediaStorageFailure.conflict
        }
        let inventory = try inventory(context)
        let budget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: context, inventory: inventory,
            ownerID: before.prepared.profile.ownerID, format: .appV2)
        // Retained occupancy already reduces filesystem free space. It is not
        // a pending package; preserve pending peers/reserve and add only growth.
        let growth = max(0, Int64(try after.encoded().count) - Int64(try before.cohort.encoded().count))
        try budget.totals.checkAvailable(availableBytes(), additionalReservation: growth)
        let witnesses = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory)
        let historical = try SharedMediaNativeTerminalScan.read(container: container, inventoryID: inventory.id)
        // The existing pending handoff advance pays for this save exactly once.
        // Inventory +1 and historical obligation -1 preserve every peer's runway.
        try SharedMediaNativeReceivingCleanGraph.requireAggregateRunway(inventoryRevision: inventory.revision,
            witnesses: Array(witnesses.values), historical: historical)
        try Task.checkCancellation(); try before.requireCurrent(context: context)
    }

    private static func compareOriginal(_ acquisition: InitialCompletionDocuments.CpmAcquisition,
                                        before: Snapshot.Applied, baseline: NativeInitialHistoryBaseline.Value) throws {
        let scalars = try scalars(acquisition, prepared: before.prepared)
        let record = try LocalScanRecordFactory.makeInitialRecord(from: acquisition.result, speciesID: scalars.speciesID,
            timestamp: scalars.timestamp, captureDate: scalars.captureDate, capturedMediaJSON: nil, coverImagePath: nil, fieldNotes: scalars.fieldNotes)
        record.mediaAuthorityRaw = "sharedDirectNativeInitialV1"; record.sharedMediaConsumerID = before.prepared.bindingID
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        record.observationContextsJSON = try scalars.contexts.map {
            guard let text = String(data: try encoder.encode($0), encoding: .utf8) else { throw SharedMediaStorageFailure.invalid }
            return text
        }
        try before.cohort.receipt.requireBaseline(LocalScanRecordFactory.initialApplicationBaseline(record: record, result: acquisition.result))
        guard try SavedIdentificationDisplayBaseline.capture(
            AnalysisDisplaySnapshot(analysisID: baseline.association.baselineAnalysisID, record: record), matching: baseline.result) != nil else {
            throw SharedMediaStorageFailure.conflict
        }
    }

    private func applied(_ prepared: SharedMediaNativeReceivingIntent.Prepared) throws -> SharedMediaNativeConsumerCohort.AppliedInitial? {
        try retained(prepared)?.cohort
    }

    private func retained(_ prepared: SharedMediaNativeReceivingIntent.Prepared) throws -> Snapshot.Applied? {
        let context = fresh(), inventory = try inventory(context)
        guard let consumer = try SharedMediaConsumerLookup.one(context, packageID: prepared.package.id),
              SharedMediaNativeConsumerCohort.AppliedInitialFormat(rawValue: consumer.contractVersion) != nil else { return nil }
        guard let row = try SharedMediaNativeReceivingPhaseGraph.row(prepared.package.id, in: context) else { throw SharedMediaStorageFailure.closed }
        let value = try Snapshot.Applied.read(row, inventory: inventory, context: context)
        guard try value.prepared.encoded() == prepared.encoded() else { throw SharedMediaStorageFailure.stale }
        return value
    }

    private func states(_ before: Snapshot, context: ModelContext,
                        inventory: SharedMediaInventoryRecord) throws -> [SharedMediaNativePairFileState] {
        let id = before.prepared.package.id
        let package = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id }))
        let member = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
        let frozen = try SharedMediaNativeFrozenCohort.decode(before.prepared.cohort.bytes)
        return try frozen.entries.map {
            let intent = try SharedMediaNativeDerivativeIntent.decode($0.intent.bytes)
            let state = try SharedMediaNativePairFileGraph.state(context: context, inventory: inventory,
                package: package, member: member, pairID: intent.pairID)
            guard state.phase == "ready", try state.intent() == intent else { throw SharedMediaStorageFailure.stale }
            return state
        }
    }

    private static func scalars(_ acquisition: InitialCompletionDocuments.CpmAcquisition,
                                prepared: SharedMediaNativeReceivingIntent.Prepared) throws -> Poststate.ApplicationScalars {
        guard let projection = try InitialAnalysisCanonical.parse(acquisition.record.projection).object,
              let text = projection["scan_timestamp"]?.string, let association = projection["species_association"] else {
            throw SharedMediaStorageFailure.conflict
        }
        let speciesID: String
        if association.isNull { speciesID = "" } else {
            guard let id = association.object?["species_id"]?.string else { throw SharedMediaStorageFailure.conflict }
            speciesID = id
        }
        let timestamp = try Date.ISO8601FormatStyle(includingFractionalSeconds: text.contains(".")).parse(text)
        let frozen = try SharedMediaNativeFrozenCohort.decode(prepared.cohort.bytes)
        let supporting: SharedMediaNativeFrozenSupporting = try SharedMediaAcquisitionEncoding.decode(frozen.supportingBytes,
            maximum: Int(PhotoPreparationPolicy.metadata))
        guard let first = frozen.entries.first else { throw SharedMediaStorageFailure.closed }
        let original = try SharedMediaNativeDerivativeIntent.decode(first.intent.bytes).preparation.original.reference.referenceID
        let presentation = supporting.presentation.first { $0.referenceID == original }
        let captured = presentation?.captureDate ?? Date(timeIntervalSinceReferenceDate: Double(bitPattern: prepared.timestampBits))
        return .init(speciesID: speciesID, timestamp: timestamp, captureDate: captured, fieldNotes: nil, contexts: supporting.contexts)
    }

    private func validate() throws {
        guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
    }
    private func fresh() -> ModelContext {
        let context = ModelContext(container); context.autosaveEnabled = false; return context
    }
    private func inventory(_ context: ModelContext) throws -> SharedMediaInventoryRecord {
        let id = authority.profile.inventoryID
        return try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
    }
}
