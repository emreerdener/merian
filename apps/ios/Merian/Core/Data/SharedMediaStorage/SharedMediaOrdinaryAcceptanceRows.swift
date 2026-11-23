import Foundation
import SwiftData

/// Closed write set for one ordinary admission. The registered owner supplies
/// the audited predecessor and file seals; these rows do not grant a save.
@MainActor
struct SharedMediaOrdinaryAcceptanceRows {
    typealias OriginalRows = SharedMediaNativeAppOriginalRows
    let admission: SharedMediaOrdinaryQueueAdmission
    let holds: SharedMediaOrdinaryHoldCohort
    let acceptance: SharedMediaOrdinarySubmissionAcceptance
    let parent: SharedMediaOrdinarySubmissionRecord
    let transfers: [SharedMediaOrdinaryTransferRecord]
    let queue: SharedMediaOrdinaryQueueAdmission.Rows
    let inventory: SharedMediaInventoryRecord
    let originals: [UUID: OriginalRows]
    let metadataBytes: Int64
    private let contextID: ObjectIdentifier
    private let inserted: Set<PersistentIdentifier>
    private let updated: Set<PersistentIdentifier>

    init(context: ModelContext, admission: SharedMediaOrdinaryQueueAdmission,
         holds: SharedMediaOrdinaryHoldCohort) throws {
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        let submission = admission.submission
        try submission.validate(holds: holds)
        try admission.requireAbsent(in: context)
        guard try SharedMediaOrdinarySubmissionReceipt.existing(submission, in: context) == nil else {
            throw SharedMediaStorageFailure.conflict
        }
        self.admission = admission; self.holds = holds; contextID = ObjectIdentifier(context)
        acceptance = try .init(submission: submission, holds: holds)
        let body = try submission.encoded()
        parent = SharedMediaOrdinarySubmissionRecord(inventoryID: submission.profile.inventoryID,
            inventoryGeneration: submission.profile.generation, ownerID: submission.profile.ownerID,
            recipientScanID: submission.scanID, submissionGeneration: submission.generation,
            jobID: submission.jobID, eventID: submission.eventID, writerEpoch: submission.writerEpoch,
            formatRaw: submission.format.rawValue, requestData: body,
            requestSHA256: SharedMediaAcquisitionEncoding.digest(body), observationSHA256: submission.observation.sha256)
        parent.phaseRaw = "accepted"; parent.revision = 1
        let accepted = try acceptance.encoded(submission: submission, holds: holds)
        parent.acceptanceData = accepted; parent.acceptanceSHA256 = SharedMediaAcquisitionEncoding.digest(accepted)
        let receipts = try holds.acceptances()
        transfers = try holds.requests.map { request in
            let bytes = try request.encoded()
            guard let receipt = receipts[request.id] else { throw SharedMediaStorageFailure.conflict }
            let accepted = try receipt.encoded(request: request)
            let row = SharedMediaOrdinaryTransferRecord(id: request.id, inventoryID: request.profile.inventoryID,
                inventoryGeneration: request.profile.generation, ownerID: request.profile.ownerID,
                sourceAssetID: request.source.assetID, sourceReferenceID: request.source.referenceID,
                recipientScanID: request.recipient.scanID, submissionGeneration: request.recipient.submissionGeneration,
                writerEpoch: request.writerEpoch, requestData: bytes, requestSHA256: SharedMediaAcquisitionEncoding.digest(bytes))
            row.phaseRaw = "accepted"; row.revision = 1
            row.acceptanceData = accepted; row.acceptanceSHA256 = SharedMediaAcquisitionEncoding.digest(accepted)
            return row
        }
        metadataBytes = try transfers.reduce(Int64(body.count + accepted.count + 128)) {
            try SharedMediaStoragePolicy.add($0, SharedMediaOrdinaryHoldReceipt.read($1).metadataBytes)
        }
        guard metadataBytes <= PhotoPreparationPolicy.metadata else { throw SharedMediaStorageFailure.capacity }
        var selected: [UUID: OriginalRows] = [:]
        for request in holds.requests {
            let rows = try OriginalRows(context, profile: submission.profile, source: request.source)
            guard rows.inventory.revision == request.inventoryRevision,
                  rows.count.liveCount == request.liveCount, rows.count.revision == request.countRevision else {
                throw SharedMediaStorageFailure.stale
            }
            selected[request.source.assetID] = rows
        }
        guard let first = selected.values.first else { throw SharedMediaStorageFailure.conflict }
        originals = selected; inventory = first.inventory; queue = admission.makeRows()
        // Inserted identities are collected after insertion: SwiftData may
        // replace an unattached model's temporary identifier when attaching it.
        context.insert(parent)
        for row in transfers { context.insert(row) }
        context.insert(queue.scan); context.insert(queue.job); context.insert(queue.event)
        if let goal = queue.goal { context.insert(goal) }
        inserted = queue.identities.union(transfers.map(\.persistentModelID)).union([parent.persistentModelID])
        updated = Set(selected.values.map { $0.count.persistentModelID }).union([inventory.persistentModelID])
        for (id, rows) in selected {
            let request = try holds.requests.first(where: { $0.source.assetID == id }).unwrapOrdinary()
            let receipt = try receipts[request.id].unwrapOrdinary()
            rows.count.liveCount = receipt.liveCount; rows.count.revision = receipt.countRevision
        }
        inventory.revision = acceptance.inventoryRevision
    }

