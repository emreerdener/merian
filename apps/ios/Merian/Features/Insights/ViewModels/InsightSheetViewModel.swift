import SafariServices
import SwiftData
import SwiftUI

/// Defines the unified local state graph and primary business logic orchestrating the `InsightSheetView` presentation and data actions.
@MainActor
@Observable
final class InsightSheetViewModel {

    // MARK: - Init

    /// Allows `InsightSheetView` to seed either a queued scan or a persisted record at
    /// `@State` initialization time, preventing the first render from falling back to a
    /// transient analyzing state while the sheet finishes wiring its dependencies.
    init(
        queuedContext: QueuedScanContext? = nil,
        initialRecord: LocalScanRecord? = nil,
        inferenceEngine: InferenceEngine? = nil,
        appSettings: AppSettings? = nil
    ) {
        self.queuedContext = queuedContext
        self.activeLocalRecord = initialRecord
        self.inferenceEngine = inferenceEngine
        self.appSettings = appSettings ?? AppSettings.shared
        self.cachedActiveMedia = queuedContext?.capturedMediaSnapshot.activeScanMedia
            ?? initialRecord?.capturedMediaSnapshot.activeScanMedia
    }

    var toastActionTitle: String?
    var toastAction: (() -> Void)?

    /// Wipes all memory-retained states that persist across SwiftUI sheet presentations since `activeSheet == .insight` evaluates to identical IDs natively.
    func reset() {
        sharedExploreStateRevision = 0
        sharedExploreStateRequestToken = 0
        boundFieldNotesScanId = nil
        state = UIState()
        toastActionTitle = nil
        toastAction = nil
        activeLocalRecord = nil
        queuedContext = nil
        cachedActiveMedia = nil
    }

    // MARK: - Internal Cached State
    /// An in-memory cache of the successfully decoded `ActiveScanMedia` representing the user's media.
    /// Safely decoded exactly once within lifecycle mappings (`init` and `fetchLocalRecord`) to prevent
    /// main-thread thrashing on layout changes where the framework routinely interrogates boundary sizes.
    private var cachedActiveMedia: ActiveScanMedia?
    @ObservationIgnored private var sharedExploreStateRevision: UInt64 = 0
    @ObservationIgnored private var sharedExploreStateRequestToken: UInt64 = 0
    @ObservationIgnored private var boundFieldNotesScanId: String?
    @ObservationIgnored private var appSettings: AppSettings

    // MARK: - Interface State
    struct UIState: Equatable {
        var showCelebration = false
        var showBottomBarTools = false
        var isCommonNameScrolledPast = false
        var isFieldNotesSheetPresented = false
        var isFlagIssuePresented = false
        var isIdentificationFlagPresented = false
        var showDeleteConfirmation = false
        var showSaveSuccessAlert = false
        var showNewCollectionAlert = false
        var isCandidateSwipePresented = false
        var showPaywall = false
        var toastMessage: String?
        var newCollectionName = ""
        var preferredCommonName: String?
        var isNamePickerPresented = false
        var isSafariPresented = false
        var selectedWikiURL: URL?
        var isSavingPhotos = false
        var isSharingToExplore = false
        var isUpdatingExplorePostContent = false
        var isUpdatingExploreFieldNotes = false
        var showExploreOnboarding = false
        var sharedExplorePostId: String?
        var sharedExploreHashtags: [String] = []
        var exploreFieldNotesArePublic = false
        var showExploreSheet = false
        var fieldNotesText = ""
        var dismissedFieldNotesCardScanId: String?
    }

    var state = UIState()

    func bindSettings(_ appSettings: AppSettings) {
        self.appSettings = appSettings
    }

    var hasUserPhotos: Bool {
        !activeMedia.imagePathsForUpload.isEmpty || activeMedia.liveImageData != nil
    }

    // MARK: - SwiftData Status
    var activeLocalRecord: LocalScanRecord?

