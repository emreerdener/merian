import Foundation
import SwiftData

/// Exact sidecar/inventory write set. Receiving revision and every immutable
/// submission byte remain unchanged. Construct only on an audited clean view.
@MainActor
struct NativePhotoAllocationPoststate {
    private typealias Facts = SharedMediaNativeAppMetadataFacts
    private let before: SharedMediaNativeReceivingIntentGraph.Row
    private let inventory: SharedMediaNativeReleaseStagePoststate.Inventory
    private let rowID: PersistentIdentifier, inventoryID: PersistentIdentifier
    private let bytes: Data, digest: String
    private let transaction: SharedMediaNativeReceivingIntent.Transaction
    private let recoveryPresentationData: Data?

    init(row: SharedMediaReceivingIntentRecord, inventory: SharedMediaInventoryRecord,
         after: SharedMediaNativePhotoAllocation, prepared: SharedMediaNativeReceivingIntent.Prepared, context: ModelContext) throws {
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        before = .init(row); try before.requireNoReleaseStart()
        guard before.phase == "received", before.version == 2,
              after.claim.profile == (try SharedMediaNativeAppEligibility.profile(inventory)),
              after.claim.packageID == before.id,
              after.claim.preparedSHA256 == before.preparedSHA256,
              after.claim.receivedSHA256 == before.resultSHA256 else { throw SharedMediaStorageFailure.conflict }
        guard before.preparedData == (try prepared.encoded()), let result = before.resultData else {
            throw SharedMediaStorageFailure.conflict
        }
        let received = try SharedMediaNativeReceivingIntent.Received.decode(result, prepared: prepared)
        try after.claim.requireMatch(prepared: prepared, received: received)
        transaction = try received.reconstruct(prepared)
        recoveryPresentationData = try SharedMediaNativeReceivingRows.recoveryPresentationBytes(request: transaction, in: context)
        _ = try SharedMediaNativeReceivingRows.recoveryPresentation(recoveryPresentationData, prepared: prepared)
        if let old = before.allocationData, let sha = before.allocationSHA256 {
            let predecessor = try SharedMediaNativePhotoAllocation.decode(old, sha256: sha)
            try predecessor.requireSuccessor(after)
        } else {
            try before.requireNoAllocation()
            guard after.receipt == nil, after.roleMapping == nil, after.transferReservation == nil else { throw SharedMediaStorageFailure.closed }
        }
        self.inventory = .init(inventory); rowID = row.persistentModelID; inventoryID = inventory.persistentModelID
        bytes = try after.encoded(); digest = SharedMediaAcquisitionEncoding.digest(bytes)
    }

    func validate(_ context: ModelContext, row: SharedMediaReceivingIntentRecord, inventory: SharedMediaInventoryRecord) throws {
        guard context.insertedModelsArray.isEmpty, context.deletedModelsArray.isEmpty,
              Set(context.changedModelsArray.map(\.persistentModelID)) == [rowID, inventoryID],
              row.persistentModelID == rowID, inventory.persistentModelID == inventoryID else {
            throw SharedMediaStorageFailure.conflict
        }
        try self.inventory.requireSuccessor(inventory)
        try SharedMediaNativeReceivingRows.requireRecoveryPresentation(recoveryPresentationData, request: transaction, in: context)
        let after = SharedMediaNativeReceivingIntentGraph.Row(row)
        try after.requireNoReleaseStart()
        guard after.id == before.id, after.inventoryID == before.inventoryID,
              after.inventoryGeneration == before.inventoryGeneration, after.ownerID == before.ownerID,
              after.draftGeneration == before.draftGeneration, after.operationID == before.operationID,
              after.cursor == before.cursor, after.phase == before.phase, after.version == before.version,
              after.revision == before.revision, after.preparedData == before.preparedData,
              after.preparedSHA256 == before.preparedSHA256, after.resultData == before.resultData,
              after.resultSHA256 == before.resultSHA256, after.releaseStartData == before.releaseStartData,
              after.releaseStartSHA256 == before.releaseStartSHA256,
              after.allocationData == bytes, after.allocationSHA256 == digest else { throw SharedMediaStorageFailure.conflict }
    }

