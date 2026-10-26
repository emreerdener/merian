import Foundation

extension CaptureWorkspaceViewModel {
    func submitNativePhotoDraft() async {
        guard let session = dependencies.submission.nativePhotoSubmission,
              canSubmitDraft, isDraftAccountCurrent, baseRefinementContext == nil,
              !dependencies.submission.admission.isLibraryAccessBlocked(),
              dependencies.submission.admission.accountID() == session.selection.identity.ownerID,
              !isAutomaticStagedSubmissionPending else {
            offlineToastMessage = .error("This local photo draft needs attention before it can be submitted. Your media and details are retained.")
            return
        }
        let generation = draftSession.generation
        // Claim synchronously before admission yields. The session independently
        // excludes callers and retains durable state after UI cancellation.
        isCheckingScanAdmission = true
        defer { isCheckingScanAdmission = false }
        guard let snapshot = try? CaptureNativePhotoSubmissionSnapshot(stagedCapture) else {
            offlineToastMessage = .error("The prepared photos no longer match this draft. Your media and details are retained.")
            return
        }
        do {
            let attempt = try await session.submit(snapshot)
            guard !Task.isCancelled, session.attemptID == attempt,
                  draftSession.generation == generation, isDraftReadyForSubmission,
                  isDraftAccountCurrent, baseRefinementContext == nil,
                  !dependencies.submission.admission.isLibraryAccessBlocked(),
                  dependencies.submission.admission.accountID() == session.selection.identity.ownerID,
                  try CaptureNativePhotoSubmissionSnapshot(stagedCapture) == snapshot else { return }
            offlineToastMessage = .information("Saved locally. Identification has not been requested.")
        } catch {
            guard !Task.isCancelled, draftSession.generation == generation, isDraftAccountCurrent,
                  baseRefinementContext == nil,
                  dependencies.submission.admission.accountID() == session.selection.identity.ownerID,
                  (try? CaptureNativePhotoSubmissionSnapshot(stagedCapture)) == snapshot else { return }
            offlineToastMessage = .error("The local submission needs recovery. Your original media and details are retained; try again explicitly when ready.")
        }
    }
}
