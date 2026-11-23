import UIKit

extension CaptureWorkspaceViewModel {
    func canSelectPhotoSubject(_ image: StagedImage) -> Bool {
        guard isDraftAccountCurrent, !isDraftMutationLocked, image.reviewBasis != .unproven else { return false }
        if initialDraftSession != nil { return !isInitialDraftWorkActive && image.original.allowsReframing }
        return reanalysisEditor?.supportsManualSelection == true
    }
    func beginPhotoReviewCommit(
        imageID: UUID, action: CapturePhotoReviewAction? = nil, notesSessionID: UUID? = nil
    ) -> CapturePhotoReviewCommit? {
        let submittingNotes = fieldNotesSession.map {
            $0.id == notesSessionID && $0.isSubmitting && acceptsFieldNotesWrite($0)
        } ?? false
        guard !isDraftMutationLocked, photoReviewCommit == nil,
              !isFieldNotesOccupied || submittingNotes, !draftSession.hasUnresolvedWork,
              isDraftAccountCurrent, imageToCrop?.id == imageID,
              stagedCapture.images.contains(where: { $0.original.id == imageID }) else { return nil }
        let requested = action ?? .identify
        if submittingNotes, requested != .identify { return nil }
        let commit = CapturePhotoReviewCommit(imageID: imageID, generation: draftSession.generation,
            accountID: dependencies.submission.admission.accountID(), action: requested)
        completedPhotoReviewCommitID = nil
        photoReviewCommit = commit
        return commit
    }

    func isCurrentPhotoReviewCommit(_ commit: CapturePhotoReviewCommit) -> Bool {
        photoReviewCommit == commit && draftSession.generation == commit.generation
            && dependencies.submission.admission.accountID() == commit.accountID && isDraftAccountCurrent
            && imageToCrop?.id == commit.imageID
            && stagedCapture.images.contains { $0.original.id == commit.imageID }
    }

    /// Commit the displayed edit before acting on the whole observation. A later
    /// admission failure preserves committed edits and the staged draft for retry.
    @discardableResult
    func finishPhotoReviewCommit(_ commit: CapturePhotoReviewCommit, succeeded: Bool) -> Bool {
        guard isCurrentPhotoReviewCommit(commit) else {
            if photoReviewCommit == commit { photoReviewCommit = nil }
            return false
        }
        photoReviewCommit = nil
        guard succeeded else { return false }
        completedPhotoReviewCommitID = commit.id
        switch commit.action {
        case .selectMedia(let nodeID):
            _ = presentMediaReview(nodeID: nodeID)
            return false
        case .addMore:
            retireMediaReview()
            return false
        case .fieldNotes:
            if let session = mediaReviewSession { _ = openFieldNotes(inReview: session) }
            return false
        case .historicalDescription(let id):
            mediaReviewSession?.historicalDescriptionID = id
            return false
        case .identify:
            editingCropIndex = nil
            imageToCrop = nil
            return true
        }
    }

    /// Unchanged review preserves existing prepared bytes and native recipes.
    /// Imported originals already have their default square recipe.
    func canPreservePhotoReviewArtifacts(imageID: UUID) -> Bool {
        guard let image = stagedCapture.images.first(where: { $0.original.id == imageID }) else { return false }
        if let session = nativePhotoDraftSession, let reference = image.photoOriginalReference {
            return session.items.contains { !$0.removed && $0.reference == reference && $0.recipe != nil }
        }
        return !image.compressedData.isEmpty && !image.displayData.isEmpty
    }

    /// Capture-only async commit barrier; the avatar cropper keeps its own contract.
    func commitPhotoReview(
        _ commit: CapturePhotoReviewCommit,
        croppedData: Data, scale: CGFloat, offset: CGSize, displaySize: CGFloat, quarterTurns: Int,
        sourceSelection: NormalizedImageFocusRegion? = nil, preservesPixels: Bool = false
    ) async -> Bool {
        guard isCurrentPhotoReviewCommit(commit), !croppedData.isEmpty else {
            return finishPhotoReviewCommit(commit, succeeded: false)
        }
        if initialDraftSession != nil {
            return await commitInitialPhotoReview(commit, scale: scale, offset: offset,
                displaySize: displaySize, quarterTurns: quarterTurns, sourceSelection: sourceSelection,
                preservesPixels: preservesPixels)
        }
        if stagedCapture.nativePhotoDraft != nil || nativePhotoDraftSession != nil {
            let succeeded = confirmNativePhotoCrop(imageID: commit.imageID, thumbnailData: croppedData,
                scale: scale, offset: offset, displaySize: displaySize, quarterTurns: quarterTurns,
                completesReview: false, sourceSelection: sourceSelection)
            return finishPhotoReviewCommit(commit, succeeded: succeeded)
        }
        guard let existing = stagedCapture.images.first(where: { $0.original.id == commit.imageID }) else {
            return finishPhotoReviewCommit(commit, succeeded: false)
        }
        guard !preservesPixels || croppedData == existing.compressedData else {
            return finishPhotoReviewCommit(commit, succeeded: false)
        }
        let focusRegion: NormalizedImageFocusRegion?
        if let sourceSelection {
            guard sourceSelection.source == .userSelection, sourceSelection.isValidEvidence else {
                return finishPhotoReviewCommit(commit, succeeded: false)
            }
            if preservesPixels, existing.hasPreparedReviewIdentity {
                focusRegion = sourceSelection
            } else {
                guard let mapping = ImageCropProcessor.cropMapping(image: existing.original.image,
                    displaySize: displaySize, scale: scale, offset: offset, quarterTurns: quarterTurns),
                  let selectedFocus = mapping.focus(fromSourceSelection: sourceSelection.rect) else {
                    return finishPhotoReviewCommit(commit, succeeded: false)
                }
                focusRegion = selectedFocus
            }
        } else { focusRegion = await ImageFocusRegionDetector.detect(in: croppedData) }
        let displayData = preservesPixels ? existing.displayData : await ImageCropProcessor.generateCrop(
            image: existing.original.image, displaySize: displaySize, scale: scale,
            currentScale: 1, offset: offset, currentOffset: .zero, quarterTurns: quarterTurns,
            maxPixelSize: Int(ImagePreparationPolicy.displayMaxDimension)
        )
        guard !Task.isCancelled, isCurrentPhotoReviewCommit(commit),
              !displayData.isEmpty,
              let index = stagedCapture.images.firstIndex(where: { $0.original.id == commit.imageID }) else {
            return finishPhotoReviewCommit(commit, succeeded: false)
        }
        var original = existing.original
        original.lastCropScale = scale
        original.lastCropOffset = offset
        original.lastCropQuarterTurns = quarterTurns
        original.lastCropDisplaySize = preservesPixels && existing.hasPreparedReviewIdentity ? nil : displaySize
        original.manualSourceSelection = sourceSelection
        let thumbnail = ImageDownsampler.downsampledUIImage(data: croppedData, maxSize: 512) ?? existing.uiImage
        stagedCapture.images[index] = existing.replacing(compressedData: croppedData, displayData: displayData,
            uiImage: thumbnail, original: original).replacingFocusRegion(focusRegion)
        let persisted = await persistPhotoPreparationDraft()
        guard !Task.isCancelled, isCurrentPhotoReviewCommit(commit), persisted else {
            return finishPhotoReviewCommit(commit, succeeded: false)
        }
        return finishPhotoReviewCommit(commit, succeeded: true)
    }
}
