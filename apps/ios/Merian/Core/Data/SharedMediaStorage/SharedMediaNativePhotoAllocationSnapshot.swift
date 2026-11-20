import Foundation
import SwiftData

/// Clean, exact received graph with an immutable allocation liability. This is
/// descriptive evidence, never create, execution or release authority.
@MainActor
struct SharedMediaNativePhotoAllocationSnapshot {
    typealias Intent = SharedMediaNativeReceivingIntent
    typealias Row = SharedMediaNativeReceivingIntentGraph.Row
    let row: Row
    let prepared: Intent.Prepared
    let received: Intent.Received
    let transaction: Intent.Transaction
    let allocation: SharedMediaNativePhotoAllocation
    let header: SharedMediaNativeAppEligibility.Header
    let recoveryPresentationData: Data?
    let initialPin: InitialPin?

    /// Immutable typed storage evidence. Ordinary allocation mutation still
    /// requires a nil initial sidecar. No pin/application authority is minted.
    struct InitialPin: Equatable, Sendable {
        let admission: InitialCompletionDocuments.CpmAdmission
        let completion: InitialCompletionDocuments.CpmRecoveryRecord?
        var remainingAdvances: Int64 { completion == nil ? 1 : 0 }
        var currentBytes: Int64 {
            Int64(admission.acknowledgement.count + 64 + (completion.map { $0.bytes.count + 64 } ?? 0))
        }
        var chargedBytes: Int64 {
            get throws {
                try PhotoPreparationPolicy.add([Int64(admission.acknowledgement.count), 64,
                    Int64(InitialCompletionDocuments.CpmRecoveryRecord.maximumBytes), 64])
            }
        }
        fileprivate init(row: Row, allocation: SharedMediaNativePhotoAllocation) throws {
            guard row.releaseStartData == nil, row.releaseStartSHA256 == nil,
                  let bytes = row.initialAdmissionData, let sha = row.initialAdmissionSHA256,
                  bytes.count <= 8192, SharedMediaAcquisitionEncoding.isHash(sha),
                  SharedMediaAcquisitionEncoding.digest(bytes) == sha else { throw SharedMediaStorageFailure.closed }
            admission = try .init(acknowledgement: bytes, original: .saved(allocation))
            switch (row.initialCompletionData, row.initialCompletionSHA256) {
            case (nil, nil): completion = nil
            case (.some(let bytes), .some(let sha)):
                guard bytes.count <= (try InitialCompletionDocuments.CpmRecoveryRecord.maximumBytes),
                      SharedMediaAcquisitionEncoding.isHash(sha),
                      SharedMediaAcquisitionEncoding.digest(bytes) == sha else { throw SharedMediaStorageFailure.conflict }
                completion = try .decode(bytes, admission: admission)
            default: throw SharedMediaStorageFailure.closed
            }
        }
    }

    private init(row: Row, prepared: Intent.Prepared, received: Intent.Received,
                 allocation: SharedMediaNativePhotoAllocation,
                 header: SharedMediaNativeAppEligibility.Header, recoveryPresentationData: Data?, initialPin: InitialPin?) throws {
        self.row = row; self.prepared = prepared; self.received = received
        transaction = try received.reconstruct(prepared)
        self.allocation = allocation; self.header = header
        self.recoveryPresentationData = recoveryPresentationData; self.initialPin = initialPin
    }

    static func read(_ row: Row, inventory: SharedMediaInventoryRecord,
                     context: ModelContext, checkpoint: () throws -> Void = {}) throws -> Self {
        try read(row, inventory: inventory, context: context, allowsInitial: false, checkpoint: checkpoint)
    }

    static func readInitial(_ row: Row, inventory: SharedMediaInventoryRecord,
                            context: ModelContext, checkpoint: () throws -> Void = {}) throws -> Self {
        try read(row, inventory: inventory, context: context, allowsInitial: true, checkpoint: checkpoint)
    }

