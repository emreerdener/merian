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

        let generation = scanOperationState.beginStillCapture()
        let captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.finishStillCaptureUI(for: generation) }

            guard await self.requestScanAdmission(
                flashFallbackEligible: self.stagedCapture.isEmpty
                    && self.baseRefinementContext == nil
            ) != nil else { return }

            do {
                try self.requireCurrentStillCapture(generation)

                if emitHaptic {
                    self.dependencies.scan.feedback.photoCapture()
                }

                self.triggerFlash()

                async let shutterLocation = self.dependencies.scan.context
                    .requestCurrentLocation()
                let composingCenter = self.composingZoneVerticalCenter
                let captureData = try await self.dependencies.scan.camera
                    .captureImage()
                try self.requireCurrentStillCapture(generation)

                let resolvedShutterLocation = await shutterLocation
                try self.requireCurrentStillCapture(generation)
                let instantLocation = resolvedShutterLocation
                    ?? self.dependencies.scan.context.lastKnownLocation()

                let saveImage = self.dependencies.scan.library.saveImage
                Task { @MainActor in
                    await saveImage(captureData, instantLocation)
                }

                let preparedCapture = try await self.dependencies.scan.media
                    .prepareStill(CaptureScanStillPreparationRequest(
                        captureData: captureData,
                        composingCenter: composingCenter,
                        isProActive: self.dependencies.scan.canStartProScan()
                    ))
                try self.requireCurrentStillCapture(generation)

                if let preparedCapture {
                    let fetchDeferredContext = self.dependencies.scan.context
                        .fetchDeferredContext
                    let contextTask = Task {
                        await fetchDeferredContext(instantLocation)
                    }

                    self.preFetchTask = contextTask
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
                    self.stagedCapture.images.append(StagedImage(
                        compressedData: preparedCapture.inferenceData,
                        displayData: preparedCapture.displayData,
                        uiImage: previewImage,
                        original: identifiable,
                        focusRegion: preparedCapture.focusRegion
                    ))
                    self.beginAutomaticStagedSubmissionIfEligible()
                }
            } catch is CancellationError {
                return
            } catch {
                guard self.scanOperationState.isCurrent(generation) else {
                    return
                }
                MerianLog.hardware.error(
                    "Hardware shutter failure: \(error, privacy: .private)"
                )
            }
        }
        scanOperationState.installStillCaptureTask(
            captureTask,
            for: generation
        )
    }

    @discardableResult
    func cancelStillCapture() -> Bool {
        guard scanOperationState.cancelStillCapture() else { return false }
        isCapturing = false
        return true
    }

    private func requireCurrentStillCapture(
        _ generation: CaptureScanStillGeneration
    ) throws {
        guard !Task.isCancelled,
              scanOperationState.isCurrent(generation) else {
            throw CancellationError()
        }
    }

    private func finishStillCaptureUI(
        for generation: CaptureScanStillGeneration
    ) {
        guard scanOperationState.finishStillCapture(generation) else {
            return
        }
        isCapturing = false
    }
}
