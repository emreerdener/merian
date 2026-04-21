import SafariServices
import SwiftData
import SwiftUI

/// Defines the unified local state graph and primary business logic orchestrating the `InsightSheetView` presentation and data actions.
@MainActor
@Observable
final class InsightSheetViewModel {

    // MARK: - Init

    /// Allows `InsightSheetView` to seed `queuedContext` at `@State` initialization time
    /// via `State(initialValue:)`, ensuring `contentMode` resolves to `.queued` on the
    /// very first SwiftUI render rather than defaulting to `.analyzing` during the nil-window
    /// that exists before `onAppear` fires.
    init(queuedContext: QueuedScanContext? = nil) {
        self.queuedContext = queuedContext
        if let jsonStr = queuedContext?.observationContextsJSON?.first, let data = jsonStr.data(using: .utf8) {
            self.cachedHistoricObservationContext = try? JSONDecoder().decode(ObservationContext.self, from: data)
        }
    }
    
    /// Wipes all memory-retained states that persist across SwiftUI sheet presentations since `activeSheet == .insight` evaluates to identical IDs natively.
    func reset() {
        showCelebration = false
        showBottomBarTools = false
        isCommonNameScrolledPast = false
        isDescriptionSheetPresented = false
        isFlagIssuePresented = false
        isIdentificationFlagPresented = false
        showDeleteConfirmation = false
        showSaveSuccessAlert = false
        showNewCollectionAlert = false
        isCandidateSwipePresented = false
        toastMessage = nil
        preferredCommonName = nil
        isNamePickerPresented = false
        isSafariPresented = false
        selectedWikiURL = nil
        isSavingPhotos = false
        activeLocalRecord = nil
        queuedContext = nil
        cachedHistoricObservationContext = nil
    }
    
    // MARK: - Internal Cached State
    /// An in-memory cache of the successfully decoded `ObservationContext` representing the user's text.
    /// Safely decoded exactly once within lifecycle mappings (`init` and `fetchLocalRecord`) to prevent
    /// main-thread thrashing on layout changes where the framework routinely interrogates boundary sizes.
    private var cachedHistoricObservationContext: ObservationContext?
    
    // MARK: - Interface State
    var showCelebration = false
    var showBottomBarTools = false
    var isCommonNameScrolledPast = false
    
    /// Indicates whether the `InsightDescriptionSheet` is currently covering the insight router organically.
    var isDescriptionSheetPresented = false

    // MARK: - Alert & Modal Flags
    var isFlagIssuePresented = false
    var isIdentificationFlagPresented = false
    var showDeleteConfirmation = false
    var showSaveSuccessAlert = false
    var showNewCollectionAlert = false
    var isCandidateSwipePresented = false
    var toastMessage: String?
    var newCollectionName = ""

    // MARK: - Name Preference State
    /// User's chosen display name for the current species, persisted in UserDefaults.
    /// Nil means no override — the canonical `commonName` from the DB is used.
    var preferredCommonName: String?
    /// Controls the name-picker bottom sheet.
    var isNamePickerPresented: Bool = false
    
    // MARK: - Navigation State
    var isSafariPresented = false
    var selectedWikiURL: URL?
    
