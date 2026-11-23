import Foundation
import SwiftData

/// Sequential staging of the saved whole observation. Each network result is
/// durably bound before the next role; a retry reads that acknowledgement and
/// never treats a timeout as readiness. The caller owns the account drain and
/// root locks until this operation (including transport cancellation) joins.
@MainActor
enum SharedMediaCaptureUploadWorker {
    static func stage(scanID: UUID, generation: UUID, container: ModelContainer,
                      authority: SharedMediaNativeAppOperationAuthority, files: SharedMediaCaptureArtifactFiles,
                      transport: CaptureStageTransport, availableBytes: () throws -> Int64,
                      validateAttempt: @escaping @MainActor @Sendable () throws -> Void,
                      qualifyRoot: @MainActor () async throws -> Void,
                      boundary: (SharedMediaCaptureReservationBoundary) throws -> Void = { _ in }) async throws -> SharedMediaCaptureSubmissionReceipt.Snapshot {
        try validateAttempt()
        try await qualifyRoot()
        _ = try await SharedMediaCaptureBudget.evaluate(container, authority: authority, files: files)
        let original = try snapshot(scanID: scanID, generation: generation, container: container, authority: authority, files: files)
        let plan = try original.submission.plan()
        for member in original.submission.members {
            try Task.checkCancellation(); try validateAttempt()
            let saved = try snapshot(scanID: scanID, generation: generation, container: container, authority: authority, files: files)
            guard saved.submission == original.submission, saved.state == original.state,
                  let artifact = saved.artifacts.first(where: { $0.request.id == member.artifactID }) else {
                throw SharedMediaStorageFailure.conflict
            }
            if artifact.remoteStage != nil { continue }
            // Read only the exact recorded inode, rehash off-main, and recheck
            // account/header identity after the read before constructing a body.
            let bytes = try await files.readReady(artifact, container: container, authority: authority)
            let wire = try CaptureStageWireRequest(plan: plan, mediaID: member.mediaID, bytes: bytes)
            let header = try authority.header(container)
            let check: @MainActor @Sendable () throws -> Void = {
                try validateAttempt(); try files.check()
                guard try authority.header(container) == header else { throw SharedMediaStorageFailure.stale }
            }
            let prior = try saved.artifacts.first(where: { $0.remoteStage != nil }).map { artifact -> CaptureStageReceipt in
                guard let remote = artifact.remoteStage, let stage = artifact.stage else { throw SharedMediaStorageFailure.conflict }
                return try .init(saved: remote, plan: plan, request: artifact.request, stage: stage)
            }
            let receipt = try await transport.upload(wire, previous: prior, validateAttempt: check, validateResponse: check)
            try Task.checkCancellation(); try check()
            try await qualifyRoot()
            try check()
            guard try snapshot(scanID: scanID, generation: generation, container: container,
                authority: authority, files: files) == saved else { throw SharedMediaStorageFailure.stale }
            _ = try await SharedMediaCaptureRemoteStageWriter.bind(receipt, artifactID: member.artifactID,
                container: container, authority: authority, files: files, availableBytes: availableBytes, boundary: boundary)
        }
        try validateAttempt()
        let complete = try snapshot(scanID: scanID, generation: generation, container: container, authority: authority, files: files)
        guard complete.submission == original.submission, complete.state == original.state else {
            throw SharedMediaStorageFailure.conflict
        }
        _ = try SharedMediaCaptureUploadReadiness.require(complete)
        return complete
    }

    private static func snapshot(scanID: UUID, generation: UUID, container: ModelContainer,
                                 authority: SharedMediaNativeAppOperationAuthority,
                                 files: SharedMediaCaptureArtifactFiles) throws -> SharedMediaCaptureSubmissionReceipt.Snapshot {
        _ = try authority.header(container); try files.check()
        let context = ModelContext(container); context.autosaveEnabled = false
        guard let result = try SharedMediaCaptureSubmissionReceipt.matching(scanID: scanID, generation: generation, in: context),
              case .accepted = result.state, result.submission.profile == authority.profile,
              result.submission.scanID == scanID, result.submission.generation == generation,
              result.submission.rootBindingSHA256 == files.rootBindingSHA256 else { throw SharedMediaStorageFailure.conflict }
        try SharedMediaCaptureQueueIdentity.require(result.submission, in: context)
        guard let raw = try SharedMediaCaptureCompletionReadback.job(result.submission, context: context).metadataJSON,
              try SharedMediaCaptureFundingResolution.funding(raw, submission: result.submission).allowsDispatch else {
            throw SharedMediaStorageFailure.closed
        }
        return result
    }
}
