import SwiftUI

extension CaptureWorkspaceViewModel {
    func triggerFlash() {
        flashOpacity = 1.0
        withAnimation(.easeOut(duration: 0.15)) {
            flashOpacity = 0.0
        }
    }

    func handleFocusTap(devicePoint: CGPoint) {
        dependencies.scan.camera.setFocusPoint(devicePoint)
        dependencies.scan.feedback.selection()
    }

    func executeCapture(emitHaptic: Bool = true) {
        guard activeSheet == nil,
              !isCapturing,
              hasAvailableStagedCaptureSlot,
              imageToCrop == nil else { return }

        isCapturing = true

        Task {
            guard await requestScanAdmission(
                flashFallbackEligible: stagedCapture.isEmpty
                    && baseRefinementContext == nil
            ) != nil else {
                isCapturing = false
                return
            }

            if emitHaptic {
                dependencies.scan.feedback.photoCapture()
            }

            triggerFlash()

            do {
                async let shutterLocation = dependencies.scan.context
                    .requestCurrentLocation()
                let composingCenter = composingZoneVerticalCenter
                let captureData = try await dependencies.scan.camera
                    .captureImage()
                let resolvedShutterLocation = await shutterLocation
                let instantLocation = resolvedShutterLocation
                    ?? dependencies.scan.context.lastKnownLocation()

                let saveImage = dependencies.scan.library.saveImage
                Task {
                    await saveImage(captureData, instantLocation)
                }

                let preparedCapture = try await dependencies.scan.media
                    .prepareStill(CaptureScanStillPreparationRequest(
                        captureData: captureData,
                        composingCenter: composingCenter,
                        isProActive: dependencies.scan.canStartProScan()
                    ))

                if let preparedCapture {
                    let fetchDeferredContext = dependencies.scan.context
                        .fetchDeferredContext
                    let contextTask = Task {
                        await fetchDeferredContext(instantLocation)
                    }

                    preFetchTask = contextTask
                    let previewImage = UIImage(
                        cgImage: preparedCapture.previewCGImage.image,
                        scale: 1.0,
                        orientation: .up
                    )
                    let identifiable = IdentifiableImage(
                        image: previewImage,
                        environmentContext: nil,
                        isFromGallery: false
                    )
                    stagedCapture.images.append(StagedImage(
                        compressedData: preparedCapture.inferenceData,
                        displayData: preparedCapture.displayData,
                        uiImage: previewImage,
                        original: identifiable,
                        focusRegion: preparedCapture.focusRegion
                    ))
                    beginAutomaticStagedSubmissionIfEligible()
                }
            } catch {
                MerianLog.hardware.error(
                    "Hardware shutter failure: \(error, privacy: .private)"
                )
            }

            isCapturing = false
        }
    }
}