    // MARK: - Image Engine Dependencies
    var inferenceEngine: InferenceEngine?

    // MARK: - Queued Scan Context
    /// Non-nil when the sheet is presenting a queued scan from `LibraryView` rather than a
    /// live inference result. Stored as a value-type `QueuedScanContext` — never a live
    /// `OfflineQueuedScan` reference — so computed properties cannot access a zombie `@Model`
    /// during SwiftUI's sheet dismissal animation after `context.delete()` fires.
    var queuedContext: QueuedScanContext?

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
        return activeLocalRecord?.id
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
        return inferenceEngine?.activeMedia ?? ActiveScanMedia()
    }

    var observationContext: ObservationContext? {
        for item in activeMedia.items {
            if case .description(let ctx) = item { return ctx }
        }
        return nil
    }

    var currentFieldNotesScanId: String? {
        if let ctx = queuedContext { return ctx.id }
        return activeLocalRecord?.id
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
        guard activeLocalRecord != nil else { return false }
        return true
    }

    var canReviewAlternatives: Bool {
        guard queuedContext == nil else { return false }
        guard let speciesData = inferenceEngine?.speciesData else { return false }
        return !(speciesData.candidates ?? []).isEmpty &&
            !speciesData.alternativesExhausted &&
            !speciesData.isFlagged
    }

    var canConfirm: Bool {
        guard queuedContext == nil else { return false }
        guard let speciesData = inferenceEngine?.speciesData else { return false }
        return !speciesData.userConfirmedIdentification && speciesData.userIdentificationOverride == nil && !speciesData.isFlagged
    }

    var canShareToExplore: Bool {
        guard queuedContext == nil else { return false }
        guard let record = activeLocalRecord else { return false }
        return record.isBiological
    }

    var isAlreadyFlagged: Bool {
        guard queuedContext == nil else { return false }
        return inferenceEngine?.speciesData?.isFlagged ?? false
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
        if let preferred = state.preferredCommonName, !preferred.isEmpty {
            return preferred
        }
        let common = species.commonName.trimmingCharacters(in: .whitespacesAndNewlines)
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
        inferenceEngine?.speciesData?.scientificName ?? "Awaiting taxonomy"
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

    // MARK: - Lifecycle Handlers

    func evaluateVoiceOverAndCelebration(inferenceEngine: InferenceEngine) {
        let hazardType = inferenceEngine.speciesData?.insightData.hazardType ?? "none"
        let commonName = inferenceEngine.speciesData?.commonName.capitalized ?? "Scanning subject..."

        if UIAccessibility.isVoiceOverRunning {
            let hazardWarning: String
            switch hazardType {
            case "venomous":   hazardWarning = "Warning: This species is venomous."
            case "allergenic": hazardWarning = "Warning: This species may trigger allergic reactions."
            case "irritant":   hazardWarning = "Warning: This species may cause skin or eye irritation."
            case "poisonous":  hazardWarning = "Warning: This species is toxic."
            default:           hazardWarning = ""
            }
            let announcement = hazardWarning.isEmpty ? commonName : "\(commonName). \(hazardWarning)"
            UIAccessibility.post(notification: .announcement, argument: announcement)
        }

        if let data = inferenceEngine.speciesData, data.isNewDiscovery {
            let lowerName = data.commonName.lowercased()
            if data.isBiological && lowerName != "not applicable" && lowerName != "unknown subject" && lowerName != "inanimate object" {
                state.showCelebration = true
            }
        }
    }

    func evaluateProcessingCompletion(isStillProcessing: Bool, inferenceEngine: InferenceEngine, modelContext: ModelContext) {
        guard !isStillProcessing else { return }

        markRecordViewedIfAppropriate(modelContext: modelContext)

        // The sheet was opened before inference completed, so onAppear saw nil speciesData.
        // Re-evaluate celebration and VoiceOver now that data has arrived.
        evaluateVoiceOverAndCelebration(inferenceEngine: inferenceEngine)
        if let data = inferenceEngine.speciesData {
            let lowerName = data.commonName.lowercased()
            let isValidCelebration = data.isNewDiscovery && data.isBiological
                && lowerName != "not applicable"
                && lowerName != "unknown subject"
                && lowerName != "inanimate object"
            if !isValidCelebration {
                HapticManager.shared.triggerSheetSpring()
            }
            
            if data.isBiological && !appSettings.hasSeenExploreOnboarding {
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    guard !Task.isCancelled else { return }
                    if self.canShareToExplore && !self.appSettings.hasSeenExploreOnboarding {
                        self.appSettings.hasSeenExploreOnboarding = true
                        withAnimation {
                            self.state.showExploreOnboarding = true
                        }
                    }
                }
            } else if !data.isBiological {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    self.state.toastMessage = "Scan succeeded. Added to non-biological collection."
                    self.toastActionTitle = "View"
                    self.toastAction = {
                        AppEventPublisher.shared.send(.requestOpenNonBiologicalScansIntent)
                    }
                }
            }
        }
    }

    // MARK: - Media & Share Exports

    func saveUserPhotos(inferenceEngine: InferenceEngine) {
        guard !state.isSavingPhotos else { return }
        state.isSavingPhotos = true

        let liveData = inferenceEngine.activeMedia.items.compactMap { if case .liveImage(let data) = $0 { return data } else { return nil } }.first
        let validPaths = inferenceEngine.activeMedia.items.compactMap { if case .image(let path) = $0 { return path } else { return nil } }
        let refUrls = inferenceEngine.speciesData?.referenceImageUrl

        InsightMediaExportManager.shared.saveUserPhotos(
            liveData: liveData,
            validPaths: validPaths,
            referenceImageUrl: refUrls
        ) { photosSaved in
            self.state.isSavingPhotos = false
            if photosSaved > 0 {
                HapticManager.shared.triggerSuccessPulse()
                self.state.showSaveSuccessAlert = true
            }
        }
    }

    func shareDiscovery(inferenceEngine: InferenceEngine) {
        let commonName = inferenceEngine.speciesData?.commonName.capitalized ?? "Scanning subject..."
        let scientificName = inferenceEngine.speciesData?.scientificName ?? "Awaiting taxonomy"
        let liveData = inferenceEngine.activeMedia.items.compactMap { if case .liveImage(let data) = $0 { return data } else { return nil } }.first
        let historicPath = inferenceEngine.activeMedia.items.compactMap { if case .image(let path) = $0 { return path } else { return nil } }.first
        let refUrls = inferenceEngine.speciesData?.referenceImageUrl

        InsightMediaExportManager.shared.shareDiscovery(
            commonName: commonName,
            scientificName: scientificName,
            liveData: liveData,
            historicPath: historicPath,
            referenceImageUrl: refUrls,
            presentShareSheet: { items in
                ShareSheetUtility.present(items: items)
            }
        )
    }

    func shareToExplore(
        includeFieldNotes: Bool = false,
        fieldNotes: String? = nil,
        hashtags: [String] = [],
        locationSharing: ExplorePostLocationSharing = .obscured
    ) async {
        guard canShareToExplore, let record = activeLocalRecord, !state.isSharingToExplore else { return }

        state.isSharingToExplore = true
        defer { state.isSharingToExplore = false }

        do {
            let notesForPost = fieldNotes ?? (includeFieldNotes ? shareableFieldNotes : nil)
            let response = try await MerianNetworkClient.shared.shareScanToExplore(
                scan: record,
                fieldNotes: notesForPost,
                hashtags: hashtags,
                locationSharing: locationSharing
            )
            appSettings.hasUnseenExplorePost = true
            cacheSharedExplorePostId(response.postId, for: record.id)
            state.sharedExploreHashtags = hashtags
            state.exploreFieldNotesArePublic = notesForPost != nil
            HapticManager.shared.triggerSuccessPulse()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                state.toastMessage = "Shared to Explore"
                toastActionTitle = "View"
                toastAction = { [weak self] in
                    self?.state.showExploreSheet = true
                }
            }
        } catch {
            HapticManager.shared.triggerErrorThump()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                state.toastMessage = ExploreErrorFormatter.message(for: error)
            }
        }
    }

    func updateExploreFieldNotesVisibility(
        isPublic: Bool,
        modelContext: ModelContext
    ) async -> FieldNotesVisibilityUpdateFeedback {
        guard let postId = state.sharedExplorePostId, !state.isUpdatingExploreFieldNotes else {
            return .failure("Field notes visibility is already updating")
        }

        guard !isPublic || shareableFieldNotes != nil else {
            return .failure("Add field notes before publishing them")
        }

        state.isUpdatingExploreFieldNotes = true
        defer { state.isUpdatingExploreFieldNotes = false }

        do {
            if !isPublic, let shareableFieldNotes {
                preserveLocalFieldNotesIfNeeded(shareableFieldNotes, modelContext: modelContext)
            }

            let response = try await MerianNetworkClient.shared.updateExplorePostFieldNotes(
                postId: postId,
                fieldNotes: isPublic ? shareableFieldNotes : nil
            )
            let publicNotes = response.fieldNotes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            state.exploreFieldNotesArePublic = publicNotes
            HapticManager.shared.triggerSuccessPulse()
            return .success(isPublic: publicNotes)
        } catch {
            HapticManager.shared.triggerErrorThump()
            return .failure(ExploreErrorFormatter.message(for: error))
        }
    }

    func updateExplorePostContent(
        _ draft: ExplorePostComposerDraft,
        modelContext: ModelContext
    ) async {
        guard let postId = state.sharedExplorePostId, !state.isUpdatingExplorePostContent else { return }

        state.isUpdatingExplorePostContent = true
        defer { state.isUpdatingExplorePostContent = false }

        do {
            let response = try await MerianNetworkClient.shared.updateExplorePostContent(
                postId: postId,
                fieldNotes: draft.publicFieldNotes,
                hashtags: draft.hashtags,
                locationSharing: draft.locationSharing
            )
            state.sharedExploreHashtags = response.hashtags ?? draft.hashtags
            state.exploreFieldNotesArePublic = response.fieldNotes?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty == false

            let draftNotes = draft.fieldNotes ?? ""
            state.fieldNotesText = draftNotes
            _ = persistFieldNotes(draftNotes, modelContext: modelContext)

            HapticManager.shared.triggerSuccessPulse()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                state.toastMessage = "Explore post updated"
            }
        } catch {
            HapticManager.shared.triggerErrorThump()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                state.toastMessage = ExploreErrorFormatter.message(for: error)
            }
        }
    }