    func validate(_ context: ModelContext) throws {
        guard ObjectIdentifier(context) == contextID,
              context.deletedModelsArray.isEmpty,
              Set(context.insertedModelsArray.map(\.persistentModelID)) == inserted,
              Set(context.changedModelsArray.map(\.persistentModelID)).subtracting(inserted) == updated,
              inventory.revision == acceptance.inventoryRevision else { throw SharedMediaStorageFailure.conflict }
        try admission.requireRows(queue)
        let submission = admission.submission
        // The strict receipt reader needs a clean context. Compare every parent
        // field here; clean readback independently decodes and joins the cohort.
        guard parent.schemaVersion == 1, parent.id == submission.generation,
              parent.cursorKey == submission.generation.uuidString.lowercased(),
              parent.identityKey == submission.identityKey,
              parent.scanKey == [submission.profile.ownerID, submission.scanID].map({ $0.uuidString.lowercased() }).joined(separator: ":"),
              parent.inventoryID == submission.profile.inventoryID, parent.inventoryGeneration == submission.profile.generation,
              parent.ownerID == submission.profile.ownerID, parent.recipientScanID == submission.scanID,
              parent.submissionGeneration == submission.generation, parent.jobID == submission.jobID,
              parent.eventID == submission.eventID, parent.writerEpoch == submission.writerEpoch,
              parent.phaseRaw == "accepted", parent.revision == 1, parent.formatRaw == submission.format.rawValue,
              parent.requestData == (try submission.encoded()), parent.requestSHA256 == acceptance.requestSHA256,
              parent.observationSHA256 == submission.observation.sha256,
              parent.acceptanceData == (try acceptance.encoded(submission: submission, holds: holds)),
              parent.acceptanceSHA256 == parent.acceptanceData.map(SharedMediaAcquisitionEncoding.digest),
              parent.retirementData == nil, parent.retirementSHA256 == nil else { throw SharedMediaStorageFailure.conflict }
        let receipts = try holds.acceptances()
        for (request, row) in zip(holds.requests, transfers) {
            guard let receipt = receipts[request.id],
                  try SharedMediaOrdinaryHoldReceipt.read(row).state == .accepted(request, receipt),
                  let rows = originals[request.source.assetID],
                  rows.count.id == request.source.assetID, rows.count.inventoryID == request.profile.inventoryID,
                  rows.count.inventoryGeneration == request.profile.generation, rows.count.ownerID == request.profile.ownerID,
                  rows.count.assetGeneration == request.source.assetGeneration, rows.count.retirementID == nil,
                  rows.count.liveCount == receipt.liveCount, rows.count.revision == receipt.countRevision else {
                throw SharedMediaStorageFailure.conflict
            }
        }
        guard try SharedMediaNativeAppEligibility.profile(inventory) == submission.profile else {
            throw SharedMediaStorageFailure.conflict
        }
    }
}

private extension Optional {
    func unwrapOrdinary() throws -> Wrapped {
        guard let value = self else { throw SharedMediaStorageFailure.conflict }; return value
    }
}
