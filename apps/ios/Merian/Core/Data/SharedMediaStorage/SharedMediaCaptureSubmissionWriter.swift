import Foundation
import SwiftData

enum SharedMediaCaptureReservationBoundary: CaseIterable { case beforeSave, afterSave }

/// Reserves the entire immutable observation before any child file is written.
/// Queue admission and network dispatch remain separate committed transitions.
@MainActor
enum SharedMediaCaptureSubmissionWriter {
    static func reserve(plan: CaptureInitialEvidencePlan, context input: SharedMediaCaptureSubmissionContext,
                        expectedJournal: SharedMediaCaptureDraftJournalReceipt.Snapshot? = nil,
                        container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                        files: SharedMediaCaptureArtifactFiles, availableBytes: () throws -> Int64,
                        boundary: (SharedMediaCaptureReservationBoundary) throws -> Void = { _ in }) async throws -> SharedMediaCaptureSubmissionReceipt.Snapshot {
        try input.validate(plan: plan)
        guard plan.ownerID == authority.profile.ownerID else { throw SharedMediaStorageFailure.conflict }
        let before = try authority.header(container)
        var totals = try await SharedMediaCaptureBudget.evaluate(container, authority: authority, files: files)
        guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
        let context = ModelContext(container); context.autosaveEnabled = false
        if let saved = try SharedMediaCaptureSubmissionReceipt.matching(scanID: plan.scanID, generation: plan.generation, in: context) {
            guard saved.submission.profile == authority.profile,
                  saved.submission.rootBindingSHA256 == files.rootBindingSHA256,
                  saved.submission.context == input, try saved.submission.plan() == plan else {
                throw SharedMediaStorageFailure.conflict
            }
            return saved
        }
        try requireUnclaimedMembers(plan, context: context)
        try SharedMediaCaptureDraftSourceBinding.requireUnclaimed(scan: plan.scanID, context: context)
        let binding = try SharedMediaCaptureDraftSourceBinding.read(plan: plan, profile: authority.profile,
            rootBindingSHA256: files.rootBindingSHA256, context: context)
        let value = try SharedMediaCaptureSubmission(plan: plan, context: input, profile: authority.profile,
            writerEpoch: authority.writerEpoch, inventoryRevision: before.inventory.revision,
            rootBindingSHA256: files.rootBindingSHA256, eventID: UUID(), artifactIDs: binding.artifactIDs,
            retainedArtifacts: binding.sources)
        let data = try value.encoded(), packageBytes = try value.packageBytes
        if binding.sources.isEmpty {
            try totals.includePhotoPackage(id: value.scanID, bytes: packageBytes)
            try totals.includePhotoPhysical(materialized: 0, reserved: packageBytes)
        } else {
            let journal = try SharedMediaCaptureDraftJournalReceipt.matching(scanID: plan.scanID, generation: plan.generation, context: context)
            let journalBytes = try journal.map { try SharedMediaStoragePolicy.add($0.metadataBytes, $0.futureBytes) } ?? 0
            try totals.bindCapturePackage(id: value.scanID, sourceBytes: SharedMediaStoragePolicy.add(binding.packageBytes, journalBytes),
                planBytes: SharedMediaStoragePolicy.add(packageBytes, journalBytes))
            try totals.includePhotoPhysical(materialized: 0,
                reserved: SharedMediaCaptureDraftSourceBinding.newPhysicalReservation(value,
                    sourceIDs: Set(binding.sources.map { $0.request.id })))
        }
        try totals.checkAvailable(availableBytes())
        let inventoryID = authority.profile.inventoryID
        var query = FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID })
        query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count == 1, let inventory = rows.first,
              inventory.revision == before.inventory.revision,
              try SharedMediaNativeAppEligibility.profile(inventory) == authority.profile else {
            throw SharedMediaStorageFailure.stale
        }
        context.insert(SharedMediaOrdinarySubmissionRecord(inventoryID: inventoryID,
            inventoryGeneration: authority.profile.generation, ownerID: authority.profile.ownerID,
            recipientScanID: value.scanID, submissionGeneration: value.generation, jobID: value.jobID,
            eventID: value.eventID, writerEpoch: value.writerEpoch, formatRaw: value.format.rawValue,
            requestData: data, requestSHA256: SharedMediaAcquisitionEncoding.digest(data), observationSHA256: value.observation.sha256))
        try SharedMediaCaptureDraftJournalSubmission.reserve(plan: plan, input: input, expected: expectedJournal, context: context)
        inventory.revision = try SharedMediaStoragePolicy.add(inventory.revision, 1)
        try boundary(.beforeSave)
        guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
        try files.check(); try context.save()
        try boundary(.afterSave)
        _ = try authority.header(container)
        _ = try await SharedMediaCaptureBudget.evaluate(container, authority: authority, files: files)
        let readback = ModelContext(container); readback.autosaveEnabled = false
        guard let saved = try SharedMediaCaptureSubmissionReceipt.matching(scanID: plan.scanID, generation: plan.generation, in: readback), saved.submission == value else {
            throw SharedMediaStorageFailure.conflict
        }
        return saved
    }

    /// A reserved parent already owns its complete future membership, even
    /// before any artifact row exists. A second observation cannot borrow those
    /// identities or make the original reservation impossible to finish.
    private static func requireUnclaimedMembers(_ plan: CaptureInitialEvidencePlan, context: ModelContext) throws {
        let mediaIDs = Set(plan.uploads.map { $0.artifact.mediaID })
        let format = SharedMediaCaptureSubmission.Format.v1.rawValue
        var query = FetchDescriptor<SharedMediaOrdinarySubmissionRecord>(predicate: #Predicate { $0.formatRaw == format },
            sortBy: [SortDescriptor(\.cursorKey)])
        query.fetchLimit = SharedMediaStoragePolicy.pageSize
        var offset = 0
        while true {
            try Task.checkCancellation(); query.fetchOffset = offset
            let rows = try context.fetch(query)
            for row in rows {
                let saved = try SharedMediaCaptureSubmissionReceipt.auditRead(row, in: context)
                guard mediaIDs.isDisjoint(with: Set(saved.submission.members.map(\.mediaID))) else {
                    throw SharedMediaStorageFailure.conflict
                }
            }
            if rows.count < SharedMediaStoragePolicy.pageSize { return }
            let (next, overflow) = offset.addingReportingOverflow(rows.count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }
            offset = next
        }
    }

}
