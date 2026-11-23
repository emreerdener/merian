import Foundation

extension CaptureWorkspaceViewModel {
    func isCurrentMediaReview(_ session: CaptureMediaReviewSession) -> Bool {
        mediaReviewSession?.id == session.id
            && session.draftGeneration == draftSession.generation
            && session.accountID == dependencies.submission.admission.accountID()
            && isDraftAccountCurrent
    }

    /// Ingress resolves collection indexes before entering this stable-ID owner.
    @discardableResult
    func presentMediaReview(nodeID: String) -> Bool {
        guard !areCaptureActionsBlocked, isDraftAccountCurrent,
              !draftSession.hasUnresolvedWork,
              let node = stagedCapture.orderedNodes.first(where: { $0.id == nodeID }) else { return false }
        if case .description = node { return false }
        if let session = mediaReviewSession {
            guard isCurrentMediaReview(session) else { return false }
            session.selectedNodeID = nodeID
        } else {
            guard mediaReviewPresentationID == nil, !isFeaturePresentationAwaitingDismissal, activePresentation == nil,
                  !isRootPresentationDismissing, !isPhotoLibraryPresented else { return false }
            mediaReviewSession = CaptureMediaReviewSession(draftGeneration: draftSession.generation,
                accountID: dependencies.submission.admission.accountID(), selectedNodeID: nodeID)
            mediaReviewPresentationID = mediaReviewSession?.id
            isFeaturePresentationAwaitingDismissal = true
        }
        if case .image(let index, let image) = node {
            editingCropIndex = index
            imageToCrop = image.original
        } else {
            editingCropIndex = nil
            imageToCrop = nil
        }
        revokeAutomaticSubmission()
        return true
    }

    func dismissMediaReview(sessionID: UUID) {
        guard mediaReviewSession?.id == sessionID else { return }
        cancelActiveCropTask()
        photoReviewCommit = nil
        videoReviewCommitID = nil
        invalidateFieldNotes(clearProgress: false)
        imageToCrop = nil
        editingCropIndex = nil
        mediaReviewSession = nil
        // The matching outer onDismiss owns the occupancy release.
    }

    /// Only the dismissed outer cover can release this presentation's lifetime.
    @discardableResult
    func finishMediaReviewDismissal(sessionID: UUID) -> Bool {
        guard mediaReviewPresentationID == sessionID, mediaReviewSession == nil else { return false }
        mediaReviewPresentationID = nil
        if let notes = fieldNotesSession, !notes.isPresented {
            finishFieldNotesDismissal(sessionID: notes.id)
        }
        return true
    }

    func retireMediaReview() {
        if let session = mediaReviewSession { dismissMediaReview(sessionID: session.id) }
    }

    func reconcileMediaReviewSelection() {
        guard let session = mediaReviewSession, !areCaptureActionsBlocked else { return }
        guard isCurrentMediaReview(session) else { retireMediaReview(); return }
        guard !stagedCapture.orderedNodes.contains(where: { $0.id == session.selectedNodeID }) else { return }
        let next = stagedCapture.orderedNodes.first { node in
            if case .description = node { return false }
            return true
        }
        if let next { _ = presentMediaReview(nodeID: next.id) } else { retireMediaReview() }
    }

    func removeReviewedMedia(session: CaptureMediaReviewSession) {
        guard isCurrentMediaReview(session), !areCaptureActionsBlocked,
              let node = stagedCapture.orderedNodes.first(where: { $0.id == session.selectedNodeID }) else { return }
        switch node {
        case .image(let index, let image):
            if initialDraftSession != nil {
                removeInitialDraftItem(image.original.id)
            } else if nativePhotoDraftSession != nil || stagedCapture.nativePhotoDraft != nil {
                removeNativePhoto(imageID: image.original.id)
            } else if activePhotoOriginalPreparation != nil {
                removePhotoPreparationImage(index)
            } else {
                stagedCapture.images.remove(at: index)
                imageToCrop = nil
                editingCropIndex = nil
                clearFieldNotesAfterFinalMediaRemoval()
                resetReviewIfEmpty()
            }
        case .audio(let index, _): removeStagedAudio(at: index)
        case .video(let index, _): removeStagedVideo(at: index)
        case .description: return
        }
        reconcileMediaReviewSelection()
    }
}
