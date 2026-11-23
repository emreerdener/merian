import Foundation
import SwiftData

/// Irreversible local abort of an entire pre-parent preparation attempt. The
/// original sources and review state survive; no queue or provider may exist.
@MainActor
enum SharedMediaCapturePreparationAbort {
    typealias Receipt = SharedMediaCaptureDraftJournalReceipt

    static func abort(_ expected: Receipt.Snapshot, container: ModelContainer,
                      authority: SharedMediaNativeAppOperationAuthority, files: SharedMediaCaptureArtifactFiles,
                      availableBytes: () throws -> Int64,
                      journalBoundary: (SharedMediaCaptureDraftJournalBoundary) throws -> Void = { _ in },
                      artifactBoundary: SharedMediaCaptureSourceDiscard.Boundary = { _ in }) async throws -> Receipt.Snapshot {
        let value = expected.value
        guard value.profile == authority.profile, value.rootBindingSHA256 == files.rootBindingSHA256,
              value.phase == .preparing || value.phase == .abortingPreparation else { throw SharedMediaStorageFailure.closed }
        let abortValue = value.phase == .abortingPreparation ? value
            : try SharedMediaCaptureDraftJournalStore.preparationSuccessor(value, phase: .abortingPreparation)
        let abortBytes = try abortValue.encoded()
        let abortReceipt = Receipt.Snapshot(value: abortValue, bytes: abortBytes, sha256: SharedMediaAcquisitionEncoding.digest(abortBytes))
        var finished = try SharedMediaCaptureDraftJournalStore.preparationSuccessor(abortValue, phase: .editing)
        finished.abortedPreparations = (abortValue.abortedPreparations ?? []) + [try tombstone(abortReceipt, container: container)]
        let read = ModelContext(container); read.autosaveEnabled = false
        guard let current = try Receipt.matching(scanID: value.scanID, generation: value.generation, context: read),
              current == expected || current == abortReceipt || current.value == finished else { throw SharedMediaStorageFailure.stale }
        try SharedMediaCaptureDraftSourceBinding.requireUnclaimed(scan: value.scanID, context: read)
        guard try SharedMediaCaptureSubmissionReceipt.matching(scanID: value.scanID, generation: value.generation, in: read) == nil else {
            throw SharedMediaStorageFailure.closed
        }
        if current.value == finished {
            try requireReleased(abortReceipt, container: container)
            _ = try await SharedMediaCaptureBudget.evaluate(container, authority: authority, files: files)
            return current
        }
        var saved = current
        if current.value.phase == .preparing {
            let cleanupTarget = try ambiguousTarget(current, container: container, files: files)
            saved = try await SharedMediaCaptureDraftJournalStore.beginPreparationAbort(current, container: container,
                authority: authority, files: files, availableBytes: availableBytes, cleanupTarget: cleanupTarget, boundary: journalBoundary)
        }
        guard saved == abortReceipt, let attempt = saved.value.preparation else { throw SharedMediaStorageFailure.conflict }
        let digest = try attempt.digest
        for input in try inputs(saved) {
            try Task.checkCancellation()
            guard var artifact = try member(input, expected: saved, container: container) else { continue }
            let before = try authority.header(container)
            _ = try await SharedMediaCaptureBudget.evaluate(container, authority: authority, files: files,
                cleanupTarget: ambiguousTarget(saved, container: container, files: files))
            guard try authority.header(container) == before,
                  try member(input, expected: saved, container: container) == artifact else { throw SharedMediaStorageFailure.stale }
            if artifact.retirement == nil {
                let context = ModelContext(container); context.autosaveEnabled = false
                let facts = try files.preparedDiscardIdentities(artifact, preparationSHA256: digest, context: context)
                let intent = try SharedMediaCaptureArtifactRetirement(request: artifact.request, stage: artifact.stage,
                    inventoryRevision: SharedMediaStoragePolicy.add(before.inventory.revision, 1),
                    partialIdentity: facts.partial, finalIdentity: facts.final, preparationSHA256: digest)
                try SharedMediaCaptureRetirementWriter.persist(artifact, retirement: intent, container: container,
                    authority: authority, boundary: artifactBoundary)
                guard let retained = try member(input, expected: saved, container: container) else { throw SharedMediaStorageFailure.conflict }
                artifact = retained
            }
            guard let retirement = artifact.retirement, retirement.preparationSHA256 == digest else { throw SharedMediaStorageFailure.conflict }
            if retirement.releasedRevision == nil {
                try artifactBoundary(.beforeUnlink)
                _ = try authority.header(container)
                let context = ModelContext(container); context.autosaveEnabled = false
                try SharedMediaCapturePreparedAttempt.requireAbortMember(artifact.request, digest: digest, context: context)
                guard try member(input, expected: saved, container: container) == artifact else { throw SharedMediaStorageFailure.stale }
                try files.unlinkDiscardedSource(artifact)
                try artifactBoundary(.afterUnlink)
                let header = try authority.header(container)
                let released = try retirement.releasing(at: SharedMediaStoragePolicy.add(header.inventory.revision, 1),
                    request: artifact.request, stage: artifact.stage)
                try SharedMediaCaptureRetirementWriter.persist(artifact, retirement: released, container: container,
                    authority: authority, boundary: artifactBoundary)
            }
        }
        return try await SharedMediaCaptureDraftJournalStore.finishPreparationAbort(saved, container: container,
            authority: authority, files: files, availableBytes: availableBytes, boundary: journalBoundary)
    }

