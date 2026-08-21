import SwiftUI

enum InsightShareRecommendation: Equatable {
    case publishToExplore
    case askCommunity
    case communityPending
    case communityResolvedNeedsPublish
}

struct InsightResultToolbarRevealKey: Equatable {
    let scanId: String?
    let presentationGeneration: UInt64
}

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
            HapticManager.shared.triggerMediumPulse(source: "media.insight.audioBoost.enabled")
        } else {
            HapticManager.shared.triggerLightImpact(
                intensity: 0.5,
                source: "media.insight.audioBoost.disabled"
            )
        }
    }

    var observationContext: ObservationContext? {
        for item in activeMedia.items {
            if case .description(let ctx) = item { return ctx }
        }
        return nil
    }

    var currentFieldNotesScanId: String? {
        if let ctx = queuedContext { return ctx.id }
        if inferenceEngine?.speciesData?.scanId != nil {
            return presentedLocalRecordScanId
        }
        return inferenceEngine?.activeScanId
    }

    /// The completed engine result is the presentation authority. Any cached
    /// record identity must agree before a scan-bound action may combine the
    /// two sources.
    var presentedSpeciesScanId: String? {
        guard queuedContext == nil,
              let rawScanId = inferenceEngine?.speciesData?.scanId else {
            return nil
        }

        let scanId = rawScanId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scanId.isEmpty else { return nil }

        let cachedScanIds = [
            activeLocalRecord?.id,
            activeLocalRecordId,
            toolbarRecordSnapshot?.scanId
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard cachedScanIds.allSatisfy({
            $0.caseInsensitiveCompare(scanId) == .orderedSame
        }) else {
            return nil
        }

        return scanId
    }

    /// Exact persisted-record identity for actions that mutate local state or
    /// reuse scan-bound server state. Unlike Field Chat presentation, these
    /// actions cannot proceed before the local record and snapshot are bound.
    var presentedLocalRecordScanId: String? {
        guard let scanId = presentedSpeciesScanId,
              let activeLocalRecord,
              activeLocalRecord.id.caseInsensitiveCompare(scanId) == .orderedSame,
              let activeLocalRecordId,
              activeLocalRecordId.caseInsensitiveCompare(scanId) == .orderedSame,
              let snapshot = toolbarRecordSnapshot,
              snapshot.scanId.caseInsensitiveCompare(scanId) == .orderedSame else {
            return nil
        }
        return scanId
    }

    func isPresentingLocalRecord(
        scanId: String,
        generation: UInt64? = nil
    ) -> Bool {
        if let generation, generation != scanBoundActionGeneration {
            return false
        }
        return presentedLocalRecordScanId?
            .caseInsensitiveCompare(scanId) == .orderedSame
    }

    /// Exact identity for controls that are also available while a scan is
    /// still queued. The generation rejects an obsolete A presentation even
    /// when the same scan ID later appears again after an A → B → A switch.
    func isPresentingScan(
        scanId: String,
        generation: UInt64
    ) -> Bool {
        guard generation == scanBoundActionGeneration else { return false }
        if let queuedContext {
            return queuedContext.id.caseInsensitiveCompare(scanId) == .orderedSame
        }
        return isPresentingLocalRecord(scanId: scanId, generation: generation)
    }

    /// Exact identity for read-only media callbacks, which remain available
    /// before a completed local record has been bound. This deliberately uses
    /// the presentation authority rather than the destructive-action helper.
    func isPresentingMedia(
        scanId: String,
        generation: UInt64
    ) -> Bool {
        guard generation == scanBoundActionGeneration else { return false }
        return persistentScanId?
            .caseInsensitiveCompare(scanId) == .orderedSame
    }

    /// Reveals result-only actions after their presentation has settled.
    /// A completed record may reuse the queued row's scan ID, so callers must
    /// provide the monotonic presentation generation as the identity fence.
    @discardableResult
    func revealBottomBarTools(
        expectedScanId scanId: String,
        expectedGeneration generation: UInt64
    ) -> Bool {
        guard queuedContext == nil,
              isPresentingLocalRecord(
                  scanId: scanId,
                  generation: generation
              ),
              toolbarRecordSnapshot?.scanId
                .caseInsensitiveCompare(scanId) == .orderedSame else {
            return false
        }
        state.showBottomBarTools = true
        return true
    }

    var fieldNotesText: String {
        if queuedContext == nil,
           inferenceEngine?.speciesData?.scanId != nil,
           presentedLocalRecordScanId == nil {
            return ""
        }
        return state.fieldNotesText
    }

    var hasFieldNotes: Bool {
        !fieldNotesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var shouldShowFieldNotesCard: Bool {
        guard !hasFieldNotes else { return true }
        guard let currentFieldNotesScanId else { return true }
        return state.dismissedFieldNotesCardScanId != currentFieldNotesScanId
    }

    var shareableFieldNotes: String? {
        let trimmed = fieldNotesText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var fieldNotesPromptContext: FieldNotesPromptContext {
        FieldNotesPromptResolver.context(for: inferenceEngine?.speciesData)
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

    // MARK: - Toolbar Capability Flags

    var isReviewLocked: Bool {
        guard queuedContext == nil else { return false }
        guard let speciesData = inferenceEngine?.speciesData else { return false }
        return speciesData.userConfirmedIdentification || speciesData.userIdentificationOverride != nil
    }

    var canReanalyze: Bool {
        guard queuedContext == nil else { return false }
        return presentedLocalRecordScanId != nil
    }

    var canReviewAlternatives: Bool {
        guard queuedContext == nil else { return false }
        return !reviewAlternativeCandidates.isEmpty
    }

    var canReviewIdentificationConcernCandidates: Bool {
        !identificationConcernCandidates.isEmpty
    }

    var reviewAlternativeCandidates: [IdentificationCandidate] {
        guard queuedContext == nil else { return [] }
        return CandidateReviewVisibilityPolicy.visibleCandidates(for: inferenceEngine?.speciesData)
    }

    var identificationConcernCandidates: [IdentificationCandidate] {
        guard queuedContext == nil,
              let speciesData = inferenceEngine?.speciesData,
              speciesData.isBiological,
              speciesData.hasResolvedBiologicalIdentification,
              !speciesData.isHumanSubject,
              speciesData.userIdentificationOverride == nil,
              !speciesData.userConfirmedIdentification else {
            return []
        }

        return speciesData.candidates ?? []
    }

    var candidateSwipeCandidates: [IdentificationCandidate] {
        switch state.candidateSwipePresentationSource {
        case .standard:
            return reviewAlternativeCandidates
        case .identificationConcern:
            return identificationConcernCandidates
        }
    }

    var canConfirm: Bool {
        guard queuedContext == nil,
              presentedLocalRecordScanId != nil else { return false }
        return !reviewAlternativeCandidates.isEmpty
    }

    var canShareToExplore: Bool {
        guard queuedContext == nil,
              let speciesData = inferenceEngine?.speciesData,
              presentedLocalRecordScanId != nil,
              let snapshot = toolbarRecordSnapshot,
              speciesData.hasResolvedBiologicalIdentification,
              !speciesData.isHumanSubject,
              !snapshot.isHumanSubject else {
            return false
        }

        return snapshot.isExploreShareEligible && speciesData.isBiological
    }

    var canRequestCommunityIdentification: Bool {
        canShareToExplore && hasUserMedia
    }

    var shareRecommendation: InsightShareRecommendation {
        let hasPresentedRecord = presentedLocalRecordScanId != nil
        if hasPresentedRecord,
           state.sharedExplorePostId != nil,
           state.isExploreFeedVisible {
            return .publishToExplore
        }

        switch hasPresentedRecord ? state.sharedCommunityIdentificationStatus : nil {
        case .needsId:
            return .communityPending
        case .resolved:
            return .communityResolvedNeedsPublish
        case .withdrawn, nil:
            break
        }

        guard canRequestCommunityIdentification else {
            return .publishToExplore
        }

        if hasUserReviewedIdentification || hasStrongAIIdentification {
            return .publishToExplore
        }

        return .askCommunity
    }

    var requiresExplorePublishConfirmation: Bool {
        switch shareRecommendation {
        case .askCommunity, .communityPending:
            return true
        case .publishToExplore, .communityResolvedNeedsPublish:
            return false
        }
    }

    private var hasUserReviewedIdentification: Bool {
        guard let speciesData = inferenceEngine?.speciesData else { return false }
        return speciesData.userConfirmedIdentification
            || speciesData.userIdentificationOverride?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var hasStrongAIIdentification: Bool {
        guard let speciesData = inferenceEngine?.speciesData,
              speciesData.hasResolvedBiologicalIdentification,
              !speciesData.isHumanSubject else {
            return false
        }
        let bands = MerianConfig.confidenceBands(forInferenceTier: speciesData.inferenceTier)
        return speciesData.confidenceScore >= bands.strong
    }

    // MARK: - Content Routing

    enum ContentMode: Equatable {
        case analyzing
        case queued
        case nonBiological
        case biological
    }

    /// Derives which content subtree `InsightContentView` should render.
    /// Computed from engine state so each call site switches on one value
    /// rather than duplicating the `isProcessing` / `speciesData` guard chain.
    var contentMode: ContentMode {
        if queuedContext != nil { return .queued }
        if isProcessing { return .analyzing }
        guard let data = inferenceEngine?.speciesData else { return .analyzing }
        let usesSimplifiedResultView =
            data.isInferenceErrorPlaceholder ||
            data.isClassifiedNonBiological ||
            data.commonName.lowercased() == "not applicable"
        if usesSimplifiedResultView {
            return .nonBiological
        }
        return .biological
    }

    // MARK: - Header Computed Properties

    /// The display name shown as the InsightHeader headline.
    /// Applies the resolution chain: user preference → canonical DB common name.
    var resolvedHeaderTitle: String {
        guard let species = inferenceEngine?.speciesData else {
            return "Scanning subject..."
        }
        let common = species.subjectDisplayName(
            isAudioOnlyObservation: hasStandaloneAudio && !activeMedia.hasUserImage
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        if species.isInferenceErrorPlaceholder {
            return common.isEmpty ? "Analysis unavailable" : common
        }
        if species.isClassifiedNonBiological || common.lowercased() == "not applicable" {
            return "Non-biological"
        }
        if let petLabel = species.petIdentification?.label.trimmingCharacters(in: .whitespacesAndNewlines),
           !petLabel.isEmpty {
            return petLabel
        }
        if let preferred = state.preferredCommonName, !preferred.isEmpty {
            return preferred
        }
        let scientific = species.scientificName.trimmingCharacters(in: .whitespacesAndNewlines)
        if common.isEmpty {
            return scientific
        } else if common.lowercased() == scientific.lowercased() {
            return common
        } else {
            return common.capitalized
        }
    }

    /// All English synonym names available for user selection, excluding whichever name
    /// is currently resolved as the headline (to avoid surfacing the active name as an option).
    /// Uses allNamesForPicker as the base so the canonical primary name is included even
    /// when the user has chosen an alternative as their preferred headline.
    var displayAlternativeCommonNames: [String]? {
        let all = allNamesForPicker
        guard !all.isEmpty else { return nil }
        let activeKey = resolvedHeaderTitle.commonNameKey
        let filtered = all.filter { $0.commonNameKey != activeKey }
        return filtered.isEmpty ? nil : filtered
    }

    /// All candidate names for the picker sheet: primary common name + alternatives,
    /// with a checkmark on the currently resolved headline.
    var allNamesForPicker: [String] {
        guard let species = inferenceEngine?.speciesData else { return [] }
        let primary = species.commonName.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        let alternatives = species.alternativeCommonNames ?? []
        return ([primary] + alternatives).removingFuzzyDuplicateNames()
    }

    var headerSubtitle: String {
        guard let species = inferenceEngine?.speciesData else {
            return "Awaiting taxonomy"
        }
        return species.presentationScientificName
    }

    var hazardType: String {
        inferenceEngine?.speciesData?.insightData.hazardType ?? "none"
    }

    var isHazardous: Bool { hazardType != "none" }

    var headerParagraphs: [String] {
        guard let species = inferenceEngine?.speciesData, !species.insightData.aiReasoning.isEmpty else { return [] }
        return species.insightData.aiReasoning
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // MARK: - Layout Computations

    /// Keeps the iOS 26 top scroll-edge treatment away from the hero image, then
    /// restores it once the image clears the navigation toolbar. The separate
    /// return threshold prevents the effect from flickering at the boundary.
    func evaluateHeroScrollOffset(maxY: CGFloat) {
        let shouldHideEffect = MediaHeroTopScrollEdgeEffectPolicy.isHidden(
            heroMaxY: maxY,
            currentlyHidden: state.isTopScrollEdgeEffectHidden
        )

        guard state.isTopScrollEdgeEffectHidden != shouldHideEffect else { return }

        withAnimation(.easeInOut(duration: 0.18)) {
            state.isTopScrollEdgeEffectHidden = shouldHideEffect
        }
    }

    /// Evaluates dynamic coordinate thresholds actively against negative scroll intersections, routing structural top-bar offsets.
    func evaluateScrollOffset(minY: CGFloat) {
        guard minY != .infinity else { return }
        // The value passed is actually the Title text's 'maxY'.
        // When its bottom edge dips below the native sheet NavigationBar (44pt), it has "scrolled past" fully offscreen.
        let threshold: CGFloat = 44
        let isPast = minY < threshold

        if state.isCommonNameScrolledPast != isPast {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                state.isCommonNameScrolledPast = isPast
            }
        }
    }
}