    func requirePredecessor(row: SharedMediaReceivingIntentRecord, inventory: SharedMediaInventoryRecord, context: ModelContext) throws {
        guard !context.hasChanges, SharedMediaNativeReceivingIntentGraph.Row(row) == before,
              SharedMediaNativeReleaseStagePoststate.Inventory(inventory) == self.inventory else {
            throw SharedMediaStorageFailure.stale
        }
        try SharedMediaNativeReceivingRows.requireRecoveryPresentation(recoveryPresentationData, request: transaction, in: context)
    }
    /// Initial-pin seal. This validates a complete raw after-image and never
    /// saves; the retained allocation operation remains the sole writer.
    @MainActor
    struct InitialPin {
        let before: SharedMediaNativePhotoAllocationSnapshot
        let admission: InitialCompletionDocuments.CpmAdmission
        let completion: InitialCompletionDocuments.CpmRecoveryRecord?
        let after: SharedMediaNativeReceivingIntentGraph.Row
        private let inventory: SharedMediaNativeReleaseStagePoststate.Inventory
        private let rowID: PersistentIdentifier, inventoryID: PersistentIdentifier

        init(before: SharedMediaNativePhotoAllocationSnapshot, acknowledgement: Data,
             row: SharedMediaReceivingIntentRecord, inventory: SharedMediaInventoryRecord, context: ModelContext) throws {
            try before.requireCurrent(context: context)
            try before.row.requireNoReleaseStart()
            try before.requireSettledPresentation()
            guard before.row == .init(row) else { throw SharedMediaStorageFailure.closed }
            admission = try .init(acknowledgement: acknowledgement, original: .saved(before.allocation))
            completion = nil
            self.before = before; after = .init(admitting: admission, from: before.row)
            self.inventory = .init(inventory); rowID = row.persistentModelID; inventoryID = inventory.persistentModelID
        }

        init(before: SharedMediaNativePhotoAllocationSnapshot, acquisition: InitialCompletionDocuments.CpmAcquisition,
             row: SharedMediaReceivingIntentRecord, inventory: SharedMediaInventoryRecord, context: ModelContext) throws {
            try before.requireCurrent(context: context)
            try before.requireSettledPresentation()
            guard let pin = before.initialPin, pin.completion == nil,
                  before.row == .init(row) else { throw SharedMediaStorageFailure.closed }
            admission = pin.admission
            let record = try InitialCompletionDocuments.CpmRecoveryRecord.decode(acquisition.record.bytes, admission: admission)
            completion = record; self.before = before; after = .init(completing: record, from: before.row)
            self.inventory = .init(inventory); rowID = row.persistentModelID; inventoryID = inventory.persistentModelID
        }

        func validate(_ context: ModelContext, row: SharedMediaReceivingIntentRecord, inventory: SharedMediaInventoryRecord) throws {
            guard context.insertedModelsArray.isEmpty, context.deletedModelsArray.isEmpty,
                  Set(context.changedModelsArray.map(\.persistentModelID)) == [rowID, inventoryID],
                  row.persistentModelID == rowID, inventory.persistentModelID == inventoryID,
                  SharedMediaNativeReceivingIntentGraph.Row(row) == after else { throw SharedMediaStorageFailure.conflict }
            try self.inventory.requireSuccessor(inventory)
            try SharedMediaNativeReceivingRows.requireRecoveryPresentation(before.recoveryPresentationData,
                request: before.transaction, in: context)
        }

        func requirePredecessor(_ context: ModelContext, inventory: SharedMediaInventoryRecord) throws {
            try before.requireCurrent(context: context)
            guard SharedMediaNativeReleaseStagePoststate.Inventory(inventory) == self.inventory else { throw SharedMediaStorageFailure.stale }
        }

        func requireSuccessor(_ context: ModelContext, inventory: SharedMediaInventoryRecord) throws {
            guard let row = try SharedMediaNativeReceivingPhaseGraph.row(after.id, in: context),
                  SharedMediaNativeReceivingIntentGraph.Row(row) == after else { throw SharedMediaStorageFailure.stale }
            try self.inventory.requireSuccessor(inventory)
            let current = try SharedMediaNativePhotoAllocationSnapshot.readInitial(after, inventory: inventory, context: context)
            guard current.initialPin?.admission == admission, current.initialPin?.completion == completion, current.recoveryPresentationData == before.recoveryPresentationData else {
                throw SharedMediaStorageFailure.stale
            }
            _ = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: context, inventory: inventory,
                ownerID: before.prepared.profile.ownerID, format: .appV2)
        }