    private static func read(_ row: Row, inventory: SharedMediaInventoryRecord,
                             context: ModelContext, allowsInitial: Bool, checkpoint: () throws -> Void) throws -> Self {
        try checkpoint()
        if !allowsInitial { try row.requireNoReleaseStart() }
        guard !context.hasChanges else { throw SharedMediaStorageFailure.closed }
        let source = try original(row, inventory: inventory)
        let prepared = source.prepared, received = source.received, allocation = source.allocation
        let profile = prepared.profile
        let transaction = try received.reconstruct(prepared)
        let rows = try SharedMediaNativeReceivingPhaseGraph.receivedRows(transaction, context: context)
        _ = try SharedMediaNativeReceivingRows.recoveryPresentation(rows.queue.recoveryPresentationData, prepared: prepared)
        let value = try Self(row: row, prepared: prepared, received: received, allocation: allocation,
            header: currentHeader(profile, context: context), recoveryPresentationData: rows.queue.recoveryPresentationData,
            initialPin: allowsInitial ? InitialPin(row: row, allocation: allocation) : nil)
        _ = try SharedMediaNativeConsumerGraph.validateAllocatedReceived(rows.consumer, allocation: value,
            context: context, checkpoint: checkpoint)
        try value.requireCurrent(context: context)
        return value
    }

    /// Immutable source decoding shared by pending and retained readers. It
    /// intentionally proves no queue, consumer, package or scan ownership.
    private struct Original {
        let prepared: Intent.Prepared
        let received: Intent.Received
        let allocation: SharedMediaNativePhotoAllocation
    }
    private static func original(_ row: Row, inventory: SharedMediaInventoryRecord) throws -> Original {
        guard row.version == 2, row.phase == "received",
              let data = row.allocationData, let sha = row.allocationSHA256 else {
            throw SharedMediaStorageFailure.closed
        }
        let profile = try SharedMediaNativeAppEligibility.profile(inventory)
        guard row.cursor == row.id.uuidString.lowercased(), row.inventoryID == profile.inventoryID,
              row.inventoryGeneration == profile.generation, row.ownerID == profile.ownerID,
              let p = row.preparedData, let r = row.resultData,
              row.preparedSHA256 == SharedMediaAcquisitionEncoding.digest(p),
              row.resultSHA256 == SharedMediaAcquisitionEncoding.digest(r) else {
            throw SharedMediaStorageFailure.conflict
        }
        let prepared = try Intent.Prepared.decode(p)
        let received = try Intent.Received.decode(r, prepared: prepared)
        guard let allocation = try? SharedMediaNativePhotoAllocation.decode(data, sha256: sha) else {
            throw SharedMediaStorageFailure.closed
        }
        try allocation.claim.requireMatch(prepared: prepared, received: received)
        for receipt in allocation.completedRoles ?? [] {
            guard try receipt.transfer == SharedMediaNativePhotoTransferReservation(prepared: prepared, selection: receipt.transfer.selection) else {
                throw SharedMediaStorageFailure.conflict
            }
        }
        if let transfer = allocation.transferReservation {
            guard try transfer == SharedMediaNativePhotoTransferReservation(prepared: prepared, selection: transfer.selection) else {
                throw SharedMediaStorageFailure.conflict
            }
        }
        guard prepared.version == 2, prepared.profile == profile, prepared.package.id == row.id,
              prepared.package.generation == row.draftGeneration, prepared.operationID == row.operationID,
              row.revision == (try SharedMediaStoragePolicy.add(prepared.intentRevision ?? 0, 1)) else {
            throw SharedMediaStorageFailure.conflict
        }
        return Original(prepared: prepared, received: received, allocation: allocation)
    }

