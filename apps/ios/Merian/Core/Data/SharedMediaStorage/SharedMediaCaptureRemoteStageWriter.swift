import Foundation
import SwiftData

/// Post-upload acknowledgement commit. The registered operation retains the
/// account/root fence across transport and this save; a saved acknowledgement
/// never replaces the local acceptance or proves final inference completion.
@MainActor
enum SharedMediaCaptureRemoteStageWriter {
    static func bind(_ receipt: CaptureStageReceipt, artifactID: UUID, container: ModelContainer,
                     authority: SharedMediaNativeAppOperationAuthority, files: SharedMediaCaptureArtifactFiles,
                     availableBytes: () throws -> Int64,
                     boundary: (SharedMediaCaptureReservationBoundary) throws -> Void = { _ in }) async throws -> SharedMediaCaptureRemoteStage {
        let before = try authority.header(container)
        let totals = try await SharedMediaCaptureBudget.evaluate(container, authority: authority, files: files)
        guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
        let context = ModelContext(container); context.autosaveEnabled = false
        guard let saved = try SharedMediaCaptureSubmissionReceipt.matching(scanID: receipt.scanID,
            generation: receipt.generation, in: context), case .accepted = saved.state,
              saved.submission.profile == authority.profile,
              saved.submission.rootBindingSHA256 == files.rootBindingSHA256,
              let artifact = saved.artifacts.first(where: { $0.request.id == artifactID }),
              artifact.phase == .ready, let stage = artifact.stage else { throw SharedMediaStorageFailure.conflict }
        try receipt.requirePlan(saved.submission.plan())
        // The immutable local receipt proves role, ordinal, hash, bytes and
        // membership. All authenticated server receipts must bind that same plan.
        for prior in saved.artifacts.compactMap(\.remoteStage) {
            guard prior.serverRequestSHA256 == receipt.requestSHA256 else { throw SharedMediaStorageFailure.conflict }
        }
        if let prior = artifact.remoteStage {
            let replay = try SharedMediaCaptureRemoteStage(receipt: receipt, request: artifact.request,
                stage: stage, inventoryRevision: prior.inventoryRevision, submission: saved.submission)
            guard replay == prior else { throw SharedMediaStorageFailure.conflict }
            return prior
        }
        let revision = try SharedMediaStoragePolicy.add(before.inventory.revision, 1)
        let value = try SharedMediaCaptureRemoteStage(receipt: receipt, request: artifact.request,
            stage: stage, inventoryRevision: revision, submission: saved.submission)
        let encoded = try value.encoded(request: artifact.request, stage: stage)
        // The complete bounded envelope was reserved before any upload started.
        try totals.checkAvailable(availableBytes())
        let id = artifactID, inventoryID = authority.profile.inventoryID
        let row = try one(context, FetchDescriptor<SharedMediaOrdinaryArtifactRecord>(predicate: #Predicate { $0.id == id }))
        let inventory = try one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        row.acceptanceData = encoded; row.acceptanceSHA256 = SharedMediaAcquisitionEncoding.digest(encoded)
        row.revision = 3; inventory.revision = revision
        try boundary(.beforeSave)
        guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
        try files.check(); try context.save()
        try boundary(.afterSave)
        _ = try await SharedMediaCaptureBudget.evaluate(container, authority: authority, files: files)
        let read = ModelContext(container); read.autosaveEnabled = false
        guard let committed = try SharedMediaCaptureSubmissionReceipt.matching(scanID: receipt.scanID,
            generation: receipt.generation, in: read), committed.submission == saved.submission,
              committed.state == saved.state,
              committed.artifacts.first(where: { $0.request.id == artifactID })?.remoteStage == value else {
            throw SharedMediaStorageFailure.conflict
        }
        return value
    }

    private static func one<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>) throws -> T {
        var query = descriptor; query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first else { throw SharedMediaStorageFailure.conflict }
        return row
    }
}
