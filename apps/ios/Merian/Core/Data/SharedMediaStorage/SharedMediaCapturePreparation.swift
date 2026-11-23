import Foundation
import SwiftData

/// Retains final output files before V71 freezes a submission. The same root,
/// scan lock, artifact writer, and accounting own both preparing and accepted
/// work. Cold recovery reuses exact ready files; missing output stays held.
@MainActor
enum SharedMediaCapturePreparation {
    typealias Receipt = SharedMediaCaptureDraftJournalReceipt

    static func retain(plan: CaptureInitialEvidencePlan, expected: Receipt.Snapshot,
                       container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                       files: SharedMediaCaptureArtifactFiles, availableBytes: () throws -> Int64,
                       readArtifact: SharedMediaCaptureDraftAcceptance.ReadArtifact,
                       artifactBoundary: SharedMediaCaptureArtifactWriter.Boundary = { _ in }) async throws -> Receipt.Snapshot {
        let before = try authority.header(container)
        _ = try await SharedMediaCaptureBudget.evaluate(container, authority: authority, files: files)
        guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
        let read = ModelContext(container); read.autosaveEnabled = false
        guard var saved = try Receipt.matching(scanID: plan.scanID, generation: plan.generation, context: read),
              saved.value.profile == authority.profile, saved.value.rootBindingSHA256 == files.rootBindingSHA256 else {
            throw SharedMediaStorageFailure.stale
        }
        if saved.value.phase == .submitting || saved.value.phase == .accepted {
            guard saved.value.frozenObservation?.bytes == (try plan.encoded()) else { throw SharedMediaStorageFailure.conflict }
            return saved
        }
        if saved.value.phase == .editing {
            guard saved == expected else { throw SharedMediaStorageFailure.stale }
            let attempt = try SharedMediaCapturePreparedAttempt(plan: plan, journal: saved)
            let old = saved.value
            let next = SharedMediaCaptureDraftJournal(format: old.format, profile: old.profile,
                rootBindingSHA256: old.rootBindingSHA256, scanID: old.scanID, generation: old.generation,
                revision: try SharedMediaStoragePolicy.add(old.revision, 1), phase: .preparing,
                sources: old.sources, items: old.items, frozenObservation: nil, frozenContext: nil, preparation: attempt, abortedPreparations: old.abortedPreparations)
            saved = try await SharedMediaCaptureDraftJournalStore.saveEditing(next, replacing: saved,
                container: container, authority: authority, files: files, availableBytes: availableBytes)
        }
        guard saved.value.phase == .preparing, let attempt = saved.value.preparation,
              try attempt.plan(ownerID: authority.profile.ownerID) == plan,
              saved == expected || attempt.previousJournalSHA256 == expected.sha256 else {
            throw SharedMediaStorageFailure.conflict
        }
        for upload in plan.uploads {
            if saved.value.sources.contains(where: { $0.input.mediaID == upload.artifact.mediaID }) { continue }
            try Task.checkCancellation()
            let input = try attempt.input(mediaID: upload.artifact.mediaID, ownerID: plan.ownerID)
            let context = ModelContext(container); context.autosaveEnabled = false
            let id = input.id, media = input.mediaID
            var query = FetchDescriptor<SharedMediaOrdinaryArtifactRecord>(predicate: #Predicate { $0.id == id || $0.mediaID == media })
            query.fetchLimit = 2
            let rows = try context.fetch(query)
            guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
            if let row = rows.first {
                let artifact = try SharedMediaCaptureArtifactLedger.receipt(row)
                guard input.matches(artifact.request), artifact.remoteStage == nil else { throw SharedMediaStorageFailure.conflict }
                if artifact.phase == .ready { continue }
            }
            let header = try authority.header(container)
            let bytes = try await readArtifact(input)
            guard try authority.header(container) == header else { throw SharedMediaStorageFailure.stale }
            _ = try await SharedMediaCaptureArtifactWriter.materialize(input, bytes: bytes, container: container,
                authority: authority, files: files, availableBytes: availableBytes, boundary: artifactBoundary)
        }
        _ = try await SharedMediaCaptureBudget.evaluate(container, authority: authority, files: files)
        let final = ModelContext(container); final.autosaveEnabled = false
        guard try Receipt.matching(scanID: plan.scanID, generation: plan.generation, context: final) == saved else {
            throw SharedMediaStorageFailure.stale
        }
        // This proves the complete cohort is ready and exactly matches the
        // planned IDs before any immutable submission or queue row can exist.
        _ = try SharedMediaCaptureDraftSourceBinding.read(plan: plan, profile: authority.profile,
            rootBindingSHA256: files.rootBindingSHA256, context: final)
        return saved
    }
}