    /// Metadata-only admission for the enrollment owner's existing intent. It
    /// deliberately returns no Applied witness and cannot bypass native audits.
    static func enrollmentRecovery(_ candidate: SharedMediaNativeReceivedCandidate,
                                   context: ModelContext) throws -> NativeInitialEnrollmentRecovery? {
        guard !context.hasChanges else { throw SharedMediaStorageFailure.closed }
        let inventoryID = candidate.profile.inventoryID
        let inventory = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        guard try SharedMediaNativeAppEligibility.profile(inventory) == candidate.profile else { throw SharedMediaStorageFailure.stale }
        guard let saved = try SharedMediaNativeReceivingPhaseGraph.row(candidate.packageID, in: context) else { return nil }
        let row = Row(saved)
        guard row.draftGeneration == candidate.draftGeneration, row.operationID == candidate.operationID,
              row.revision == candidate.revision, row.preparedSHA256 == candidate.preparedSHA256,
              row.resultSHA256 == candidate.receivedSHA256 else { throw SharedMediaStorageFailure.stale }
        let source = try original(row, inventory: inventory), prepared = source.prepared
        guard let intent = try ObservationHistoryEnrollmentIntent.existing(observationID: prepared.observationID,
            ownerID: candidate.profile.ownerID, context: context) else { return nil }
        guard try ObservationHistoryEnrollmentIntent.baseline(observationID: prepared.observationID,
            ownerID: candidate.profile.ownerID, context: context) == nil else { throw SharedMediaStorageFailure.conflict }
        let consumer = try SharedMediaNativeReceivingRows.enrollmentRecoveryConsumer(prepared, receipt: intent, context: context)
        let cohort = try SharedMediaNativeConsumerCohort.AppliedInitial.decode(consumer.cohortData)
        let pin = try InitialPin(row: row, allocation: source.allocation)
        guard let completion = pin.completion else { throw SharedMediaStorageFailure.closed }
        let fields = try InitialAnalysisCanonical.parse(completion.bytes).object
        guard cohort.format == .initial, cohort.historyHandoffRemainingAdvances == 1, cohort.historyBaseline == nil,
              try cohort.original == source.received.reconstruct(prepared).cohort,
              cohort.receipt.originalRowSHA256 == (try SharedMediaNativeConsumerCohort.InitialApplicationReceipt.originalDigest(saved)),
              cohort.receipt.completionSHA256 == SharedMediaAcquisitionEncoding.digest(completion.bytes),
              cohort.receipt.referenceSHA256 == SharedMediaAcquisitionEncoding.digest(completion.reference),
              cohort.receipt.resultDigest == fields?["result_digest"]?.string,
              cohort.receipt.provenanceDigest == fields?["provenance_digest"]?.string,
              consumer.contractVersion == cohort.format.rawValue, consumer.cohortSHA256 == (try cohort.digest()),
              consumer.inventoryID == inventoryID, consumer.inventoryGeneration == candidate.profile.generation,
              consumer.ownerID == candidate.profile.ownerID, consumer.packageID == candidate.packageID,
              consumer.draftGeneration == candidate.draftGeneration, consumer.kindRaw == "localScan",
              consumer.id == prepared.bindingID, consumer.cursorKey == prepared.bindingID.uuidString.lowercased(),
              consumer.originQueueID == cohort.original.originQueueID, consumer.observationID == cohort.original.observationID,
              consumer.executionKindRaw == cohort.original.executionKind, consumer.inferenceGeneration == cohort.original.inferenceGeneration,
              consumer.digestVersion == 1, consumer.frozenPackageRevision == (try SharedMediaNativeFreezeCommit.decode(cohort.original.freeze.bytes).packageRevision),
              consumer.consumerID == prepared.observationID.uuidString.lowercased(), consumer.revision == 1,
              consumer.lifecycleRaw == "active", consumer.retirementID == nil else { throw SharedMediaStorageFailure.conflict }
        return .init(candidate: candidate, prepared: prepared, intent: intent, originalRowSHA256: cohort.receipt.originalRowSHA256,
            cohortSHA256: try cohort.digest())
    }

    /// Explicit retained-state witness. It never grants a save, a media path,
    /// enrollment or replay permission. No mutable scan display is snapshotted.
    @MainActor
    struct Applied {
        let row: Row
        let prepared: Intent.Prepared
        let cohort: SharedMediaNativeConsumerCohort.AppliedInitial
        let completion: InitialCompletionDocuments.CpmRecoveryRecord
        let admission: InitialCompletionDocuments.CpmAdmission
        let header: SharedMediaNativeAppEligibility.Header

        private init(row: Row, prepared: Intent.Prepared, cohort: SharedMediaNativeConsumerCohort.AppliedInitial,
                     completion: InitialCompletionDocuments.CpmRecoveryRecord, admission: InitialCompletionDocuments.CpmAdmission,
                     header: SharedMediaNativeAppEligibility.Header) {
            self.row = row; self.prepared = prepared; self.cohort = cohort
            self.completion = completion; self.admission = admission; self.header = header
        }

