import Foundation

/// Funding admission is separate from queue acceptance. Only the native
/// whole-observation writer inserts the queue, jobs and acceptance receipt.
@MainActor
struct CaptureInitialSubmissionAccess {
    typealias ContextFactory = (CaptureInitialEvidencePlan, ScanFundingReservation) throws -> SharedMediaCaptureSubmissionContext
    let begin: (CaptureInitialEvidencePlan, SharedMediaCaptureSubmissionContext?, ContextFactory) throws -> SharedMediaCaptureSubmissionContext
    let end: (UUID) -> Void
    let acceptanceAttemptFinished: () -> Void
    var prepare: (SharedMediaNativeOriginalOwner) async throws -> Void = { _ in }

    static func live(queue: OfflineQueueManager) -> Self {
        .init(begin: { plan, retained, makeContext in
            try queue.beginNativeCaptureAdmission(plan: plan, retained: retained, makeContext: makeContext)
        }, end: { scanID in
            queue.endNativeCaptureAdmission(scanID: scanID)
        }, acceptanceAttemptFinished: {
            // A lost acknowledgement may still have committed. This is only
            // a wake hint, including on cancellation/account change; the
            // worker requalifies the current account and durable accepted job.
            queue.captureExecutionRecovery?()
        }, prepare: { owner in
            queue.restoreFundingReservationsForCurrentAccount()
            try await owner.restoreCaptureAdmissionFunding()
        })
    }
}
