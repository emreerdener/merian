import PhotosUI
import UIKit

/// Retained in picker order before any acquisition; a failed item is never
/// replaced by another selection or loaded again to guess its durable outcome.
struct CaptureNativePhotoPickerInput {
    let id = UUID()
    let localIdentifier: String?
    let load: @Sendable () async throws -> Data
}

extension CaptureWorkspaceViewModel {
    var usesNativePhotoComposition: Bool {
        dependencies.submission.nativePhotoDraftFactory != nil
            || dependencies.submission.nativePhotoSubmission != nil
            || nativePhotoDraftSession != nil || stagedCapture.nativePhotoDraft != nil
    }

    func importNativePhotoItems(_ inputs: [CaptureNativePhotoPickerInput]) {
        guard !inputs.isEmpty, !isDraftMutationLocked, !draftSession.hasUnresolvedWork,
              baseRefinementContext == nil, dependencies.photoOriginalPreparation == nil,
              dependencies.submission.nativePhotoSubmission == nil,
              stagedCapture.audios.isEmpty, stagedCapture.videos.isEmpty,
              !dependencies.submission.admission.isLibraryAccessBlocked(),
              let account = dependencies.submission.admission.accountID(),
              let factory = dependencies.submission.nativePhotoDraftFactory,
              nativePhotoDraftSession != nil || (stagedCapture.images.isEmpty && stagedCapture.nativePhotoDraft == nil),
              inputs.count + (nativePhotoDraftSession?.items.count ?? 0) <= 2,
              let operation = beginDraftOperation(nativePhoto: true) else {
            offlineToastMessage = .error("These photos couldn’t be added to this local draft. Your current media and details are retained.")
            return
        }
        let session = nativePhotoDraftSession ?? factory(account)
        guard session.identity.ownerID == account,
              stagedCapture.nativePhotoDraft == nil || stagedCapture.nativePhotoDraft == session.identity,
              session.canEdit else {
            completeDraftOperation(operation, succeeded: false)
            return
        }
        nativePhotoDraftSession = session
        stagedCapture.nativePhotoDraft = session.identity // before any side effect
        nativePhotoPickerInputs.append(contentsOf: inputs)
        revokeAutomaticSubmission()
        nativePhotoImportTask = Task { @MainActor in
            var succeeded = false
            defer {
                nativePhotoImportTask = nil
                completeDraftOperation(operation, succeeded: succeeded)
                if succeeded { presentNextRequiredGalleryCrop() }
            }
            do {
                for input in inputs {
                    try Task.checkCancellation()
                    guard draftSession.contains(operation), isDraftAccountCurrent,
                          dependencies.submission.admission.accountID() == account,
                          !dependencies.submission.admission.isLibraryAccessBlocked() else { throw SharedMediaStorageFailure.stale }
                    let context = await historicalContextSnapshot(for: input.localIdentifier)
                    try Task.checkCancellation()
                    guard draftSession.contains(operation), isDraftAccountCurrent,
                          dependencies.submission.admission.accountID() == account else { throw SharedMediaStorageFailure.stale }
                    let (reference, preview) = try await session.acquire(itemID: input.id, load: input.load)
                    guard !Task.isCancelled, draftSession.contains(operation), isDraftAccountCurrent,
                          dependencies.submission.admission.accountID() == account,
                          !dependencies.submission.admission.isLibraryAccessBlocked() else { throw SharedMediaStorageFailure.stale }
                    let original = IdentifiableImage(image: preview, environmentContext: context?.makeEnvironmentContext(), isFromGallery: true)
                    // Empty evidence is provisional, protected by the independent
                    // native marker. Only owner readback may populate these bytes.
                    stagedCapture.images.append(.init(compressedData: Data(), displayData: Data(),
                        uiImage: preview, original: original, photoOriginalReference: reference))
                    operationState.appendRequiredGalleryCrop(imageID: original.id)
                }
                selectedPhotoItems.removeAll()
                succeeded = true
            } catch {
                if session.hasNoNativeAcquisition {
                    nativePhotoDraftSession = nil
                    stagedCapture.nativePhotoDraft = nil
                    nativePhotoPickerInputs.removeAll()
                } else { session.holdForAttention() }
                guard draftSession.contains(operation), isDraftAccountCurrent,
                      dependencies.submission.admission.accountID() == account else { return }
                offlineToastMessage = .error(session.hasNoNativeAcquisition
                    ? "Photos couldn’t be imported. Your current details are retained."
                    : "Photo import needs recovery. Your local draft and selected items are retained.")
            }
        }
    }

