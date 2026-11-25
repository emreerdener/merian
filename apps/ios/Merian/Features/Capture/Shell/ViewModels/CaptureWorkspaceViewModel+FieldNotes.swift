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

    /// Queue navigation behind the same dismissal barrier used by autosaved notes.
    func navigateFromFieldNotes(_ action: CapturePhotoReviewAction) {
        guard let session = fieldNotesSession, acceptsFieldNotesWrite(session),
              !session.isSubmitting, photoReviewCommit == nil else { return }
        switch action {
        case .selectMedia, .addMore, .historicalDescription: break
        case .identify, .fieldNotes: return
        }
        session.pendingNavigation = action
        closeFieldNotes(sessionID: session.id)
    }

    @discardableResult
    func finishFieldNotesDismissal(sessionID: UUID) -> CapturePhotoReviewAction? {
        guard let session = fieldNotesSession, session.id == sessionID,
              !session.isPresented else { return nil }
        let isCurrent = session.draftGeneration == draftSession.generation
            && session.accountID == dependencies.submission.admission.accountID() && isDraftAccountCurrent
        // Closing persists initial-draft notes. Keep the destination and occupancy
        // until that existing work drains rather than dropping a tap on slow storage.
        if isCurrent, session.pendingNavigation != nil, isInitialDraftWorkActive { return nil }
        fieldNotesSession = nil
        guard isCurrent, !isDraftMutationLocked, stagedCapture.physicalItemCount > 0 else { return nil }
        return session.pendingNavigation
    }

    func resetFieldNotes(session: CaptureFieldNotesSession) {
        guard acceptsFieldNotesWrite(session), !session.isSubmitting else { return }
        session.stopInput()
        session.prompts.resetFunnel()
        session.prompts.activeQuestionIndex = 0
        var context = descriptionDraft
        context.freeText = ""
        _ = autosaveFieldNotes(context, session: session)
    }

    func invalidateFieldNotes(clearProgress: Bool) {
        if clearProgress {
            fieldNotesPromptProgress = nil
            fieldNotesPromptGeneration = nil
        }
        guard let session = fieldNotesSession else { return }
        session.pendingNavigation = nil
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
