import Foundation
import SwiftData

/// One local handoff for the complete frozen observation. The caller retains
/// draft sources until this operation joins; accepted replay never rereads a
/// draft source or reconstructs membership from mutable presentation state.
@MainActor
enum SharedMediaCaptureDraftAcceptance {
    typealias ReadArtifact = @MainActor @Sendable (SharedMediaCaptureArtifactInput) async throws -> Data

    static func accept(plan: CaptureInitialEvidencePlan, context: SharedMediaCaptureSubmissionContext,
                       expectedJournal: SharedMediaCaptureDraftJournalReceipt.Snapshot? = nil,
                       container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                       files: SharedMediaCaptureArtifactFiles, availableBytes: () throws -> Int64,
                       readArtifact: ReadArtifact,
                       reservationBoundary: (SharedMediaCaptureReservationBoundary) throws -> Void = { _ in },
                       artifactBoundary: (SharedMediaCaptureArtifactWriteBoundary) throws -> Void = { _ in }) async throws -> SharedMediaCaptureSubmissionAcceptance {
        try Task.checkCancellation()
        let preparedJournal: SharedMediaCaptureDraftJournalReceipt.Snapshot?
        if let expectedJournal {
            preparedJournal = try await SharedMediaCapturePreparation.retain(plan: plan, expected: expectedJournal,
                container: container, authority: authority, files: files, availableBytes: availableBytes,
                readArtifact: readArtifact, artifactBoundary: artifactBoundary)
        } else { preparedJournal = nil }
        let saved = try await SharedMediaCaptureSubmissionWriter.reserve(plan: plan, context: context,
            expectedJournal: preparedJournal,
            container: container, authority: authority, files: files, availableBytes: availableBytes,
            boundary: reservationBoundary)
        if case .accepted = saved.state {
            return try await SharedMediaCaptureAcceptance.accept(scanID: plan.scanID, generation: plan.generation,
                container: container, authority: authority, files: files, availableBytes: availableBytes)
        }
        for member in saved.submission.members {
            try Task.checkCancellation()
            _ = try authority.header(container); try files.check()
            let input = try saved.submission.artifact(mediaID: member.mediaID)
            // The reservation performs a complete physical audit before this
            // point. Ready members are immutable, including after a lost reply.
            if saved.artifacts.contains(where: { $0.request.id == input.id && $0.phase == .ready }) { continue }
            let before = try authority.header(container)
            let bytes = try await readArtifact(input)
            try Task.checkCancellation(); try files.check()
            guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
            _ = try await SharedMediaCaptureArtifactWriter.materialize(input, bytes: bytes, container: container,
                authority: authority, files: files, availableBytes: availableBytes, boundary: artifactBoundary)
        }
        try Task.checkCancellation()
        return try await SharedMediaCaptureAcceptance.accept(scanID: plan.scanID, generation: plan.generation,
            container: container, authority: authority, files: files, availableBytes: availableBytes,
            boundary: reservationBoundary)
    }
}