// Removed presentShareSheet as this logic was extracted into ShareSheetUtility

    // MARK: - SwiftData Operations

    func eradicateCurrentScan(modelContext: ModelContext, inferenceEngine: InferenceEngine, dismiss: DismissAction) {
        guard let targetId = inferenceEngine.speciesData?.scanId else { return }

        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == targetId })
        let records = (try? modelContext.fetch(descriptor)) ?? []

        if let record = records.first {
            HapticManager.shared.triggerErrorThump()
            ScanRepository.shared.eradicateScan(record: record, modelContext: modelContext)
            dismiss()
        }
    }

    func toggleScanInCollection(_ collection: ScanCollection, modelContext: ModelContext) {
        guard let record = activeLocalRecord else { return }

        var updatedCollections = record.collections ?? []
        let actionMessage: String

        if updatedCollections.contains(where: { $0.id == collection.id }) {
            updatedCollections.removeAll(where: { $0.id == collection.id })
            actionMessage = "Removed from \(collection.name)"
        } else {
            updatedCollections.append(collection)
            actionMessage = "Added to \(collection.name)"
        }

        record.collections = updatedCollections
        guard saveInsightMutation(
            modelContext,
            failureMessage: "Could not update collection. Please try again.",
            logContext: "toggle scan collection"
        ) else {
            HapticManager.shared.triggerErrorThump()
            return
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            state.toastMessage = actionMessage
        }
        OfflineQueueManager.shared.enqueueCollectionSync()
        HapticManager.shared.triggerSelectionPulse()
    }

    @discardableResult
    private func saveInsightMutation(
        _ modelContext: ModelContext,
        failureMessage: String?,
        logContext: String
    ) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            MerianLog.data.error("InsightSheetViewModel: failed to save \(logContext, privacy: .public): \(error, privacy: .private)")
            if let failureMessage {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    state.toastMessage = failureMessage
                }
            }
            return false
        }
    }

