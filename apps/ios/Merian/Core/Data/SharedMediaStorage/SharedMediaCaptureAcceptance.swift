import Foundation
import SwiftData

/// Commits the queue and its complete local capture cohort together. This does
/// not upload, release originals or prove server completion.
@MainActor
enum SharedMediaCaptureAcceptance {
    static let mediaAuthority = "sharedCaptureInitialV1"

    static func accept(scanID: UUID, generation: UUID, container: ModelContainer,
                       authority: SharedMediaNativeAppOperationAuthority, files: SharedMediaCaptureArtifactFiles,
                       availableBytes: () throws -> Int64,
                       boundary: (SharedMediaCaptureReservationBoundary) throws -> Void = { _ in }) async throws -> SharedMediaCaptureSubmissionAcceptance {
        let before = try authority.header(container)
        let totals = try await SharedMediaCaptureBudget.evaluate(container, authority: authority, files: files)
        guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
        let context = ModelContext(container); context.autosaveEnabled = false
        guard let saved = try SharedMediaCaptureSubmissionReceipt.matching(scanID: scanID, generation: generation, in: context),
              saved.submission.scanID == scanID, saved.submission.generation == generation,
              saved.submission.profile == authority.profile, saved.submission.rootBindingSHA256 == files.rootBindingSHA256 else {
            throw SharedMediaStorageFailure.conflict
        }
        let submission = saved.submission, queue = try queue(submission)
        if case .accepted(let acceptance) = saved.state {
            // Retry counters and dispatch metadata may have advanced since the
            // original save. The immutable receipt and funding identity remain
            // mandatory; never overwrite the live job to replay acceptance.
            try SharedMediaCaptureQueueIdentity.require(submission, in: context)
            return acceptance
        }
        try queue.requireAbsent(in: context)
        let revision = try SharedMediaStoragePolicy.add(before.inventory.revision, 1)
        let acceptance = try SharedMediaCaptureSubmissionAcceptance(submission: submission,
            artifacts: saved.artifacts, inventoryRevision: revision)
        let data = try acceptance.encoded(submission: submission, artifacts: saved.artifacts)
        // The parent already reserves acceptance bytes. Queue context is a new
        // copy and needs independent free-space headroom before its atomic save.
        let contextBytes = try SharedMediaAcquisitionEncoding.encode(submission.context, maximum: Int(PhotoPreparationPolicy.metadata))
        try totals.checkAvailable(availableBytes(), additionalReservation:
            SharedMediaStoragePolicy.add(Int64(contextBytes.count + queue.metadata.json.utf8.count), 8192))
        let inventoryID = authority.profile.inventoryID
        let inventory = try one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let parent = try one(context, FetchDescriptor<SharedMediaOrdinarySubmissionRecord>(predicate: #Predicate { $0.id == generation }))
        try SharedMediaCaptureDraftJournalSubmission.accept(submission, context: context)
        let rows = queue.makeRows()
        context.insert(rows.scan); context.insert(rows.job); context.insert(rows.event)
        if let goal = rows.goal { context.insert(goal) }
        parent.phaseRaw = "accepted"; parent.revision = 1
        parent.acceptanceData = data; parent.acceptanceSHA256 = SharedMediaAcquisitionEncoding.digest(data)
        inventory.revision = revision
        try queue.requireRows(rows)
        try boundary(.beforeSave)
        guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
        try files.check(); try context.save()
        try boundary(.afterSave)
        _ = try authority.header(container)
        _ = try await SharedMediaCaptureBudget.evaluate(container, authority: authority, files: files)
        let read = ModelContext(container); read.autosaveEnabled = false
        guard let committed = try SharedMediaCaptureSubmissionReceipt.matching(scanID: scanID, generation: generation, in: read),
              committed.submission == submission, committed.state == .accepted(acceptance),
              committed.artifacts == saved.artifacts else { throw SharedMediaStorageFailure.conflict }
        try queue.requireSaved(in: read)
        return acceptance
    }

    private static func queue(_ submission: SharedMediaCaptureSubmission) throws -> SharedMediaInitialQueueAdmission {
        let plan = try submission.plan(), context = submission.context
        try context.validate(plan: plan)
        return try .init(identity: .init(ownerID: plan.ownerID, scanID: plan.scanID, generation: plan.generation),
            eventIdentity: submission.eventID, jobID: submission.jobID, mediaAuthority: mediaAuthority,
            metadata: context.metadata(plan: plan), timestamp: context.timestamp, telemetry: context.telemetry,
            blurScore: context.blurScore, preferredGoal: context.preferredGoal, fieldNotes: context.initialFieldNotes,
            approximateBytes: plan.uploads.reduce(Int64(0)) { try SharedMediaStoragePolicy.add($0, Int64($1.artifact.byteCount)) })
    }

    private static func one<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>) throws -> T {
        var query = descriptor; query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first else { throw SharedMediaStorageFailure.conflict }
        return row
    }
}