        func requireReservation(_ context: ModelContext, inventory: SharedMediaInventoryRecord,
                                availableBytes: () throws -> Int64) throws {
            try requirePredecessor(context, inventory: inventory)
            let charge: Int64 = try completion == nil ? PhotoPreparationPolicy.add([Int64(admission.acknowledgement.count), 64,
                Int64(InitialCompletionDocuments.CpmRecoveryRecord.maximumBytes), 64]) : 0
            let id = before.row.id
            let budget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: context, inventory: inventory,
                ownerID: before.prepared.profile.ownerID, format: .appV2)
            guard let old = budget.metadataByPackage[id],
                  try PhotoPreparationPolicy.add([old, charge]) <= PhotoPreparationPolicy.metadata else { throw SharedMediaStorageFailure.capacity }
            let package = try SharedMediaNativePairPlanGraph.one(context,
                FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id }))
            guard try PhotoPreparationPolicy.add([package.allocatedByteCount, old, charge]) <= PhotoPreparationPolicy.package else {
                throw SharedMediaStorageFailure.capacity
            }
            var totals = budget.totals
            try totals.includePhotoPhysical(materialized: 0, reserved: charge)
            try totals.checkAvailable(availableBytes())
            let witnesses = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory)
            let terminal = try SharedMediaNativeTerminalScan.read(container: context.container, inventoryID: inventory.id)
            try SharedMediaNativeReceivingCleanGraph.requireReplacementRunway(inventoryRevision: inventory.revision,
                packageID: id, executionAdvances: SharedMediaStoragePolicy.add(before.allocation.remainingAdvances, completion == nil ? 1 : 0),
                saveAdvances: 1, witnesses: witnesses, historical: terminal)
        }
    }

    /// Value inputs only. The eventual live owner must derive these from
    /// the exact saved completion and frozen capture facts, never live UI.
    struct ApplicationScalars {
        let speciesID: String
        let timestamp: Date, captureDate: Date
        let fieldNotes: String?
        let contexts: [ObservationContext]
    }

    /// Exact queue-to-scan after-image. Construction proves bounded scalar
    /// absence on a clean predecessor. Validation never faults relationships or
    /// saves; the future owning operation still supplies its live fences.
    @MainActor
    struct Application {
        let cohort: SharedMediaNativeConsumerCohort.AppliedInitial
        private let before: SharedMediaNativePhotoAllocationSnapshot
        private let contextID: ObjectIdentifier
        private let row: SharedMediaReceivingIntentRecord, inventory: SharedMediaInventoryRecord
        private let package: PhotoPreparationRecord, consumer: SharedMediaConsumerRecord
        private let member: SharedMediaPendingMembershipRecord
        private let rows: SharedMediaNativeReceivingRows.Set
        private let record: LocalScanRecord
        private let inventoryBefore: SharedMediaNativeReleaseStagePoststate.Inventory
        private let packageBefore: Facts.Package, consumerAfter: Facts.Consumer
        private let updated: Set<PersistentIdentifier>, deleted: Set<PersistentIdentifier>
        private let baseline: Data, result: InitialRetainedResult

        init(before: SharedMediaNativePhotoAllocationSnapshot, row: SharedMediaReceivingIntentRecord,
             inventory: SharedMediaInventoryRecord, scalars: ApplicationScalars,
             acquisition: InitialCompletionDocuments.CpmAcquisition, context: ModelContext,
             availableBytes: () throws -> Int64) throws {
            guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
            try before.requireCurrent(context: context)
            // Existing bounded lower/upper aliases also reject prior LocalScan
            // and LocalAnalysis ownership. A missing scan has no reachable media
            // or collection links; unrelated child/collection rows are allowed.
            let rows = try SharedMediaNativeReceivingPhaseGraph.receivedRows(before.transaction, context: context)
            try Self.requireNoDeletion(before.prepared, context: context)
            guard rows.consumer.revision == 0 else { throw SharedMediaStorageFailure.conflict }
            let id = before.row.id
            let package = try SharedMediaNativePairPlanGraph.one(context,
                FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id }))
            let member = try SharedMediaNativePairPlanGraph.one(context,
                FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
            // Never accept a caller model: a detached model could already have
            // unidirectional links to orphan media without changing child rows.
            let record = try LocalScanRecordFactory.makeInitialRecord(from: acquisition.result, speciesID: scalars.speciesID,
                timestamp: scalars.timestamp, captureDate: scalars.captureDate,
                capturedMediaJSON: nil, coverImagePath: nil, fieldNotes: scalars.fieldNotes)
            record.mediaAuthorityRaw = "sharedDirectNativeInitialV1"; record.sharedMediaConsumerID = before.prepared.bindingID
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            record.observationContextsJSON = try scalars.contexts.map {
                guard let text = String(data: try encoder.encode($0), encoding: .utf8) else { throw SharedMediaStorageFailure.invalid }
                return text
            }
            cohort = try ApplicationCapacity.measured(before: before, row: row, acquisition: acquisition,
                record: record, context: context, inventory: inventory, availableBytes: availableBytes)
            baseline = try LocalScanRecordFactory.initialApplicationBaseline(record: record, result: acquisition.result)
            result = acquisition.result; self.before = before; contextID = ObjectIdentifier(context)
            self.row = row; self.inventory = inventory; self.package = package; consumer = rows.consumer
            self.record = record; self.member = member; self.rows = rows
            inventoryBefore = .init(inventory); packageBefore = .init(package)
            consumerAfter = try NativePhotoAllocationPoststate.consumerImage(rows.consumer, cohort: cohort)
            updated = [inventory.persistentModelID, package.persistentModelID, rows.consumer.persistentModelID]
            deleted = [member.persistentModelID, rows.queue.persistentModelID, rows.job.persistentModelID, rows.event.persistentModelID]
            guard updated.count == 3, deleted.count == 4, updated.isDisjoint(with: deleted) else {
                throw SharedMediaStorageFailure.conflict
            }
        }

        /// No save or callback. A live caller must keep its context private and
        /// perform this and save synchronously under the same final fences.
        /// The scan model never escapes this owner before durable readback.
        func stage(_ context: ModelContext) throws {
            guard ObjectIdentifier(context) == contextID, !context.hasChanges, record.modelContext == nil else {
                throw SharedMediaStorageFailure.conflict
            }
            try before.requireCurrent(context: context)
            _ = try SharedMediaNativeReceivingPhaseGraph.receivedRows(before.transaction, context: context)
            try Self.requireNoDeletion(before.prepared, context: context)
            try cohort.receipt.requirePresentation(rows.queue.recoveryPresentationData)
            consumer.cohortData = try cohort.encoded(); consumer.cohortSHA256 = try cohort.digest()
            consumer.contractVersion = cohort.format.rawValue; consumer.kindRaw = "localScan"
            consumer.consumerID = before.prepared.observationID.uuidString.lowercased(); consumer.revision = 1
            package.accountingTierRaw = "retained"; package.revision = try SharedMediaStoragePolicy.add(packageBefore.revision, 1)
            inventory.revision = try SharedMediaStoragePolicy.add(inventoryBefore.revision, 1)
            context.delete(member); context.delete(rows.queue); context.delete(rows.job); context.delete(rows.event)
            context.insert(record)
            try validate(context)
        }

        func validate(_ context: ModelContext) throws {
            let inserted: Set<PersistentIdentifier> = [record.persistentModelID]
            guard ObjectIdentifier(context) == contextID, record.modelContext === context,
                  context.insertedModelsArray.count == 1,
                  Set(context.insertedModelsArray.map(\.persistentModelID)) == inserted,
                  context.deletedModelsArray.count == deleted.count,
                  Set(context.deletedModelsArray.map(\.persistentModelID)) == deleted,
                  Set(context.changedModelsArray.map(\.persistentModelID)).subtracting(inserted.union(deleted)) == updated,
                  SharedMediaNativeReceivingIntentGraph.Row(row) == before.row,
                  Facts.Consumer(consumer) == consumerAfter,
                  try LocalScanRecordFactory.initialApplicationBaseline(record: record, result: result) == baseline else {
                throw SharedMediaStorageFailure.conflict
            }
            try inventoryBefore.requireSuccessor(inventory)
            let after = Facts.Package(package), old = packageBefore
            guard after.id == old.id, after.ownerID == old.ownerID, after.draftID == old.draftID,
                  after.generation == old.generation, after.contract == old.contract,
                  after.phase == old.phase, after.allocated == old.allocated, after.retiring == old.retiring,
                  after.envelope == old.envelope, after.tier == "retained",
                  after.revision == (try SharedMediaStoragePolicy.add(old.revision, 1)) else { throw SharedMediaStorageFailure.conflict }
            try Self.requireNoDeletion(before.prepared, context: context)
        }

        /// First-save readback only, while the caller still serializes scan
        /// mutation. Later replay uses Applied.read without restoring this image.
        func requireSaved(_ context: ModelContext) throws {
            guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
            let inventoryID = before.prepared.profile.inventoryID, id = before.row.id
            let inventory = try SharedMediaNativePairPlanGraph.one(context,
                FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
            guard let saved = try SharedMediaNativeReceivingPhaseGraph.row(id, in: context) else { throw SharedMediaStorageFailure.stale }
            let applied = try SharedMediaNativePhotoAllocationSnapshot.Applied.read(saved, inventory: inventory, context: context)
            guard applied.row == before.row, applied.cohort == cohort else { throw SharedMediaStorageFailure.stale }
            try inventoryBefore.requireSuccessor(inventory)
            let scanID = before.prepared.observationID.uuidString.lowercased()
            let scan = try SharedMediaNativePairPlanGraph.one(context,
                FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanID }))
            guard try LocalScanRecordFactory.initialApplicationBaseline(record: scan, result: result) == baseline else {
                throw SharedMediaStorageFailure.conflict
            }
        }

        private static func requireNoDeletion(_ prepared: SharedMediaNativeReceivingIntent.Prepared, context: ModelContext) throws {
            let ids = [prepared.queueID.uuidString.lowercased(), prepared.queueID.uuidString,
                       prepared.observationID.uuidString.lowercased(), prepared.observationID.uuidString]
            var query = FetchDescriptor<PendingCloudDeletionTask>(predicate: #Predicate { ids.contains($0.scanId) })
            query.fetchLimit = 1; query.includePendingChanges = true
            guard try context.fetch(query).isEmpty else { throw SharedMediaStorageFailure.conflict }
        }

    }

    /// A detached scalar image only; this model is never inserted. Reusing
    /// the complete consumer facts avoids an index-based partial field seal.
    @MainActor
    static func consumerImage(_ old: SharedMediaConsumerRecord,
                              cohort: SharedMediaNativeConsumerCohort.AppliedInitial) throws -> SharedMediaNativeAppMetadataFacts.Consumer {
        let value = SharedMediaConsumerRecord(id: old.id, kindRaw: "localScan", consumerID: old.observationID,
            originQueueID: old.originQueueID, observationID: old.observationID, inventoryID: old.inventoryID,
            inventoryGeneration: old.inventoryGeneration, ownerID: old.ownerID, packageID: old.packageID,
            draftGeneration: old.draftGeneration, frozenPackageRevision: old.frozenPackageRevision,
            contractVersion: cohort.format.rawValue, digestVersion: old.digestVersion, cohortSHA256: try cohort.digest(),
            executionKindRaw: old.executionKindRaw, inferenceGeneration: old.inferenceGeneration)
        value.cohortData = try cohort.encoded(); value.revision = cohort.consumerRevision
        value.retirementID = old.retirementID; value.lifecycleRaw = old.lifecycleRaw
        return .init(value)
    }

    /// Conservative two-stage application accounting. The old pending liability
    /// stays charged until a future exact atomic successor is saved. These checks
    /// grant no insertion, retirement, read or replay capability.
    @MainActor
    enum ApplicationCapacity {
        /// Reserve the remaining metadata allowance once before transient result
        /// reacquisition. Existing reserved headroom is already in `oldMetadata`.
        static func preliminary(before: SharedMediaNativePhotoAllocationSnapshot,
                                context: ModelContext, inventory: SharedMediaInventoryRecord,
                                availableBytes: () throws -> Int64) throws {
            try require(before: before, context: context, inventory: inventory,
                growth: nil, availableBytes: availableBytes)
        }

        /// Measure the complete scalar baseline and replacement cohort. Keeping
        /// removed quartet/member bytes and old reserves charged is conservative;
        /// neither physical bytes nor the original cohort are charged twice.
        static func measured(before: SharedMediaNativePhotoAllocationSnapshot,
                             row: SharedMediaReceivingIntentRecord, acquisition: InitialCompletionDocuments.CpmAcquisition,
                             record: LocalScanRecord, context: ModelContext, inventory: SharedMediaInventoryRecord,
                             availableBytes: () throws -> Int64) throws -> SharedMediaNativeConsumerCohort.AppliedInitial {
            guard record.mediaAuthorityRaw == "sharedDirectNativeInitialV1",
                  record.sharedMediaConsumerID == before.prepared.bindingID,
                  record.capturedMediaJSON == nil, record.coverImagePath == nil else { throw SharedMediaStorageFailure.closed }
            let baseline = try LocalScanRecordFactory.initialApplicationBaseline(record: record, result: acquisition.result)
            let receipt = try SharedMediaNativeConsumerCohort.InitialApplicationReceipt(snapshot: before,
                row: row, acquisition: acquisition, baseline: baseline)
            let cohort = try SharedMediaNativeConsumerCohort.AppliedInitial(original: before.transaction.cohort, receipt: receipt)
            let old = Int64(try before.transaction.cohort.encoded().count), new = Int64(try cohort.encoded().count)
            guard new >= old else { throw SharedMediaStorageFailure.conflict }
            try require(before: before, context: context, inventory: inventory,
                growth: PhotoPreparationPolicy.add([new - old, Int64(baseline.count)]), availableBytes: availableBytes)
            return cohort
        }

        /// Shared checked arithmetic also makes the conservative bound explicit
        /// without requiring a synthetic near-capacity database fixture.
        static func additionalMetadata(oldMetadata: Int64, measuredGrowth: Int64?) throws -> Int64 {
            guard oldMetadata >= 0, oldMetadata <= PhotoPreparationPolicy.metadata else { throw SharedMediaStorageFailure.capacity }
            let remaining = PhotoPreparationPolicy.metadata - oldMetadata
            guard let measuredGrowth else { return remaining }
            guard measuredGrowth >= 0, measuredGrowth <= remaining else { throw SharedMediaStorageFailure.capacity }
            return measuredGrowth
        }

        private static func require(before: SharedMediaNativePhotoAllocationSnapshot,
                                    context: ModelContext, inventory: SharedMediaInventoryRecord,
                                    growth: Int64?, availableBytes: () throws -> Int64) throws {
            try Task.checkCancellation(); try before.requireCurrent(context: context)
            try before.requireSettledPresentation()
            guard before.initialPin?.completion != nil else { throw SharedMediaStorageFailure.closed }
            let budget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: context, inventory: inventory,
                ownerID: before.prepared.profile.ownerID, format: .appV2)
            let id = before.row.id
            guard let old = budget.metadataByPackage[id] else { throw SharedMediaStorageFailure.stale }
            let extra = try additionalMetadata(oldMetadata: old, measuredGrowth: growth)
            try budget.totals.requirePhotoMetadataGrowth(packageID: id, bytes: extra, availableBytes: availableBytes())
            let witnesses = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory)
            let historical = try SharedMediaNativeTerminalScan.read(container: context.container, inventoryID: inventory.id)
            // Preserve predecessor execution obligations until actual transfer;
            // also reserve application plus the successor's one History ack.
            try SharedMediaNativeReceivingCleanGraph.requireReplacementRunway(inventoryRevision: inventory.revision,
                packageID: id, executionAdvances: max(before.allocation.remainingAdvances, 1),
                saveAdvances: 1, witnesses: witnesses, historical: historical)
            try Task.checkCancellation(); try before.requireCurrent(context: context)
        }
    }

}