    // MARK: - Hardware Tasks
    var isSavingPhotos = false
    
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
    /// then the persisted local record, then the engine's active speciesData scanId.
    var persistentScanId: String? {
        if let ctx = queuedContext { return ctx.id }
        return activeLocalRecord?.id ?? inferenceEngine?.speciesData?.scanId
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

    var validHistoricImagePaths: [String] {
        if let ctx = queuedContext { return ctx.localImagePaths }
        return inferenceEngine?.validHistoricImagePaths ?? []
    }

    /// Live capture image data for the carousel — mirrors `InferenceEngine.activeImageData`.
    /// Routed through the viewModel so `ImagesCarousel` has no direct engine dependency.
    var liveImageData: Data? {
        inferenceEngine?.activeImageData
    }
    
    var observationContext: ObservationContext? {
        if queuedContext != nil || activeLocalRecord != nil {
            return cachedHistoricObservationContext
        }
        return inferenceEngine?.activeObservationContext
    }

    /// Safely resolves the audio file path escalating top-down: offline queue snapshot, SQLite cache entity, and finally hot inference pipeline.
    var audioFilePath: String? {
        if let queued = queuedContext { return queued.audioFilePaths?.first }
        if let record = activeLocalRecord { return record.audioFilePaths?.first }
        return inferenceEngine?.speciesData?.audioFilePaths?.first
    }

    var hasLive: Bool {
        guard queuedContext == nil else { return false }
        return liveImageData != nil && validHistoricImagePaths.isEmpty
    }
    
    var hasUserPhotos: Bool {
        if let queued = queuedContext {
            return !queued.localImagePaths.isEmpty
        }
        return hasLive ? (liveImageData != nil) : !validHistoricImagePaths.isEmpty
    }

    var liveCount: Int {
        guard queuedContext == nil else { return 0 }
        return hasLive ? 1 : 0
    }

    var totalImages: Int {
        // carouselPages uses hasLive as an exclusive branch: when live data is present it
        // shows liveImageData and skips validHistoricImagePaths (they are the same image
        // written to disk — showing both would duplicate the capture). Must mirror that logic
        // here or totalImages overcounts and produces unreachable pagination dots.
        let captureCount = hasLive ? liveCount : validHistoricImagePaths.count
        let refCount = refUrls.count + ((inferenceEngine?.isReferenceImageLoading == true && refUrls.isEmpty) ? 1 : 0)
        let hasDescription = observationContext?.isEmpty == false
        let hasAudio = audioFilePath.map { FileManager.default.fileExists(atPath: URL.documentsDirectory.appendingPathComponent($0).path) } ?? false
        
        return captureCount + refCount + (hasDescription ? 1 : 0) + (hasAudio ? 1 : 0)
    }

    // MARK: - Toolbar Capability Flags

    var isReviewLocked: Bool {
        guard queuedContext == nil else { return false }
        guard let speciesData = inferenceEngine?.speciesData else { return false }
        return speciesData.userConfirmedIdentification || speciesData.userIdentificationOverride != nil
    }

    var canReanalyze: Bool {
        guard queuedContext == nil else { return false }
        if isReviewLocked { return false }
        guard let record = activeLocalRecord, !(record.localImagePath?.starts(with: "http") == true) else { return false }
        return (record.additionalImagePaths ?? []).isEmpty
    }

    var canReviewAlternatives: Bool {
        guard queuedContext == nil else { return false }
        if isReviewLocked { return false }
        guard let speciesData = inferenceEngine?.speciesData else { return false }
        return !(speciesData.candidates ?? []).isEmpty && !speciesData.alternativesExhausted
    }

    var canConfirm: Bool {
        guard queuedContext == nil else { return false }
        guard let speciesData = inferenceEngine?.speciesData else { return false }
        return !speciesData.userConfirmedIdentification && speciesData.userIdentificationOverride == nil && !speciesData.isFlagged
    }

    var isAlreadyFlagged: Bool {
        guard queuedContext == nil else { return false }
        return (inferenceEngine?.speciesData?.isFlagged ?? false) || isReviewLocked
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
        if let preferred = preferredCommonName, !preferred.isEmpty {
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
        
        if isCommonNameScrolledPast != isPast {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isCommonNameScrolledPast = isPast
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
                showCelebration = true
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
        }
    }
    
    // MARK: - Media & Share Exports
    
    func saveUserPhotos(inferenceEngine: InferenceEngine) {
        guard !isSavingPhotos else { return }
        isSavingPhotos = true
        
        let liveData = inferenceEngine.activeImageData
        let validPaths = inferenceEngine.validHistoricImagePaths
        let refUrls = inferenceEngine.speciesData?.referenceImageUrl
        
        InsightMediaExportManager.shared.saveUserPhotos(
            liveData: liveData,
            validPaths: validPaths,
            referenceImageUrl: refUrls
        ) { photosSaved in
            self.isSavingPhotos = false
            if photosSaved > 0 {
                HapticManager.shared.triggerSuccessPulse()
                self.showSaveSuccessAlert = true
            }
        }
    }
    
    func shareDiscovery(inferenceEngine: InferenceEngine) {
        let commonName = inferenceEngine.speciesData?.commonName.capitalized ?? "Scanning subject..."
        let scientificName = inferenceEngine.speciesData?.scientificName ?? "Awaiting taxonomy"
        let liveData = inferenceEngine.activeImageData
        let historicPath = inferenceEngine.validHistoricImagePaths.first
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
        
        if updatedCollections.contains(where: { $0.id == collection.id }) {
            updatedCollections.removeAll(where: { $0.id == collection.id })
            record.collections = updatedCollections
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                toastMessage = "Removed from \(collection.name)"
            }
        } else {
            updatedCollections.append(collection)
            record.collections = updatedCollections
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                toastMessage = "Added to \(collection.name)"
            }
        }
        
        try? modelContext.save()
        OfflineQueueManager.shared.enqueueCollectionSync()
        HapticManager.shared.triggerSelectionPulse()
    }
    
// Removed createNewCollection as this logic was extracted into NewCollectionAlertModifier
    
    func fetchLocalRecord(for scanId: String, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
        if let record = (try? modelContext.fetch(descriptor))?.first {
            activeLocalRecord = record
            if let jsonStr = record.observationContextsJSON?.first, let data = jsonStr.data(using: .utf8) {
                self.cachedHistoricObservationContext = try? JSONDecoder().decode(ObservationContext.self, from: data)
            }
            markRecordViewedIfAppropriate(modelContext: modelContext)
        }
    }
    
    func markRecordViewedIfAppropriate(modelContext: ModelContext) {
        guard let record = activeLocalRecord else { return }
        if !record.hasBeenViewed && (inferenceEngine?.isProcessing == false) {
            record.hasBeenViewed = true
            try? modelContext.save()
        }
    }

    // MARK: - Name Preference

    /// Loads the user's preferred common name for the given scientific name from UserDefaults.
    /// Call this whenever a new species is presented so `resolvedHeaderTitle` reflects the preference.
    func loadPreferredCommonName(for scientificName: String) {
        preferredCommonName = UserDefaults.standard.string(
            forKey: UserDefaultsKeys.speciesPreferredNamePrefix + scientificName
        )
    }

    /// Persists the user's preferred common name and updates the in-memory state immediately
    /// so `resolvedHeaderTitle` recomputes without requiring a re-fetch.
    func setPreferredCommonName(_ name: String, for scientificName: String) {
        UserDefaults.standard.set(name, forKey: UserDefaultsKeys.speciesPreferredNamePrefix + scientificName)
        preferredCommonName = name
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            toastMessage = "Preferred name set to \"\(name)\""
        }
        HapticManager.shared.triggerSelectionPulse()
    }

    /// Removes the stored preference, reverting the headline to the canonical DB common name.
    func clearPreferredCommonName(for scientificName: String) {
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.speciesPreferredNamePrefix + scientificName)
        preferredCommonName = nil
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            toastMessage = "Reverted to default name"
        }
        HapticManager.shared.triggerSelectionPulse()
    }
}
