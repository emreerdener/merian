import Foundation

extension CaptureWorkspaceViewModel {
    func submitNativePhotoDraft() async {
        guard canSubmitDraft, isDraftAccountCurrent, baseRefinementContext == nil,
              !dependencies.submission.admission.isLibraryAccessBlocked(),
              dependencies.submission.admission.accountID() == (nativePhotoDraftSession?.identity.ownerID
                ?? dependencies.submission.nativePhotoSubmission?.selection.identity.ownerID),
              !isAutomaticStagedSubmissionPending else {
            offlineToastMessage = .error("This local photo draft needs attention before it can be submitted. Your media and details are retained.")
            return
        }
        let generation = draftSession.generation
        // Claim synchronously before admission yields. The session independently
        // excludes callers and retains durable state after UI cancellation.
        isCheckingScanAdmission = true
        defer { isCheckingScanAdmission = false }
        var resolvedSession = nativePhotoDraftSession?.prepared?.submission ?? dependencies.submission.nativePhotoSubmission
        if let draft = nativePhotoDraftSession,
           resolvedSession.map({ (try? CaptureNativePhotoSubmissionSnapshot(stagedCapture, selection: $0.selection)) == nil }) ?? true {
            guard let pending = try? CaptureNativePhotoSubmissionSnapshot(stagedCapture) else { return }
            do {
                let prepared = try await draft.prepare(stagedCapture)
                guard !Task.isCancelled, draftSession.generation == generation, isDraftAccountCurrent,
                      baseRefinementContext == nil, !dependencies.submission.admission.isLibraryAccessBlocked(),
                      dependencies.submission.admission.accountID() == draft.identity.ownerID,
                      (try? CaptureNativePhotoSubmissionSnapshot(stagedCapture)) == pending else { return }
                stagedCapture = prepared.capture
                resolvedSession = prepared.submission
            } catch {
                guard !Task.isCancelled, draftSession.generation == generation, isDraftAccountCurrent,
                      dependencies.submission.admission.accountID() == draft.identity.ownerID else { return }
                offlineToastMessage = .error("Photo preparation needs attention. Your originals and submitted details are retained; preparation will not be repeated automatically.")
                return
            }
        }
        guard let session = resolvedSession else {
            offlineToastMessage = .error("This local photo draft needs recovery. Your original media and details are retained.")
            return
        }
        guard let snapshot = try? CaptureNativePhotoSubmissionSnapshot(stagedCapture, selection: session.selection) else {
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
                  try CaptureNativePhotoSubmissionSnapshot(stagedCapture, selection: session.selection) == snapshot else { return }
            offlineToastMessage = .information("Saved locally. Identification has not been requested.")
        } catch {
            guard !Task.isCancelled, draftSession.generation == generation, isDraftAccountCurrent,
                  baseRefinementContext == nil,
                  dependencies.submission.admission.accountID() == session.selection.identity.ownerID,
                  (try? CaptureNativePhotoSubmissionSnapshot(stagedCapture, selection: session.selection)) == snapshot else { return }
            offlineToastMessage = .error("The local submission needs recovery. Your original media and details are retained; try again explicitly when ready.")
        }
    }
}
