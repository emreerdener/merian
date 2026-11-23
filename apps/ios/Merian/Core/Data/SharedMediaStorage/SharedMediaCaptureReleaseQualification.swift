import Foundation
import SwiftData

/// A fresh, synchronous join of completed Capture and acknowledged History.
/// This descriptive proof alone grants neither file access nor deletion. The
/// registered owner must persist a separate release intent before unlinking.
@MainActor
enum SharedMediaCaptureReleaseQualification {
    struct Proof: Codable, Equatable, Sendable {
        let version: Int
        let submissionSHA256: String
        let acceptanceSHA256: String
        let history: NativeHistoryAssociation
        let completionSHA256: String
        let fundingSHA256: String
        fileprivate init(version: Int, submissionSHA256: String, acceptanceSHA256: String,
                         history: NativeHistoryAssociation, completionSHA256: String, fundingSHA256: String) {
            self.version = version; self.submissionSHA256 = submissionSHA256; self.acceptanceSHA256 = acceptanceSHA256
            self.history = history; self.completionSHA256 = completionSHA256; self.fundingSHA256 = fundingSHA256
        }
    }

    /// Caller owns the shared persistence transaction; do not nest the History
    /// public wrapper, which acquires the same nonrecursive lock.
    static func read(_ saved: SharedMediaCaptureSubmissionReceipt.Snapshot,
                     context: ModelContext) throws -> Proof {
        guard !context.hasChanges, !context.container.mainContext.hasChanges,
              case let .accepted(acceptance) = saved.state else { throw SharedMediaStorageFailure.closed }
        let submission = saved.submission, owner = submission.profile.ownerID
        guard saved.release == nil,
              try SharedMediaCaptureSubmissionReceipt.matching(scanID: submission.scanID,
                generation: submission.generation, in: context) == saved else { throw SharedMediaStorageFailure.stale }
        try SharedMediaCaptureQueueIdentity.require(submission, in: context)
        _ = try SharedMediaCaptureUploadReadiness.require(saved)
        let job = try SharedMediaCaptureCompletionReadback.job(submission, context: context)
        guard job.status == .complete, let metadata = job.metadataJSON,
              try OrdinaryInferenceCompletion.retainedInitialIdentity(metadata: metadata, scanID: submission.scanID, owner: owner)
                == .init(ownerID: owner, scanID: submission.scanID, generation: submission.generation) else {
            throw SharedMediaStorageFailure.closed
        }
        let funding = try SharedMediaCaptureFundingReceipt.read(metadata)
        guard funding.scanID == submission.scanID, funding.delivered else { throw SharedMediaStorageFailure.closed }
        _ = try funding.settlement(ownerID: owner)
        guard let baseline = try ObservationHistoryEnrollmentService.acknowledgedInitialBaseline(
            observation: submission.scanID, owner: owner, context: context),
              try OrdinaryInferenceCompletion.matchesRetainedInitialResult(baseline.result, metadata: metadata,
                scanID: submission.scanID, owner: owner) else { throw SharedMediaStorageFailure.closed }
        let result = try Proof(version: 1,
            submissionSHA256: SharedMediaAcquisitionEncoding.digest(submission.encoded()),
            acceptanceSHA256: SharedMediaAcquisitionEncoding.digest(acceptance.encoded(submission: submission, artifacts: saved.artifacts)),
            history: .init(baseline.association),
            completionSHA256: OrdinaryInferenceCompletion.retainedInitialCompletionSHA256(metadata: metadata,
                scanID: submission.scanID, owner: owner),
            fundingSHA256: SharedMediaAcquisitionEncoding.digest(SharedMediaAcquisitionEncoding.encode(funding, maximum: 8192)))
        guard !context.hasChanges else { throw SharedMediaStorageFailure.stale }
        return result
    }
}
