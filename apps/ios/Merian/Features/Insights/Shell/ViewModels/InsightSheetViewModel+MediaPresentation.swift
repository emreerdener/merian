import SwiftUI

extension InsightSheetViewModel {
    var hasUserMedia: Bool {
        activeMedia.hasUserImage
    }

    var activeRecordTimestamp: Date? {
        guard presentedLocalRecordScanId != nil else { return nil }
        return toolbarRecordSnapshot?.captureDate ?? toolbarRecordSnapshot?.timestamp
    }

    var activeConfirmedSpeciesId: String? {
        guard presentedLocalRecordScanId != nil else { return nil }
        return toolbarRecordSnapshot?.confirmedSpeciesId
    }

    var activeImageCount: Int {
        guard presentedLocalRecordScanId != nil else {
            return activeMedia.imagePathsForUpload.count +
                activeMedia.videoPaths.count +
                (activeMedia.liveImageData == nil ? 0 : 1)
        }
        return toolbarRecordSnapshot?.imageCount
            ?? activeMedia.imagePathsForUpload.count + activeMedia.videoPaths.count + (activeMedia.liveImageData == nil ? 0 : 1)
    }

    // MARK: - Processing State

    /// Mirrors `InferenceEngine.isProcessing`. Routing through the viewModel means
    /// toolbar flags and content routing all share a single source of truth without
    /// each view needing its own direct engine environment read.
    var isProcessing: Bool {
        if queuedContext != nil { return true }
        return inferenceEngine?.isProcessing ?? false
    }

    /// Keeps the carousel analysis treatment continuous while the same visual
    /// scan transfers from foreground inference to its durable queue owner.
    /// Ordinary queued scans animate only while inferencing; a typed live visual
    /// handoff also covers its non-terminal recovery states without remounting
    /// the overlay between queue claims.
    func isCarouselAnalysisActive(
        for explicitQueuedContext: QueuedScanContext?
    ) -> Bool {
        if let explicitQueuedContext {
            guard !explicitQueuedContext.queueNeedsAttention else {
                return false
            }

            switch explicitQueuedContext.queueState {
            case .inferencing:
                return true
            case .pending, .uploading, .staged:
                return inferenceEngine?.hasLiveVisualQueueHandoff(
                    for: explicitQueuedContext.id
                ) == true
            case .externalImport, .failed:
                return false
            }
        }
        return contentMode == .analyzing
    }

    /// Restarts the delayed result-toolbar reveal when a completed scan record
    /// becomes available after the analysis UI has already been presented.
    /// The generation keeps same-ID queued-to-result handoffs identity-safe.
    var resultToolbarRevealKey: InsightResultToolbarRevealKey {
        InsightResultToolbarRevealKey(
            scanId: presentedLocalRecordScanId,
            presentationGeneration: scanBoundActionGeneration
        )
    }

    // MARK: - Carousel Computed Properties

    /// Stable scan ID for keying `ImagesCarousel`. The engine's current
    /// presentation outranks a cached record so a stale record cannot key a
    /// newer scan's media.
    var persistentScanId: String? {
        if let ctx = queuedContext { return ctx.id }
        return inferenceEngine?.speciesData?.scanId
            ?? inferenceEngine?.activeScanId
            ?? activeLocalRecordId
    }

    @discardableResult
    func refreshQueuedContextIfCurrent(
        _ refreshedContext: QueuedScanContext,
        expectedScanId: String
    ) -> Bool {
        guard refreshedContext.id.caseInsensitiveCompare(expectedScanId) == .orderedSame,
              queuedContext?.id
                .caseInsensitiveCompare(expectedScanId) == .orderedSame else {
            return false
        }
        if refreshedContext != queuedContext {
            queuedContext = refreshedContext
            cachedActiveMedia = refreshedContext.activeScanMedia
        }
        return true
    }

    var refUrls: [String] {
        activeMedia.referenceState.urls
    }

    var shouldSuppressReferenceImages: Bool {
        if inferenceEngine?.speciesData?.shouldSuppressReferenceImages == true { return true }
        if presentedLocalRecordScanId != nil {
            if toolbarRecordSnapshot?.shouldSuppressReferenceImages == true { return true }
            if activeLocalRecord?.shouldSuppressReferenceImages == true { return true }
        }
        return false
    }

    private func displayMedia(_ media: ActiveScanMedia) -> ActiveScanMedia {
        let visibleMedia = shouldSuppressReferenceImages ? media.withoutReferenceImages : media
        return visibleMedia.removingDuplicateReferenceImages(
            excluding: additionalUserMediaIdentifiers
        )
    }

