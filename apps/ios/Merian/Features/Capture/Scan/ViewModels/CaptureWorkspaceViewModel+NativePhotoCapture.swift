import CoreLocation
import UIKit

extension CaptureWorkspaceViewModel {
    /// The same native original owner used by picker import admits the hardware
    /// loader once. Neither camera preview nor legacy derivatives are evidence.
    func captureNativeCameraPhoto(emitHaptic: Bool) {
        let center = Double(composingZoneVerticalCenter)
        let recipe = SharedMediaNativePreparationRecipe(format: .cameraStill,
            isPro: dependencies.scan.canStartProScan(), cropDisplaySize: nil,
            quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0, cameraVerticalCenter: center)
        guard (try? recipe.validate()) != nil,
              !isDraftMutationLocked, !draftSession.hasUnresolvedWork, baseRefinementContext == nil,
              dependencies.photoOriginalPreparation == nil, dependencies.submission.nativePhotoSubmission == nil,
              stagedCapture.audios.isEmpty, stagedCapture.videos.isEmpty,
              !dependencies.submission.admission.isLibraryAccessBlocked(),
              let account = dependencies.submission.admission.accountID(),
              let factory = dependencies.submission.nativePhotoDraftFactory,
              nativePhotoDraftSession != nil || (stagedCapture.images.isEmpty && stagedCapture.nativePhotoDraft == nil),
              (nativePhotoDraftSession?.items.count ?? 0) < 2,
              let operation = beginDraftOperation(nativePhoto: true) else { return }
        let session = nativePhotoDraftSession ?? factory(account)
        guard session.identity.ownerID == account, session.canEdit,
              stagedCapture.nativePhotoDraft == nil || stagedCapture.nativePhotoDraft == session.identity else {
            completeDraftOperation(operation, succeeded: false)
            return
        }
        let itemID = UUID()
        nativePhotoDraftSession = session
        stagedCapture.nativePhotoDraft = session.identity // before hardware or durable IO
        revokeAutomaticSubmission()
        isCapturing = true
        let generation = scanOperationState.beginStillCapture()
        let task = Task { @MainActor [self] in
            var succeeded = false
            var capturedBytes: Data?
            var instantLocation: CLLocation?
            var shutterDate: Date?
            defer {
                capturedBytes = nil
                nativePhotoImportTask = nil
                finishStillCaptureUI(for: generation)
                completeDraftOperation(operation, succeeded: succeeded)
            }
            do {
                let (reference, preview) = try await session.acquire(itemID: itemID, kind: .camera) { @MainActor in
                    try self.requireCurrentNativeCamera(generation, operation: operation, account: account)
                    if emitHaptic { self.dependencies.scan.feedback.photoCapture() }
                    self.triggerFlash()
                    async let location = self.dependencies.scan.context.requestCurrentLocation()
                    shutterDate = Date()
                    let bytes = try await self.dependencies.scan.camera.captureImage()
                    let resolved = await location
                    // The registered owner checks lifetime and commits these exact
                    // bytes. Never trigger another shutter to resolve uncertainty.
                    capturedBytes = bytes
                    instantLocation = resolved ?? self.dependencies.scan.context.lastKnownLocation()
                    return bytes
                }
                try requireCurrentNativeCamera(generation, operation: operation, account: account)
                try session.setRecipe(recipe, for: reference)
                guard let source = preview.cgImage,
                      let framed = ImageCropProcessor.squareCrop(source, verticalCenterFraction: CGFloat(center)) else {
                    throw MediaPreparationError.unreadableImage
                }
                // Keep enrichment within this retained operation, so Identify
                // cannot freeze a partial image or accept a late context update.
                let enriched = await dependencies.scan.context.fetchDeferredContext(instantLocation)
                let context = EnvironmentContext(location: instantLocation, locationName: enriched.locationName,
                    weatherCondition: enriched.weatherCondition, weatherTemperature: enriched.weatherTemperature,
                    captureDate: shutterDate)
                try requireCurrentNativeCamera(generation, operation: operation, account: account)
                let original = IdentifiableImage(image: preview, environmentContext: context, isFromGallery: false,
                    initialCameraVerticalCenter: CGFloat(center))
                stagedCapture.images.append(.init(compressedData: Data(), displayData: Data(),
                    uiImage: UIImage(cgImage: framed), original: original, photoOriginalReference: reference))
                // Context and library work use existing clients after acquisition
                // and current-generation checks; neither grants native authority.
                let shutterLocation = instantLocation
                if let bytes = capturedBytes {
                    Task { @MainActor [weak self] in
                        guard let self, self.draftSession.generation == operation.generation,
                              self.isDraftAccountCurrent,
                              self.dependencies.submission.admission.accountID() == account,
                              !self.dependencies.submission.admission.isLibraryAccessBlocked() else { return }
                        await self.dependencies.scan.library.saveImage(bytes, shutterLocation)
                    }
                }
                succeeded = true
            } catch {
                if session.hasNoNativeAcquisition {
                    nativePhotoDraftSession = nil
                    stagedCapture.nativePhotoDraft = nil
                } else { session.holdForAttention() }
                guard draftSession.contains(operation), isDraftAccountCurrent,
                      dependencies.submission.admission.accountID() == account else { return }
                offlineToastMessage = .error("Camera capture needs attention. Any retained original remains protected.")
            }
        }
        nativePhotoImportTask = task
        scanOperationState.installStillCaptureTask(task, for: generation)
    }

    private func requireCurrentNativeCamera(_ generation: CaptureScanStillGeneration,
                                            operation: CaptureDraftSession.Operation, account: UUID) throws {
        try requireCurrentStillCapture(generation)
        guard draftSession.contains(operation), dependencies.submission.admission.accountID() == account,
              !dependencies.submission.admission.isLibraryAccessBlocked() else { throw SharedMediaStorageFailure.stale }
    }
}