// Removed createNewCollection as this logic was extracted into NewCollectionAlertModifier

    func fetchLocalRecord(for scanId: String, modelContext: ModelContext) {
        if activeLocalRecord?.id == scanId {
            markRecordViewedIfAppropriate(modelContext: modelContext)
            return
        }
        
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
        if let record = (try? modelContext.fetch(descriptor))?.first {
            bindPresentedRecord(record, modelContext: modelContext)
        }
    }

    @discardableResult
    func promoteQueuedScanIfLocalRecordExists(
        scanId: String,
        modelContext: ModelContext,
        inferenceEngine: InferenceEngine
    ) -> Bool {
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1

        guard let record = (try? modelContext.fetch(descriptor))?.first else {
            return false
        }

        inferenceEngine.load(from: record)
        bindPresentedRecord(record, modelContext: modelContext)
        queuedContext = nil

        if let scientificName = inferenceEngine.speciesData?.scientificName {
            loadPreferredCommonName(for: scientificName, modelContext: modelContext)
        }
        evaluateVoiceOverAndCelebration(inferenceEngine: inferenceEngine)
        MerianLog.data.debug(
            "InsightSheetViewModel.promoteQueuedScanIfLocalRecordExists: promoted scanId=\(scanId, privacy: .public)"
        )
        return true
    }

    func bindPresentedRecord(_ record: LocalScanRecord, modelContext: ModelContext) {
        activeLocalRecord = record
        cachedActiveMedia = record.capturedMediaSnapshot.activeScanMedia
        refreshSharedExploreStateFromLocalCache(scanId: record.id)
        syncFieldNotesFromCurrentScan(modelContext: modelContext)
        markRecordViewedIfAppropriate(modelContext: modelContext)
    }

    func updateFieldNotes(_ text: String, modelContext: ModelContext) {
        state.fieldNotesText = text
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state.dismissedFieldNotesCardScanId = nil
        }
        persistFieldNotes(text, modelContext: modelContext)
    }

    func dismissFieldNotesCard() {
        guard let currentFieldNotesScanId else { return }
        HapticManager.shared.triggerLightImpact()
        state.dismissedFieldNotesCardScanId = currentFieldNotesScanId
    }

    func syncFieldNotesFromCurrentScan(modelContext: ModelContext) {
        let currentScanId = currentFieldNotesScanId
        let existingDraft = state.fieldNotesText

        guard currentScanId != boundFieldNotesScanId else {
            guard let currentScanId else { return }

            let persistedFieldNotes = persistedFieldNotes(for: currentScanId, modelContext: modelContext) ?? ""
            if let activeLocalRecord,
               activeLocalRecord.id == currentScanId,
               activeLocalRecord.fieldNotes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                let promotableFieldNotes = existingDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? persistedFieldNotes
                    : existingDraft
                if !promotableFieldNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    state.fieldNotesText = promotableFieldNotes
                    persistFieldNotes(promotableFieldNotes, modelContext: modelContext)
                    return
                }
            }

            if persistedFieldNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !existingDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                persistFieldNotes(existingDraft, modelContext: modelContext)
            } else if existingDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !persistedFieldNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state.fieldNotesText = persistedFieldNotes
            }
            return
        }

        let previousScanId = boundFieldNotesScanId
        boundFieldNotesScanId = currentScanId

        guard let currentScanId else {
            if previousScanId != nil {
                state.fieldNotesText = ""
            }
            return
        }

        let storedFieldNotes = persistedFieldNotes(for: currentScanId, modelContext: modelContext) ?? ""
        let hasExistingDraft = !existingDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasStoredFieldNotes = !storedFieldNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if previousScanId == nil, hasExistingDraft, !hasStoredFieldNotes {
            persistFieldNotes(existingDraft, modelContext: modelContext)
        } else {
            state.fieldNotesText = storedFieldNotes
        }
    }

    func refreshSharedExploreStateFromLocalCache(scanId: String? = nil) {
        let resolvedScanId = scanId ?? activeLocalRecord?.id ?? inferenceEngine?.speciesData?.scanId
        applySharedExplorePostId(
            resolvedScanId.flatMap { ExploreShareStateStore.sharedPostId(for: $0) },
            for: resolvedScanId,
            bumpRevision: true
        )
    }

    func refreshSharedExploreStateFromServer(modelContext: ModelContext? = nil) async {
        let scanId = activeLocalRecord?.id ?? inferenceEngine?.speciesData?.scanId
        guard let scanId, !scanId.isEmpty else { return }

        sharedExploreStateRequestToken &+= 1
        let requestToken = sharedExploreStateRequestToken
        let requestRevision = sharedExploreStateRevision

        do {
            let shareState = try await MerianNetworkClient.shared.getExploreShareState(scanId: scanId)
            guard !Task.isCancelled else { return }
            guard requestToken == sharedExploreStateRequestToken else { return }
            guard requestRevision == sharedExploreStateRevision else { return }

            ExploreShareStateStore.setSharedPostId(shareState.postId, for: scanId)
            applySharedExplorePostId(shareState.postId, for: scanId, bumpRevision: false)
            await refreshExploreFieldNotesVisibility(
                postId: shareState.postId,
                modelContext: modelContext
            )
        } catch {
            // Keep the optimistic local cache when the authoritative refresh is unavailable.
        }
    }

    private func refreshExploreFieldNotesVisibility(
        postId: String?,
        modelContext: ModelContext?
    ) async {
        guard let postId else {
            state.exploreFieldNotesArePublic = false
            state.sharedExploreHashtags = []
            return
        }

        do {
            let detail = try await MerianNetworkClient.shared.getExplorePostDetail(postId: postId)
            state.sharedExploreHashtags = detail.hashtags ?? []
            if let fieldNotes = detail.trimmedFieldNotes {
                state.exploreFieldNotesArePublic = true
                if let modelContext {
                    promotePublishedExploreFieldNotesIfLocalMissing(
                        fieldNotes,
                        modelContext: modelContext
                    )
                }
            } else {
                state.exploreFieldNotesArePublic = false
            }
        } catch {
            state.exploreFieldNotesArePublic = false
        }
    }

    func markRecordViewedIfAppropriate(modelContext: ModelContext) {
        guard let record = activeLocalRecord else { return }
        if !record.hasBeenViewed && (inferenceEngine?.isProcessing == false) {
            record.hasBeenViewed = true
            _ = saveInsightMutation(
                modelContext,
                failureMessage: nil,
                logContext: "mark record viewed"
            )
        }
    }

    // MARK: - Name Preference

    /// Loads the user's preferred common name for the given scientific name.
    /// Call this whenever a new species is presented so `resolvedHeaderTitle` reflects the preference.
    func loadPreferredCommonName(for scientificName: String, modelContext: ModelContext) {
        state.preferredCommonName = SpeciesPreferredNameRepository.preferredName(
            for: scientificName,
            modelContext: modelContext
        )
    }

    /// Persists the user's preferred common name and updates the in-memory state immediately
    /// so `resolvedHeaderTitle` recomputes without requiring a re-fetch.
    func setPreferredCommonName(_ name: String, for scientificName: String, modelContext: ModelContext) {
        let didSave = SpeciesPreferredNameRepository.setPreferredName(
            name,
            for: scientificName,
            modelContext: modelContext
        )
        guard didSave else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                state.toastMessage = "Could not save preferred name"
            }
            HapticManager.shared.triggerErrorThump()
            return
        }

        state.preferredCommonName = SpeciesPreferredNameRepository.preferredName(
            for: scientificName,
            modelContext: modelContext
        )
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            state.toastMessage = "Preferred name set to \"\(name)\""
        }
        HapticManager.shared.triggerSelectionPulse()
    }

    /// Removes the stored preference, reverting the headline to the canonical DB common name.
    func clearPreferredCommonName(for scientificName: String, modelContext: ModelContext) {
        let didClear = SpeciesPreferredNameRepository.clearPreferredName(
            for: scientificName,
            modelContext: modelContext
        )
        guard didClear else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                state.toastMessage = "Could not clear preferred name"
            }
            HapticManager.shared.triggerErrorThump()
            return
        }

        state.preferredCommonName = nil
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            state.toastMessage = "Reverted to default name"
        }
        HapticManager.shared.triggerSelectionPulse()
    }

    private func cacheSharedExplorePostId(_ postId: String?, for scanId: String) {
        ExploreShareStateStore.setSharedPostId(postId, for: scanId)
        AppEventPublisher.shared.send(.exploreShareStateChanged(scanId: scanId, postId: postId))
        applySharedExplorePostId(
            ExploreShareStateStore.sharedPostId(for: scanId),
            for: scanId,
            bumpRevision: true
        )
    }

    @discardableResult
    private func persistFieldNotes(_ text: String, modelContext: ModelContext) -> Bool {
        guard let scanId = currentFieldNotesScanId else { return false }
        boundFieldNotesScanId = scanId

        return FieldNotesRepository.setFieldNotes(
            text,
            for: scanId,
            modelContext: modelContext,
            activeRecord: activeLocalRecord
        )
    }

    private func persistedFieldNotes(for scanId: String, modelContext: ModelContext) -> String? {
        FieldNotesRepository.fieldNotes(
            for: scanId,
            modelContext: modelContext,
            activeRecord: activeLocalRecord
        )
    }

    func promotePublishedExploreFieldNotesIfLocalMissing(_ notes: String, modelContext: ModelContext) {
        guard let scanId = currentFieldNotesScanId,
              state.fieldNotesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        if let resolvedNotes = FieldNotesRepository.promoteExternalFieldNotesIfLocalMissing(
            notes,
            for: scanId,
            modelContext: modelContext,
            activeRecord: activeLocalRecord
        ) {
            state.fieldNotesText = resolvedNotes
        }
    }

    private func preserveLocalFieldNotesIfNeeded(_ notes: String, modelContext: ModelContext) {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if state.fieldNotesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state.fieldNotesText = notes
        }

        guard let scanId = currentFieldNotesScanId else { return }
        boundFieldNotesScanId = scanId

        _ = FieldNotesRepository.promoteExternalFieldNotesIfLocalMissing(
            notes,
            for: scanId,
            modelContext: modelContext,
            activeRecord: activeLocalRecord
        )
    }

    private func applySharedExplorePostId(_ postId: String?, for scanId: String?, bumpRevision: Bool) {
        if bumpRevision {
            sharedExploreStateRevision &+= 1
        }

        guard scanId != nil else {
            state.sharedExplorePostId = nil
            state.exploreFieldNotesArePublic = false
            return
        }

        let trimmed = postId?.trimmingCharacters(in: .whitespacesAndNewlines)
        state.sharedExplorePostId = (trimmed?.isEmpty == false) ? trimmed : nil
        if state.sharedExplorePostId == nil {
            state.exploreFieldNotesArePublic = false
        }
    }

}
