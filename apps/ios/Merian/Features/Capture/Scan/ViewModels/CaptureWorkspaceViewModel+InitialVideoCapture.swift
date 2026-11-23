import AVFoundation
import Foundation

extension CaptureWorkspaceViewModel {
    func captureInitialVideo() {
        guard initialDraftMutationTask == nil, let account = dependencies.submission.admission.accountID(),
              let operation = beginDraftOperation() else { return }
        let generation = scanOperationState.beginVideoRecording()
        let draftGeneration = draftSession.generation, itemID = operation.id
        let center = Double(composingZoneVerticalCenter), isPro = dependencies.scan.canStartProScan()
        let capturedAt = Date()
        let shutterLocation = dependencies.scan.context.lastKnownLocation()
        isCapturing = true
        videoRecordingProgress = 0
        let task = Task { @MainActor [self] in
            var succeeded = false
            defer {
                initialDraftMutationTask = nil
                finishVideoCaptureUI(for: generation, resetProgress: true)
                completeDraftOperation(operation, succeeded: succeeded)
            }
            do {
                let session = try await diContainer.nativeMediaLifecycle.runCaptureDraftWork(ownerID: account) { [self] in
                    let session = try await resolveInitialDraft()
                    try requireInitialDraft(session, generation: draftGeneration)
                    guard let resources = try initialDraftProducerResources?.currentValue() else { throw SharedMediaStorageFailure.closed }
                    guard session.frozenPlan == nil, session.sources.allSatisfy(\.ready),
                          (session.journal?.value.items.filter { !$0.sourceIDs.isEmpty }.count ?? 0) < stagedCaptureLimit else {
                        throw SharedMediaStorageFailure.capacity
                    }
                    let recording = try await dependencies.scan.camera.recordVideo(Self.videoMaxDuration) { [weak self] in
                        guard let self, self.scanOperationState.isCurrent(generation) else { return }
                        self.isVideoRecording = true
                        self.dependencies.scan.feedback.videoStarted()
                        self.startVideoRecordingProgressTimer(for: generation)
                    }
                    // Keep the producer's file even when source validation or a
                    // durable copy fails. Retirement is explicit and retryable.
                    let sourceLease = CaptureScanTemporaryFileLease(fileURL: recording.fileURL)
                    initialDraftTemporaryFiles[itemID, default: []].append(sourceLease)
                    // Register a complete retry descriptor before the first
                    // suspension after the camera returns its original.
                    let facts = SharedMediaCaptureSourceFacts(addedAt: capturedAt,
                        context: EnvironmentContext(location: shutterLocation, captureDate: capturedAt))
                    let recipe = SharedMediaCaptureDraftJournal.VideoRecipe(duration: recording.duration,
                        isPro: isPro, composingCenter: center, scale: 1, offsetX: 0, offsetY: 0,
                        displaySize: nil, quarterTurns: 0)
                    initialDraftVideoAttempts[itemID] = .init(fileURL: recording.fileURL, facts: facts,
                        recipe: recipe, companion: nil)
                    try resources.retain(sourceLease)
                    try resources.preserveBeforeRetirement(itemID: itemID) { [self] in
                        try await materializeInitialVideoAttempt(itemID: itemID, resources: resources)
                        initialDraftVideoAttempts[itemID] = nil
                    }
                    try requireInitialDraft(session, generation: draftGeneration)
                    guard scanOperationState.isCurrent(generation) else { throw CancellationError() }
                    isVideoRecording = false; isPreparingVideo = true
                    dependencies.scan.feedback.videoCompleted()
                    try await retainInitialVideoAttempt(itemID: itemID, session: session, generation: draftGeneration)
                    try await persistInitialDraftNotes(session)
                    return session
                }
                try await refreshInitialDraftPresentation(session, generation: draftGeneration)
                succeeded = true
            } catch {
                guard isDraftAccountCurrent, draftSession.generation == draftGeneration else { return }
                offlineToastMessage = .error("The video couldn’t finish staging. Retained media is kept for recovery.")
            }
        }
        initialDraftMutationTask = task
        scanOperationState.installVideoRecordingTask(task, for: generation)
    }

    /// Retry the same producer file, shutter facts and complete companion
    /// membership. No retry recaptures or silently converts a video to silent.
    func retainInitialVideoAttempt(itemID: UUID, session: CaptureInitialDraftSession, generation: UUID) async throws {
        guard let attempt = initialDraftVideoAttempts[itemID],
              let resources = try initialDraftProducerResources?.currentValue() else { throw SharedMediaStorageFailure.closed }
        try requireInitialDraft(session, generation: generation)
        try await materializeInitialVideoAttempt(itemID: itemID, resources: resources)
        try requireInitialDraft(session, generation: generation)
        let inputs = initialDraftPendingSources.filter { $0.itemID == itemID }
        _ = try await session.retainSources(inputs.map(\.retention))
        try requireInitialDraft(session, generation: generation)
        resources.acknowledge(itemID: itemID)
        initialDraftPendingSources.removeAll { $0.itemID == itemID }
        initialDraftVideoAttempts[itemID] = nil
        await dependencies.scan.library.saveVideo(attempt.fileURL, attempt.facts.environmentContext.location)
        try requireInitialDraft(session, generation: generation)
        try await retireInitialTemporaryFiles(itemID: itemID)
    }

    private func materializeInitialVideoAttempt(itemID: UUID, resources: CaptureInitialProducerResources) async throws {
        guard var attempt = initialDraftVideoAttempts[itemID] else { throw SharedMediaStorageFailure.closed }
        var inputs = initialDraftPendingSources.filter { $0.itemID == itemID }
        if inputs.isEmpty {
            guard let original = initialDraftTemporaryFiles[itemID]?.first else { throw SharedMediaStorageFailure.closed }
            let bytes = try await original.readOriginal(maximumBytes: 12_582_912)
            inputs = [.init(itemID: itemID, bytes: bytes, role: .sourceVideo,
                contentType: "video/mp4", context: .init(origin: .camera,
                    cameraVerticalCenter: attempt.recipe.composingCenter, facts: attempt.facts), review: .video(attempt.recipe))]
            let audioTracks = try await AVURLAsset(url: attempt.fileURL).loadTracks(withMediaType: .audio)
            if !audioTracks.isEmpty {
                if attempt.companion == nil {
                    guard let companion = await CaptureScanVideoAudioExtractor.extract(videoURL: attempt.fileURL) else {
                        throw SharedMediaStorageFailure.unavailable
                    }
                    initialDraftTemporaryFiles[itemID, default: []].append(companion)
                    try resources.retainForRecovery(companion, itemID: itemID)
                    attempt.companion = companion
                    initialDraftVideoAttempts[itemID] = attempt
                }
                guard let companion = attempt.companion else { throw SharedMediaStorageFailure.closed }
                let audio = try await companion.readOriginal(maximumBytes: 2_700_000)
                inputs.append(.init(itemID: itemID, bytes: audio, role: .sourceCompanionAudio,
                    contentType: "audio/wav", context: .init(origin: .videoAudio,
                        cameraVerticalCenter: nil, facts: attempt.facts), review: nil))
            }
            initialDraftPendingSources.append(contentsOf: inputs)
        }
    }

    func retireInitialTemporaryFiles(itemID: UUID) async throws {
        while let lease = initialDraftTemporaryFiles[itemID]?.first {
            if let resources = try? initialDraftProducerResources?.currentValue() {
                try await resources.retire(lease)
            } else { try await lease.discard() }
            initialDraftTemporaryFiles[itemID]?.removeFirst()
        }
        initialDraftTemporaryFiles.removeValue(forKey: itemID)
    }
}