        static func read(_ saved: SharedMediaReceivingIntentRecord, inventory: SharedMediaInventoryRecord,
                         context: ModelContext, checkpoint: () throws -> Void = {}) throws -> Self {
            try checkpoint()
            guard !context.hasChanges else { throw SharedMediaStorageFailure.closed }
            let row = Row(saved)
            let source = try original(row, inventory: inventory)
            let prepared = source.prepared, received = source.received, allocation = source.allocation
            let pin = try InitialPin(row: row, allocation: allocation)
            guard let completion = pin.completion else { throw SharedMediaStorageFailure.closed }
            let consumer = try SharedMediaNativeReceivingRows.appliedConsumer(prepared, in: context)
            let cohort = try SharedMediaNativeConsumerCohort.AppliedInitial.decode(consumer.cohortData)
            let receipt = cohort.receipt
            let completionFields = try InitialAnalysisCanonical.parse(completion.bytes).object
            guard try cohort.original == received.reconstruct(prepared).cohort,
                  receipt.originalRowSHA256 == (try SharedMediaNativeConsumerCohort.InitialApplicationReceipt.originalDigest(saved)),
                  receipt.completionSHA256 == SharedMediaAcquisitionEncoding.digest(completion.bytes),
                  receipt.referenceSHA256 == SharedMediaAcquisitionEncoding.digest(completion.reference),
                  receipt.resultDigest == completionFields?["result_digest"]?.string,
                  receipt.provenanceDigest == completionFields?["provenance_digest"]?.string else {
                throw SharedMediaStorageFailure.conflict
            }
            let value = Self(row: row, prepared: prepared, cohort: cohort, completion: completion, admission: pin.admission,
                header: try currentHeader(prepared.profile, context: context))
            _ = try SharedMediaNativeConsumerGraph.validateAppliedInitial(consumer, applied: value,
                context: context, checkpoint: checkpoint)
            try checkpoint(); try value.requireCurrent(context: context)
            return value
        }

        func requireCurrent(context: ModelContext) throws {
            guard !context.hasChanges,
                  let saved = try SharedMediaNativeReceivingPhaseGraph.row(row.id, in: context), Row(saved) == row,
                  try currentHeader(prepared.profile, context: context) == header else { throw SharedMediaStorageFailure.stale }
            let consumer = try SharedMediaNativeReceivingRows.appliedConsumer(prepared, in: context)
            guard try consumer.cohortData == cohort.encoded(), consumer.cohortSHA256 == (try cohort.digest()),
                  consumer.contractVersion == cohort.format.rawValue, consumer.kindRaw == "localScan", consumer.revision == cohort.consumerRevision,
                  consumer.consumerID == prepared.observationID.uuidString.lowercased() else { throw SharedMediaStorageFailure.stale }
            if let acknowledged = cohort.historyBaseline {
                guard try NativeInitialHistoryBaseline.read(prepared, context: context)?.association == acknowledged else {
                    throw SharedMediaStorageFailure.conflict
                }
            }
        }

        func requireConsumerLink(_ consumer: SharedMediaConsumerRecord, context: ModelContext) throws {
            try requireCurrent(context: context)
            guard try SharedMediaNativeReceivingRows.appliedConsumer(prepared, in: context).persistentModelID
                == consumer.persistentModelID else { throw SharedMediaStorageFailure.conflict }
        }
    }

    func consumerBytes(context: ModelContext, checkpoint: () throws -> Void) throws -> Int64 {
        try requireCurrent(context: context)
        let rows = try SharedMediaNativeReceivingPhaseGraph.receivedRows(transaction, context: context)
        _ = try SharedMediaNativeConsumerGraph.validateAllocatedReceived(rows.consumer, allocation: self,
            context: context, checkpoint: checkpoint)
        return Int64(rows.consumer.cohortData.count)
    }

    func requireCurrent(context: ModelContext) throws {
        guard !context.hasChanges,
              let saved = try SharedMediaNativeReceivingPhaseGraph.row(row.id, in: context), Row(saved) == row,
              try Self.currentHeader(prepared.profile, context: context) == header else {
            throw SharedMediaStorageFailure.stale
        }
        try SharedMediaNativeReceivingRows.requireRecoveryPresentation(recoveryPresentationData,
            request: transaction, in: context)
    }

    func requireConsumerLink(_ consumer: SharedMediaConsumerRecord, value: SharedMediaNativeConsumerCohort,
                             context: ModelContext) throws {
        try requireCurrent(context: context)
        guard value == transaction.cohort, consumer.packageID == row.id,
              try SharedMediaNativeReceivingPhaseGraph.receivedRows(transaction, context: context)
                .consumer.persistentModelID == consumer.persistentModelID else {
            throw SharedMediaStorageFailure.conflict
        }
    }

