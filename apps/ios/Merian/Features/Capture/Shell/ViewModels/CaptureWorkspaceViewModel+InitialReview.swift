import Foundation

extension CaptureWorkspaceViewModel {
    func commitInitialPhotoReview(_ commit: CapturePhotoReviewCommit, scale: CGFloat, offset: CGSize,
                                  displaySize: CGFloat, quarterTurns: Int,
                                  sourceSelection: NormalizedImageFocusRegion?, preservesPixels: Bool) async -> Bool {
        guard let session = initialDraftSession, isCurrentPhotoReviewCommit(commit) else { return false }
        do {
            try await diContainer.nativeMediaLifecycle.runCaptureDraftWork(ownerID: session.identity.ownerID) { [self] in
                try requireInitialDraft(session, generation: commit.generation)
                try await persistInitialDraftNotes(session)
                guard let journal = session.journal,
                      let index = journal.value.items.firstIndex(where: { $0.id == commit.imageID }),
                      case let .photo(id, source, previous) = journal.value.items[index] else {
                    throw SharedMediaStorageFailure.conflict
                }
                let recipe: SharedMediaNativePreparationRecipe
                if preservesPixels, previous.format == .cameraStill, sourceSelection == nil {
                    recipe = previous
                } else if preservesPixels, previous.format != .cameraStill {
                    recipe = .init(format: sourceSelection == nil ? .stillImage : .selectedStillImage,
                        isPro: previous.isPro, cropDisplaySize: previous.cropDisplaySize,
                        quarterTurns: previous.quarterTurns, scale: previous.scale,
                        offsetX: previous.offsetX, offsetY: previous.offsetY, sourceSelection: sourceSelection)
                } else {
                    recipe = .init(format: sourceSelection == nil ? .stillImage : .selectedStillImage,
                        isPro: previous.isPro, cropDisplaySize: Double(displaySize), quarterTurns: quarterTurns,
                        scale: Double(scale), offsetX: Double(offset.width), offsetY: Double(offset.height),
                        sourceSelection: sourceSelection)
                }
                var items = journal.value.items
                items[index] = .photo(id: id, source: source, recipe: recipe)
                try await session.updateReview(items: items)
            }
            try await refreshInitialDraftPresentation(session, generation: commit.generation)
            guard isCurrentPhotoReviewCommit(commit) else { return false }
            return finishPhotoReviewCommit(commit, succeeded: true)
        } catch { return finishPhotoReviewCommit(commit, succeeded: false) }
    }

    func commitInitialVideoReview(_ editor: CaptureVideoEditorState, review: CaptureMediaReviewSession,
                                  notesSessionID: UUID?) async -> Bool {
        let submittingNotes = fieldNotesSession.map {
            $0.id == notesSessionID && $0.isSubmitting && acceptsFieldNotesWrite($0)
        } ?? false
        guard let session = initialDraftSession, !isDraftMutationLocked, videoReviewCommitID == nil,
              !isFieldNotesOccupied || submittingNotes, isCurrentMediaReview(review),
              review.selectedNodeID == "video_\(editor.videoID)" else { return false }
        let token = UUID(), generation = draftSession.generation
        videoReviewCommitID = token
        defer { if videoReviewCommitID == token { videoReviewCommitID = nil } }
        do {
            try await diContainer.nativeMediaLifecycle.runCaptureDraftWork(ownerID: session.identity.ownerID) { [self] in
                try requireInitialDraft(session, generation: generation)
                try await persistInitialDraftNotes(session)
                guard let journal = session.journal,
                      let index = journal.value.items.firstIndex(where: { $0.id == editor.videoID }),
                      case let .video(id, source, companion, prior) = journal.value.items[index] else {
                    throw SharedMediaStorageFailure.conflict
                }
                let framing = editor.framing
                let recipe = SharedMediaCaptureDraftJournal.VideoRecipe(duration: prior.duration, isPro: prior.isPro,
                    composingCenter: prior.composingCenter, scale: Double(framing.scale),
                    offsetX: Double(framing.offset.width), offsetY: Double(framing.offset.height),
                    displaySize: Double(framing.displaySize), quarterTurns: framing.quarterTurns)
                var items = journal.value.items
                items[index] = .video(id: id, source: source, companion: companion, recipe: recipe)
                try await session.updateReview(items: items)
            }
            // Re-project verified originals, never read the old preview as a
            // preparation source. Its existing readers retire before replacing it.
            try await refreshInitialDraftPresentation(session, generation: generation)
            return videoReviewCommitID == token && isCurrentMediaReview(review)
        } catch { return false }
    }
}
