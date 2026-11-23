import Foundation
import SwiftData

/// Immutable result/funding custody, including a permanently released cohort.
/// It never authorizes an upload, a media read, or another inference attempt.
@MainActor
enum SharedMediaCaptureCompletedCustody {
    static func read(scanID: UUID, generation: UUID, ownerID: UUID,
                     context: ModelContext) throws -> SharedMediaCaptureSubmissionReceipt.Snapshot {
        guard let saved = try SharedMediaCaptureSubmissionReceipt.auditMatching(scanID: scanID, generation: generation, in: context),
              saved.submission.scanID == scanID, saved.submission.generation == generation,
              saved.submission.profile.ownerID == ownerID else { throw SharedMediaStorageFailure.conflict }
        try SharedMediaCaptureQueueIdentity.require(saved.submission, in: context)
        guard let release = saved.release else {
            _ = try SharedMediaCaptureUploadReadiness.require(saved)
            return saved
        }
        let job = try SharedMediaCaptureCompletionReadback.job(saved.submission, context: context)
        guard job.status == .complete, let raw = job.metadataJSON,
              try OrdinaryInferenceCompletion.retainedInitialIdentity(metadata: raw, scanID: scanID, owner: ownerID)
                == .init(ownerID: ownerID, scanID: scanID, generation: generation) else { throw SharedMediaStorageFailure.closed }
        guard release.proof.completionSHA256 == (try OrdinaryInferenceCompletion.retainedInitialCompletionSHA256(
            metadata: raw, scanID: scanID, owner: ownerID)) else { throw SharedMediaStorageFailure.conflict }
        let funding = try SharedMediaCaptureFundingReceipt.read(raw)
        guard funding.scanID == scanID, funding.delivered,
              release.proof.fundingSHA256 == SharedMediaAcquisitionEncoding.digest(
                try SharedMediaAcquisitionEncoding.encode(funding, maximum: 8192)) else { throw SharedMediaStorageFailure.conflict }
        _ = try funding.settlement(ownerID: ownerID)
        return saved
    }
}