    private static func currentHeader(_ profile: SharedMediaNativeAppProfile,
                                      context: ModelContext) throws -> SharedMediaNativeAppEligibility.Header {
        try SharedMediaNativeAppEligibility.snapshot(context: context,
            scope: .init(inventoryID: profile.inventoryID, generation: profile.generation,
                ownerID: profile.ownerID, storeIdentity: profile.storeIdentity, rootBinding: profile.rootIdentity))
    }
    static func saved(_ prepared: Intent.Prepared, context: ModelContext,
                      inventory: SharedMediaInventoryRecord) throws -> SharedMediaNativePhotoAllocation? {
        guard let witness = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory)[prepared.package.id] else {
            throw SharedMediaStorageFailure.stale
        }
        switch witness {
        case .allocating(let snapshot):
            guard snapshot.recoveryPresentationData == nil else { throw SharedMediaStorageFailure.closed }
            guard try snapshot.prepared.encoded() == prepared.encoded() else { throw SharedMediaStorageFailure.stale }
            return snapshot.allocation
        case .generic(let value):
            guard value.recoveryPresentationData == nil else { throw SharedMediaStorageFailure.closed }
            guard case .received(let p, _, _) = value.slot, try p.encoded() == prepared.encoded() else { throw SharedMediaStorageFailure.closed }
            return nil
        case .initial, .staged, .releasing: throw SharedMediaStorageFailure.closed
        }
    }

    static func requireReservation(_ allocation: SharedMediaNativePhotoAllocation, replacing oldAllocation: SharedMediaNativePhotoAllocation?,
                                   context: ModelContext, inventory: SharedMediaInventoryRecord,
                                   witnesses: [UUID: SharedMediaNativeReceivingCleanGraph.Witness], availableBytes: () throws -> Int64) throws {
        let charge = try allocation.storageCharge, oldCharge = try oldAllocation?.storageCharge ?? 0
        guard charge >= oldCharge else { throw SharedMediaStorageFailure.conflict }
        let packageID = allocation.claim.packageID
        let budget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: context,
            inventory: inventory, ownerID: allocation.claim.profile.ownerID, format: .appV2)
        guard let old = budget.metadataByPackage[packageID], old >= oldCharge,
              try PhotoPreparationPolicy.add([old - oldCharge, charge]) <= PhotoPreparationPolicy.metadata else {
            throw SharedMediaStorageFailure.capacity
        }
        let package = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        guard try PhotoPreparationPolicy.add([package.allocatedByteCount, old - oldCharge, charge]) <= PhotoPreparationPolicy.package else {
            throw SharedMediaStorageFailure.capacity
        }
        var totals = budget.totals
        try totals.includePhotoPhysical(materialized: 0, reserved: charge - oldCharge)
        if allocation.transferReservation != nil, oldAllocation?.transferReservation == nil {
            try totals.include(.init(packageID: packageID, pool: .transfer, materialized: 0,
                reserved: SharedMediaNativePhotoTransferReservation.copyAllowance))
        }
        try totals.checkAvailable(availableBytes())
        let terminal = try SharedMediaNativeTerminalScan.read(container: context.container, inventoryID: inventory.id)
        try SharedMediaNativeReceivingCleanGraph.requireReplacementRunway(inventoryRevision: inventory.revision,
            packageID: packageID, executionAdvances: allocation.remainingAdvances, saveAdvances: 1,
            witnesses: witnesses, historical: terminal)
    }

    /// Completion may preserve settled accounting, including exhausted time.
    /// Decoding an active reservation never supplies settlement authority.
    func requireSettledPresentation() throws {
        guard let bytes = recoveryPresentationData else { return }
        let value = try AnalysisRecoveryPresentation.decode(bytes, identity: .init(ownerID: prepared.profile.ownerID,
            observationID: prepared.observationID, operationID: prepared.operationID))
        guard value.activeReservationID == nil else { throw SharedMediaStorageFailure.closed }
    }

    static func initialCandidate(_ prepared: Intent.Prepared, context: ModelContext,
                                 inventory: SharedMediaInventoryRecord) throws -> Self {
        let witnesses = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory)
        let value: Self
        switch witnesses[prepared.package.id] {
        case .allocating(let snapshot), .initial(let snapshot): value = snapshot
        default: throw SharedMediaStorageFailure.closed
        }
        try value.requireSettledPresentation()
        guard value.allocation.completedRoles == nil || value.allocation.version == 17 else { throw SharedMediaStorageFailure.closed }
        guard try value.prepared.encoded() == prepared.encoded() else {
            throw SharedMediaStorageFailure.stale
        }
        return value
    }

}