    private var additionalUserMediaIdentifiers: [String] {
        var identifiers: [String] = []
        if let queuedContext {
            identifiers.append(contentsOf: queuedContext.capturedMediaSnapshot.thumbnailImagePaths)
        } else if presentedLocalRecordScanId != nil {
            identifiers.append(
                contentsOf: activeLocalRecord?.capturedMediaSnapshot.thumbnailImagePaths ?? []
            )
            if let coverImagePath = toolbarRecordSnapshot?.coverImagePath {
                identifiers.append(coverImagePath)
            }
        }
        return identifiers
    }

    var activeMedia: ActiveScanMedia {
        if let queuedContext {
            if let inferenceEngine,
               inferenceEngine.hasLiveQueueHandoffMedia(
                   for: queuedContext.id
               ),
               inferenceEngine.activeMedia.totalItems > 0 {
                return displayMedia(inferenceEngine.activeMedia)
            }
            return displayMedia(cachedActiveMedia ?? ActiveScanMedia())
        }

        let engineMedia = inferenceEngine?.activeMedia ?? ActiveScanMedia()
        if engineMedia.hasUserImage {
            return displayMedia(engineMedia)
        }

        if inferenceEngine?.speciesData != nil,
           presentedSpeciesScanId == nil {
            return displayMedia(engineMedia)
        }

        guard var cachedMedia = cachedActiveMedia else {
            return displayMedia(engineMedia)
        }

        if cachedMedia.referenceState == .empty {
            cachedMedia.referenceState = engineMedia.referenceState
        }
        return displayMedia(cachedMedia)
    }

    var hasStandaloneAudio: Bool {
        activeMedia.items.contains { item in
            if case .audio = item { return true }
            return false
        }
    }

    var audioBoostEligibleScanId: String? {
        let hasPersistedScan = presentedLocalRecordScanId != nil
        guard InsightAudioBoostAvailability.isAvailable(
            hasPersistedScan: hasPersistedScan,
            isProcessing: isProcessing,
            hasStandaloneAudio: hasStandaloneAudio
        ) else { return nil }
        return persistentScanId
    }

    func finishAudioBoostAction(_ token: UUID) {
        guard state.audioBoostActionToken == token else { return }
        state.audioBoostActionToken = nil
    }

    func audioBoostBinding(
        expectedScanId: String,
        expectedGeneration: UInt64
    ) -> Binding<Bool> {
        Binding(
            get: { [weak self] in
                guard let self,
                      self.isPresentingLocalRecord(
                          scanId: expectedScanId,
                          generation: expectedGeneration
                      ),
                      self.audioBoostEligibleScanId?
                        .caseInsensitiveCompare(expectedScanId) == .orderedSame else {
                    return false
                }
                return self.state.isAudioBoostEnabled
            },
            set: { [weak self] enabled in
                guard let self,
                      self.isPresentingLocalRecord(
                          scanId: expectedScanId,
                          generation: expectedGeneration
                      ),
                      self.audioBoostEligibleScanId?
                        .caseInsensitiveCompare(expectedScanId) == .orderedSame else {
                    return
                }
                self.state.isAudioBoostEnabled = enabled
            }
        )
    }

    func toggleAudioBoostFromMedia(
        expectedScanId: String,
        expectedGeneration: UInt64
    ) {
        guard isPresentingLocalRecord(
            scanId: expectedScanId,
            generation: expectedGeneration
        ),
              audioBoostEligibleScanId?
                .caseInsensitiveCompare(expectedScanId) == .orderedSame else {
            return
        }
        if !state.isAudioBoostEnabled {
            state.audioBoostActionToken = UUID()
        }
        state.isAudioBoostEnabled.toggle()
        if state.isAudioBoostEnabled {
            dependencies.audioBoostEnabledFeedback()
        } else {
            dependencies.audioBoostDisabledFeedback()
        }
    }

    var observationContext: ObservationContext? {
        for item in activeMedia.items {
            if case .description(let ctx) = item { return ctx }
        }
        return nil
    }

    var totalImages: Int {
        return activeMedia.totalItems
    }

    // MARK: - View Binding Helpers

    /// Resolves the ActiveScanMedia for the view, correctly prioritizing a live passed-in queuedScan context.
    func resolvedMedia(for explicitQueuedScan: QueuedScanContext?) -> ActiveScanMedia {
        if let queued = explicitQueuedScan ?? queuedContext {
            if let inferenceEngine,
               inferenceEngine.hasLiveQueueHandoffMedia(for: queued.id),
               inferenceEngine.activeMedia.totalItems > 0 {
                return displayMedia(inferenceEngine.activeMedia)
            }
            if let cached = cachedActiveMedia { return displayMedia(cached) }
            return displayMedia(queued.activeScanMedia)
        }
        return displayMedia(activeMedia)
    }
}
