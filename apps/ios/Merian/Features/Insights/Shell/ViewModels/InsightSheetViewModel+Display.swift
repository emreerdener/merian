import SwiftUI

enum InsightShareRecommendation: Equatable {
    case publishToExplore
    case askCommunity
    case communityPending
    case communityResolvedNeedsPublish
}

extension InsightSheetViewModel {
    var hasUserPhotos: Bool {
        activeMedia.hasUserImage
    }

    var activeRecordTimestamp: Date? {
        toolbarRecordSnapshot?.captureDate ?? toolbarRecordSnapshot?.timestamp
    }

    var activeConfirmedSpeciesId: String? {
        toolbarRecordSnapshot?.confirmedSpeciesId
    }

    var activeImageCount: Int {
        toolbarRecordSnapshot?.imageCount
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

    // MARK: - Carousel Computed Properties

    /// Stable scan ID for keying `ImagesCarousel`. Prefers the queued scan's own ID,
    /// then the persisted local record, then the engine's in-flight scan ID, then the
    /// completed speciesData scan ID.
    var persistentScanId: String? {
        if let ctx = queuedContext { return ctx.id }
        return activeLocalRecordId
            ?? inferenceEngine?.activeScanId
            ?? inferenceEngine?.speciesData?.scanId
    }

    var refUrls: [String] {
        guard let data = inferenceEngine?.speciesData else { return [] }
        // Block Wikipedia/GBIF reference images for human subjects — surfacing
        // third-party photos of people is inappropriate regardless of source.
        guard !data.isHumanSubject else { return [] }
        return data.referenceImageUrl?
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    var activeMedia: ActiveScanMedia {
        if queuedContext != nil {
            return cachedActiveMedia ?? ActiveScanMedia()
        }

        let engineMedia = inferenceEngine?.activeMedia ?? ActiveScanMedia()
        if engineMedia.hasUserImage {
            return engineMedia
        }

        guard var cachedMedia = cachedActiveMedia else {
            return engineMedia
        }

        if cachedMedia.referenceState == .empty {
            cachedMedia.referenceState = engineMedia.referenceState
        }
        return cachedMedia
    }

    var observationContext: ObservationContext? {
        for item in activeMedia.items {
            if case .description(let ctx) = item { return ctx }
        }
        return nil
    }

    var currentFieldNotesScanId: String? {
        if let ctx = queuedContext { return ctx.id }
        return activeLocalRecordId
            ?? inferenceEngine?.activeScanId
            ?? inferenceEngine?.speciesData?.scanId
    }

    var fieldNotesText: String {
        state.fieldNotesText
    }

    var hasFieldNotes: Bool {
        !state.fieldNotesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var shouldShowFieldNotesCard: Bool {
        guard !hasFieldNotes else { return true }
        guard let currentFieldNotesScanId else { return true }
        return state.dismissedFieldNotesCardScanId != currentFieldNotesScanId
    }

    var shareableFieldNotes: String? {
        let trimmed = state.fieldNotesText.trimmingCharacters(in: .whitespacesAndNewlines)
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
            if let cached = cachedActiveMedia { return cached }
            return queued.capturedMediaSnapshot.activeScanMedia
        }
        return activeMedia
    }

    // MARK: - Toolbar Capability Flags

    var isReviewLocked: Bool {
        guard queuedContext == nil else { return false }
        guard let speciesData = inferenceEngine?.speciesData else { return false }
        return speciesData.userConfirmedIdentification || speciesData.userIdentificationOverride != nil
    }

    var canReanalyze: Bool {
        guard queuedContext == nil else { return false }
        guard activeLocalRecordId != nil else { return false }
        return true
    }

    var canReviewAlternatives: Bool {
        guard queuedContext == nil else { return false }
        return !reviewAlternativeCandidates.isEmpty
    }

    var reviewAlternativeCandidates: [IdentificationCandidate] {
        guard queuedContext == nil else { return [] }
        return CandidateReviewVisibilityPolicy.visibleCandidates(for: inferenceEngine?.speciesData)
    }

    var canConfirm: Bool {
        guard queuedContext == nil else { return false }
        return !reviewAlternativeCandidates.isEmpty
    }

    var canShareToExplore: Bool {
        guard queuedContext == nil else { return false }
        if let speciesData = inferenceEngine?.speciesData, speciesData.isHumanSubject { return false }
        if let snapshot = toolbarRecordSnapshot, snapshot.isHumanSubject { return false }
        return toolbarRecordSnapshot?.isExploreShareEligible == true &&
            inferenceEngine?.speciesData?.isBiological == true
    }

    var canRequestCommunityIdentification: Bool {
        canShareToExplore && hasUserPhotos
    }

    var shareRecommendation: InsightShareRecommendation {
        if state.sharedExplorePostId != nil, state.isExploreFeedVisible {
            return .publishToExplore
        }

        switch state.sharedCommunityIdentificationStatus {
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
        guard let speciesData = inferenceEngine?.speciesData else { return false }
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
        if !data.isBiological || data.commonName.lowercased() == "not applicable" { return .nonBiological }
        return .biological
    }

    // MARK: - Header Computed Properties

    /// The display name shown as the InsightHeader headline.
    /// Applies the resolution chain: user preference → canonical DB common name.
    var resolvedHeaderTitle: String {
        guard let species = inferenceEngine?.speciesData else {
            return "Scanning subject..."
        }
        let common = species.commonName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !species.isBiological || common.lowercased() == "not applicable" {
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
        return species.scientificName
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
