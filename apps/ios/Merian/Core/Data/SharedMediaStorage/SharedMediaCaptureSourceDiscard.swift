import Foundation
import SwiftData

enum SharedMediaCaptureSourceDiscardBoundary: CaseIterable {
    case beforeIntentSave, afterIntentSave, beforeUnlink, afterUnlink, beforeReleaseSave, afterReleaseSave
}

/// Runs only under the registered root/account owner and the same scan lock as
/// final-plan binding. A durable intent is irreversible, including after a lost
/// save reply. Accepted submission members require a separate release authority.
@MainActor
enum SharedMediaCaptureSourceDiscard {
    typealias Boundary = (SharedMediaCaptureSourceDiscardBoundary) throws -> Void

    static func discard(_ expected: SharedMediaCaptureDraftSourceInput, container: ModelContainer,
                        authority: SharedMediaNativeAppOperationAuthority, files: SharedMediaCaptureArtifactFiles,
                        boundary: Boundary = { _ in }) async throws {
        let before = try authority.header(container)
        let journalContext = ModelContext(container); journalContext.autosaveEnabled = false
        try SharedMediaCaptureDraftJournalReceipt.requireSource(expected, states: [.discarding, .released],
            phases: [.editing, .discarding, .released], context: journalContext)
        if try hasNoReservation(expected, container: container) {
            // A failure before reservation may leave no row. Only a complete
            // physical/graph audit can prove that no orphan file was created.
            _ = try await SharedMediaNativeScopedAudit.runAppCapture(container: container, profile: authority.profile,
                files: files, header: { try authority.header(container) },
                betweenPages: { await Task.yield() }, configure: { _ in })
            guard try authority.header(container) == before, try hasNoReservation(expected, container: container) else {
                throw SharedMediaStorageFailure.stale
            }
            return
        }
        let initial = try read(expected, container: container, authority: authority, files: files)
        try requireParentless(initial.request, container: container)
        // Only this exact reserved source may account for an unrecorded empty
        // partial. The exception grants inspection, never adoption or reads.
        _ = try await SharedMediaNativeScopedAudit.runAppCapture(container: container, profile: authority.profile,
            files: files, cleanupTarget: initial.request.id, header: { try authority.header(container) },
            betweenPages: { await Task.yield() }, configure: { _ in })
        guard try authority.header(container) == before,
              try read(expected, container: container, authority: authority, files: files) == initial else {
            throw SharedMediaStorageFailure.stale
        }
        var saved = initial
        if saved.retirement == nil {
            let facts = try files.discardIdentities(saved)
            let revision = try SharedMediaStoragePolicy.add(before.inventory.revision, 1)
            let intent = try SharedMediaCaptureArtifactRetirement(request: saved.request, stage: saved.stage,
                inventoryRevision: revision, partialIdentity: facts.partial, finalIdentity: facts.final)
            try SharedMediaCaptureRetirementWriter.persist(saved, retirement: intent, container: container, authority: authority, boundary: boundary)
            saved = try read(expected, container: container, authority: authority, files: files)
            guard saved.retirement == intent else { throw SharedMediaStorageFailure.conflict }
        }
        guard let intent = saved.retirement else { throw SharedMediaStorageFailure.conflict }
        if intent.releasedRevision == nil {
            try requireParentless(saved.request, container: container)
            try boundary(.beforeUnlink)
            _ = try authority.header(container)
            guard try read(expected, container: container, authority: authority, files: files) == saved else {
                throw SharedMediaStorageFailure.stale
            }
            try files.unlinkDiscardedSource(saved)
            try boundary(.afterUnlink)
            let header = try authority.header(container)
            let released = try intent.releasing(at: SharedMediaStoragePolicy.add(header.inventory.revision, 1),
                request: saved.request, stage: saved.stage)
            try SharedMediaCaptureRetirementWriter.persist(saved, retirement: released, container: container, authority: authority, boundary: boundary)
        }
        let result = try read(expected, container: container, authority: authority, files: files)
        guard result.retirement?.releasedRevision != nil else { throw SharedMediaStorageFailure.conflict }
        _ = try await SharedMediaNativeScopedAudit.runAppCapture(container: container, profile: authority.profile,
            files: files, header: { try authority.header(container) },
            betweenPages: { await Task.yield() }, configure: { _ in })
    }

    private static func hasNoReservation(_ input: SharedMediaCaptureDraftSourceInput, container: ModelContainer) throws -> Bool {
        let context = ModelContext(container); context.autosaveEnabled = false
        let id = input.id, mediaID = input.mediaID
        var query = FetchDescriptor<SharedMediaOrdinaryArtifactRecord>(predicate: #Predicate { $0.id == id || $0.mediaID == mediaID })
        query.fetchLimit = 2
        if try !context.fetch(query).isEmpty { return false }
        guard try SharedMediaCaptureSubmissionReceipt.matching(scanID: input.scanID,
            generation: input.submissionGeneration, in: context) == nil else { throw SharedMediaStorageFailure.closed }
        try SharedMediaCaptureDraftSourceBinding.requireUnclaimed(scan: input.scanID, context: context)
        return true
    }

    private static func requireParentless(_ request: SharedMediaCaptureArtifactRequest, container: ModelContainer) throws {
        let context = ModelContext(container); context.autosaveEnabled = false
        guard try SharedMediaCaptureSubmissionReceipt.matching(scanID: request.scanID,
            generation: request.submissionGeneration, in: context) == nil else { throw SharedMediaStorageFailure.closed }
        try SharedMediaCaptureDraftSourceBinding.requireUnclaimed(scan: request.scanID, context: context)
    }

    private static func read(_ expected: SharedMediaCaptureDraftSourceInput, container: ModelContainer,
                             authority: SharedMediaNativeAppOperationAuthority, files: SharedMediaCaptureArtifactFiles)
        throws -> SharedMediaCaptureArtifactLedger.Snapshot {
        _ = try authority.header(container); try files.check()
        let context = ModelContext(container); context.autosaveEnabled = false
        let value = try SharedMediaCaptureArtifactLedger.auditRead(id: expected.id, profile: authority.profile,
            rootBindingSHA256: files.rootBindingSHA256, context: context)
        guard try SharedMediaCaptureDraftSourceInput(retained: value.request) == expected, value.remoteStage == nil else {
            throw SharedMediaStorageFailure.conflict
        }
        return value
    }

}
