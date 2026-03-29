import SwiftUI
import SwiftData
import SafariServices

/// Defines the unified local state graph and primary business logic orchestrating the `InsightSheetView` presentation and data actions.
@MainActor
@Observable
final class InsightSheetViewModel {
    
    // MARK: - Interface State
    var showCelebration = false
    var showBottomBarTools = false
    var isCommonNameScrolledPast = false
    
    // MARK: - Alert & Modal Flags
    var isFlagIssuePresented = false
    var showDeleteConfirmation = false
    var showSaveSuccessAlert = false
    var showNewCollectionAlert = false
    var toastMessage: String? = nil
    var newCollectionName = ""
    
    // MARK: - Navigation State
    var isSafariPresented = false
    var selectedWikiURL: URL? = nil
    
    // MARK: - Hardware Tasks
    var isSavingPhotos = false
    
    // MARK: - SwiftData Status
    var activeLocalRecord: LocalScanRecord? = nil
    
    // MARK: - Image Engine Dependencies
    var inferenceEngine: InferenceEngine? = nil
    
    // MARK: - Carousel Computed Properties
    var refUrls: [String] {
        inferenceEngine?.speciesData?.referenceImageUrl?
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }
    
    var validHistoricImagePaths: [String] {
        inferenceEngine?.validHistoricImagePaths ?? []
    }
    
    var hasLive: Bool {
        !(inferenceEngine?.activeDisplayDatas.isEmpty ?? true)
    }
    
    var liveCount: Int {
        inferenceEngine?.activeDisplayDatas.count ?? 0
    }
    
    var totalImages: Int {
        liveCount + validHistoricImagePaths.count + refUrls.count
    }
    
    // MARK: - Header Computed Properties
    var headerTitle: String {
        inferenceEngine?.speciesData?.commonName.capitalized ?? "Scanning subject..."
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
    
    func evaluateProcessingCompletion(isStillProcessing: Bool, inferenceEngine: InferenceEngine) {
        if !isStillProcessing {
            if let data = inferenceEngine.speciesData {
                let lowerName = data.commonName.lowercased()
                let isValidCelebration = data.isNewDiscovery && data.isBiological && lowerName != "not applicable" && lowerName != "unknown subject" && lowerName != "inanimate object"
                
                if !isValidCelebration {
                    HapticManager.shared.triggerSheetSpring()
                }
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
            if !record.hasBeenViewed {
                record.hasBeenViewed = true
                try? modelContext.save()
            }
        }
    }
}
