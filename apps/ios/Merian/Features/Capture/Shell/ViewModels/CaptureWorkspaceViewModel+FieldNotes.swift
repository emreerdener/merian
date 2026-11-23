import Foundation

extension CaptureWorkspaceViewModel {
    var isFieldNotesOccupied: Bool { fieldNotesSession != nil }

    /// Competing actions use this guard. Autosaves retain the original mutation
    /// guard so the presentation cannot lock out its own editor.
    var areCaptureActionsBlocked: Bool {
        isDraftMutationLocked || isFieldNotesOccupied || photoReviewCommit != nil
    }

    var canOpenFieldNotes: Bool {
        fieldNotesSession == nil && !isDraftMutationLocked && photoReviewCommit == nil
            && activePresentation == nil && !isRootPresentationDismissing && !isPhotoLibraryPresented
            && imageToCrop == nil
            && mediaReviewSession == nil
            && !isFeaturePresentationAwaitingDismissal
            && !draftSession.hasUnresolvedWork && !isCapturing && !isVideoRecording
            && !isPreparingVideo && !isStagingRefinement && stagedCapture.physicalItemCount > 0
    }

    func requestFieldNotesWhenReady() {
        pendingFieldNotesIntent = .init(draftGeneration: draftSession.generation,
                                       accountID: dependencies.submission.admission.accountID())
        resumePendingFieldNotesIfPossible()
    }

    func resumePendingFieldNotesIfPossible() {
        guard let intent = pendingFieldNotesIntent else { return }
        guard intent.draftGeneration == draftSession.generation,
              intent.accountID == dependencies.submission.admission.accountID() else {
            pendingFieldNotesIntent = nil
            return
        }
        guard canOpenFieldNotes else { return }
        pendingFieldNotesIntent = nil
        _ = openFieldNotes()
    }

    @discardableResult
    func openFieldNotes() -> Bool {
        guard canOpenFieldNotes,
              bindDraftToCurrentAccount() else { return false }
        return createFieldNotesSession()
    }

    @discardableResult
    func openFieldNotes(inReview review: CaptureMediaReviewSession) -> Bool {
        guard isCurrentMediaReview(review), fieldNotesSession == nil,
              !isDraftMutationLocked, photoReviewCommit == nil,
              !draftSession.hasUnresolvedWork, !isCapturing, !isVideoRecording,
              !isPreparingVideo, stagedCapture.physicalItemCount > 0,
              bindDraftToCurrentAccount() else { return false }
        return createFieldNotesSession()
    }

    private func createFieldNotesSession() -> Bool {
        revokeAutomaticSubmission()
        fieldNotesSession = CaptureFieldNotesSession(
            draftGeneration: draftSession.generation,
            accountID: dependencies.submission.admission.accountID(),
            flow: describePromptFlow,
            progress: fieldNotesPromptGeneration == draftSession.generation ? fieldNotesPromptProgress : nil,
            inputDependencies: .live(speechManager: diContainer.speechManager)
        )
        return true
    }

    func acceptsFieldNotesWrite(_ session: CaptureFieldNotesSession) -> Bool {
        fieldNotesSession?.id == session.id && session.isPresented
            && session.draftGeneration == draftSession.generation
            && session.accountID == dependencies.submission.admission.accountID()
            && isDraftAccountCurrent && !isDraftMutationLocked
            && stagedCapture.physicalItemCount > 0
    }

    @discardableResult
    func autosaveFieldNotes(_ context: ObservationContext, session: CaptureFieldNotesSession) -> Bool {
        guard acceptsFieldNotesWrite(session) else { return false }
        updateDescriptionDraft(context)
        fieldNotesPromptProgress = session.prompts.progress
        fieldNotesPromptGeneration = session.draftGeneration
        return true
    }

    func saveFieldNotesProgress(session: CaptureFieldNotesSession) {
        guard acceptsFieldNotesWrite(session) else { return }
        fieldNotesPromptProgress = session.prompts.progress
        fieldNotesPromptGeneration = session.draftGeneration
    }

    func closeFieldNotes(sessionID: UUID) {
        guard let session = fieldNotesSession, session.id == sessionID else { return }
        saveFieldNotesProgress(session: session)
        session.isPresented = false
        session.stopInput()
        persistInitialDraftNotesWhenIdle()
    }

    func finishFieldNotesDismissal(sessionID: UUID) {
        guard fieldNotesSession?.id == sessionID,
              fieldNotesSession?.isPresented == false else { return }
        fieldNotesSession = nil
    }

    func invalidateFieldNotes(clearProgress: Bool) {
        if clearProgress {
            fieldNotesPromptProgress = nil
            fieldNotesPromptGeneration = nil
        }
        guard let session = fieldNotesSession else { return }
        session.isPresented = false
        session.stopInput()
    }

    func clearFieldNotesAfterFinalMediaRemoval() {
        guard stagedCapture.physicalItemCount == 0 else { return }
        pendingFieldNotesIntent = nil
        invalidateFieldNotes(clearProgress: true)
        descriptionDraft = ObservationContext()
        if isReanalyzing {
            stagedCapture.observationContexts.removeAll { $0.isRefinementSupplement }
        } else {
            stagedCapture.observationContexts.removeAll()
        }
        resetReviewIfEmpty()
    }
}