    func confirmNativePhotoCrop(imageID: UUID, thumbnailData: Data, scale: CGFloat, offset: CGSize,
                                displaySize: CGFloat, quarterTurns: Int) {
        guard !isDraftMutationLocked, isDraftAccountCurrent, let session = nativePhotoDraftSession,
              dependencies.submission.admission.accountID() == session.identity.ownerID,
              !dependencies.submission.admission.isLibraryAccessBlocked(),
              let index = stagedCapture.images.firstIndex(where: { $0.original.id == imageID }),
              let reference = stagedCapture.images[index].photoOriginalReference else { return }
        do {
            let recipe = SharedMediaNativePreparationRecipe(format: .stillImage, isPro: dependencies.scan.canStartProScan(),
                cropDisplaySize: Double(displaySize), quarterTurns: quarterTurns, scale: Double(scale),
                offsetX: Double(offset.width), offsetY: Double(offset.height))
            try session.setRecipe(recipe, for: reference)
            let existing = stagedCapture.images[index]
            var original = existing.original
            original.initialCameraVerticalCenter = nil // only explicit confirmation replaces shutter framing
            original.lastCropScale = scale; original.lastCropOffset = offset; original.lastCropQuarterTurns = quarterTurns
            let thumbnail = ImageDownsampler.downsampledUIImage(data: thumbnailData, maxSize: 512) ?? existing.uiImage
            stagedCapture.images[index] = existing.replacing(uiImage: thumbnail, original: original)
            editingCropIndex = nil; imageToCrop = nil
            if isRequiredGalleryCrop(imageID) { _ = completeRequiredGalleryCrop(for: imageID) }
        } catch {
            offlineToastMessage = .error("The crop couldn’t be confirmed. Your original photo is retained.")
        }
    }

    func removeNativePhoto(imageID: UUID) {
        guard !isDraftMutationLocked, !draftSession.hasUnresolvedWork, isDraftAccountCurrent,
              let session = nativePhotoDraftSession,
              dependencies.submission.admission.accountID() == session.identity.ownerID,
              !dependencies.submission.admission.isLibraryAccessBlocked(),
              let image = stagedCapture.images.first(where: { $0.original.id == imageID }),
              let reference = image.photoOriginalReference else { return }
        let generation = draftSession.generation
        nativePhotoDispositionTask = Task { @MainActor in
            defer { nativePhotoDispositionTask = nil }
            do {
                try await session.remove(reference)
                guard draftSession.generation == generation, isDraftAccountCurrent,
                      dependencies.submission.admission.accountID() == session.identity.ownerID else { return }
                stagedCapture.images.removeAll { $0.original.id == imageID }
                operationState.removeRequiredGalleryCrop(imageID: imageID)
                editingCropIndex = nil; imageToCrop = nil
                resetReviewIfEmpty()
                // Leave the next crop to presentation after releasing the lock.
            } catch {
                guard draftSession.generation == generation, isDraftAccountCurrent else { return }
                offlineToastMessage = .error("Photo removal needs recovery. Your local draft remains retained.")
            }
            nativePhotoDispositionTask = nil
            presentNextRequiredGalleryCrop()
        }
    }

    func discardNativePhotoDraft() {
        guard nativePhotoImportTask == nil, nativePhotoDispositionTask == nil,
              !isCheckingScanAdmission, !isQueueingStagedCapture, !draftSession.hasUnresolvedWork,
              isDraftAccountCurrent, let session = nativePhotoDraftSession, session.canDiscard,
              dependencies.submission.admission.accountID() == session.identity.ownerID,
              !dependencies.submission.admission.isLibraryAccessBlocked() else { return }
        let generation = draftSession.generation
        nativePhotoDispositionTask = Task { @MainActor in
            defer { nativePhotoDispositionTask = nil }
            do {
                try await session.discard()
                guard session.isDiscarded, draftSession.generation == generation, isDraftAccountCurrent,
                      dependencies.submission.admission.accountID() == session.identity.ownerID else { return }
                clearNativePhotoPresentation()
                stagedCapture.nativePhotoDraft = nil // every disposition acknowledged
                nativePhotoDraftSession = nil
                draftSession.reset()
                discardConfirmationGeneration = nil
            } catch {
                guard draftSession.generation == generation, isDraftAccountCurrent else { return }
                offlineToastMessage = .error("Draft removal needs recovery. Unfinished original ownership is retained.")
            }
        }
    }

    /// UI privacy only. This deliberately retains the native identity/session.
    func clearNativePhotoPresentation() {
        cancelActiveCropTask()
        operationState.removeAllRequiredGalleryCrops()
        stagedCapture.clearAll()
        nativePhotoPickerInputs.removeAll(); selectedPhotoItems.removeAll()
        descriptionDraft = ObservationContext(); descriptionFocusRequest = nil
        imageToCrop = nil; editingCropIndex = nil; isReviewActive = false
        revokeAutomaticSubmission()
    }
}