    static func requireReleased(_ expected: Receipt.Snapshot, container: ModelContainer) throws {
        guard expected.value.phase == .abortingPreparation, let attempt = expected.value.preparation else { throw SharedMediaStorageFailure.closed }
        for input in try inputs(expected) {
            if let artifact = try member(input, expected: expected, container: container) {
                guard artifact.retirement?.version == 2, artifact.retirement?.releasedRevision != nil,
                      artifact.retirement?.preparationSHA256 == (try attempt.digest) else { throw SharedMediaStorageFailure.closed }
            }
        }
        // The caller's complete physical audit proves absence for inputs that
        // never reserved a row. No missing member is represented as a release.
    }

    static func tombstone(_ expected: Receipt.Snapshot, container: ModelContainer) throws -> SharedMediaCaptureAbortedPreparation {
        guard let attempt = expected.value.preparation else { throw SharedMediaStorageFailure.conflict }
        let members = try inputs(expected).map { input in
            let value = try member(input, expected: expected, container: container)
            return SharedMediaCaptureAbortedPreparation.Member(artifactID: input.id, mediaID: input.mediaID,
                requestSHA256: try value?.request.digest)
        }
        let proof = try SharedMediaCaptureAbortedPreparation(attemptSHA256: attempt.digest,
            planSHA256: attempt.observation.sha256, members: members)
        try proof.validate()
        return proof
    }

    static func ambiguousTarget(_ expected: Receipt.Snapshot, container: ModelContainer,
                                files: SharedMediaCaptureArtifactFiles) throws -> UUID? {
        var result: UUID?
        for input in try inputs(expected) {
            if let artifact = try member(input, expected: expected, container: container), try files.inspect(artifact).ambiguous {
                guard result == nil else { throw SharedMediaStorageFailure.conflict }
                result = input.id
            }
        }
        return result
    }

    private static func inputs(_ expected: Receipt.Snapshot) throws -> [SharedMediaCaptureArtifactInput] {
        guard let attempt = expected.value.preparation else { throw SharedMediaStorageFailure.conflict }
        return try attempt.plan(ownerID: expected.value.profile.ownerID).uploads.compactMap { upload in
            if expected.value.sources.contains(where: { $0.input.mediaID == upload.artifact.mediaID }) { return nil }
            return try attempt.input(mediaID: upload.artifact.mediaID, ownerID: expected.value.profile.ownerID)
        }
    }

    private static func member(_ input: SharedMediaCaptureArtifactInput, expected: Receipt.Snapshot,
                               container: ModelContainer) throws -> SharedMediaCaptureArtifactLedger.Snapshot? {
        let context = ModelContext(container); context.autosaveEnabled = false
        let id = input.id, media = input.mediaID
        var query = FetchDescriptor<SharedMediaOrdinaryArtifactRecord>(predicate: #Predicate { $0.id == id || $0.mediaID == media })
        query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
        guard let row = rows.first else { return nil }
        let artifact = try SharedMediaCaptureArtifactLedger.auditRead(id: row.id, profile: expected.value.profile,
            rootBindingSHA256: expected.value.rootBindingSHA256, context: context)
        guard input.matches(artifact.request), artifact.remoteStage == nil else { throw SharedMediaStorageFailure.conflict }
        return artifact
    }
}
