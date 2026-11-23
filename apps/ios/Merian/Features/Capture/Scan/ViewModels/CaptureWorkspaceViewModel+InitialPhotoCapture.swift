import CoreLocation
import Foundation

extension CaptureWorkspaceViewModel {
    func captureInitialCameraPhoto(emitHaptic: Bool) {
        guard let account = dependencies.submission.admission.accountID(),
              initialDraftMutationTask == nil, let operation = beginDraftOperation() else { return }
        let generation = scanOperationState.beginStillCapture(), itemID = UUID()
        let draftGeneration = draftSession.generation
        let center = Double(composingZoneVerticalCenter)
        let isPro = dependencies.scan.canStartProScan()
        let recipe = SharedMediaNativePreparationRecipe(format: .cameraStill, isPro: isPro,
            cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0, cameraVerticalCenter: center)
        isCapturing = true
        let task = Task { @MainActor [self] in
            var succeeded = false
            defer {
                initialDraftMutationTask = nil
                finishStillCaptureUI(for: generation)
                completeDraftOperation(operation, succeeded: succeeded)
            }
            do {
                let session = try await diContainer.nativeMediaLifecycle.runCaptureDraftWork(ownerID: account) { [self] in
                    let session = try await resolveInitialDraft()
                    try requireInitialDraft(session, generation: draftGeneration)
                    guard session.frozenPlan == nil, session.sources.allSatisfy(\.ready),
                          (session.journal?.value.items.filter { !$0.sourceIDs.isEmpty }.count ?? 0) < stagedCaptureLimit else {
                        throw SharedMediaStorageFailure.closed
                    }
                    try requireCurrentStillCapture(generation)
                    if emitHaptic { dependencies.scan.feedback.photoCapture() }
                    triggerFlash()
                    let capturedAt = Date()
                    let distance = diContainer.cameraManager.subjectDistanceInMeters
                    let zoom = Double(diContainer.cameraManager.zoomFactor)
                    async let requestedLocation = dependencies.scan.context.requestCurrentLocation()
                    let bytes = try await dependencies.scan.camera.captureImage()
                    let location = await requestedLocation ?? dependencies.scan.context.lastKnownLocation()
                    let context = EnvironmentContext(location: location, captureDate: capturedAt)
                    let facts = SharedMediaCaptureSourceFacts(addedAt: capturedAt, context: context,
                        distance: distance, zoom: zoom)
                    let contentType = try CaptureInitialSourceAttempt.imageContentType(for: bytes)
                    let input = CaptureInitialSourceAttempt(itemID: itemID, bytes: bytes, role: .sourceImage,
                        contentType: contentType, context: .init(origin: .camera, cameraVerticalCenter: center, facts: facts),
                        review: .photo(recipe))
                    initialDraftPendingSources.append(input)
                    try requireCurrentStillCapture(generation)
                    try requireInitialDraft(session, generation: draftGeneration)
                    try await input.retain(in: session)
                    initialDraftPendingSources.removeAll { $0.itemID == itemID && $0.role == .sourceImage }
                    try requireCurrentStillCapture(generation)
                    // Library saving borrows the same captured bytes; it grants
                    // neither original custody nor submission acknowledgement.
                    await dependencies.scan.library.saveImage(bytes, location)
                    try await persistInitialDraftNotes(session)
                    return session
                }
                try requireCurrentStillCapture(generation)
                try await refreshInitialDraftPresentation(session, generation: draftGeneration)
                succeeded = true
            } catch {
                guard isDraftAccountCurrent, draftSession.generation == draftGeneration else { return }
                offlineToastMessage = .error("The photo couldn’t finish staging. Any retained original is kept for recovery.")
            }
        }
        initialDraftMutationTask = task
        scanOperationState.installStillCaptureTask(task, for: generation)
    }
}
