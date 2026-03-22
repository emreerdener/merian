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
    
    // MARK: - Layout Computations
    
    /// Evaluates dynamic coordinate thresholds actively against negative scroll intersections, routing structural top-bar offsets.
    func evaluateScrollOffset(minY: CGFloat) {
        guard minY != .infinity else { return }
        let threshold = -(UIScreen.main.bounds.width + 80)
        let isPast = minY < threshold
        
        if isCommonNameScrolledPast != isPast {
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.isCommonNameScrolledPast = isPast
                }
            }
        }
    }
    
    // MARK: - Lifecycle Handlers
    
    func evaluateVoiceOverAndCelebration(inferenceEngine: InferenceEngine) {
        let isPoisonous = inferenceEngine.speciesData?.insightData.isPoisonous ?? false
        let commonName = inferenceEngine.speciesData?.commonName.capitalized ?? "Scanning subject..."
        
        if UIAccessibility.isVoiceOverRunning {
            let announcement = isPoisonous ? "\(commonName). Warning: This subject is poisonous." : commonName
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
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
                self.presentShareSheet(items: items)
            }
        )
    }
    
    func presentShareSheet(items: [Any]) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootVC = window.rootViewController else { return }
        
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        var topController = rootVC
        while let presented = topController.presentedViewController {
            topController = presented
        }
        
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = topController.view
            popover.sourceRect = CGRect(x: topController.view.bounds.midX, y: topController.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        topController.present(activityVC, animated: true)
    }
    
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
        
        if record.collections == nil {
            record.collections = []
        }
        
        if record.collections?.contains(where: { $0.id == collection.id }) == true {
            record.collections?.removeAll(where: { $0.id == collection.id })
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                toastMessage = "Removed from \(collection.name)"
            }
        } else {
            record.collections?.append(collection)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                toastMessage = "Added to \(collection.name)"
            }
        }
        
        try? modelContext.save()
        HapticManager.shared.triggerSelectionPulse()
    }
    
    func createNewCollection(modelContext: ModelContext) {
        let collectionName = newCollectionName.isEmpty ? "Untitled" : newCollectionName
        let collection = ScanCollection(name: collectionName)
        
        modelContext.insert(collection)
        
        if activeLocalRecord?.collections == nil {
            activeLocalRecord?.collections = []
        }
        activeLocalRecord?.collections?.append(collection)
        
        try? modelContext.save()
        newCollectionName = ""
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            toastMessage = "Created \(collectionName) and added scan"
        }
        HapticManager.shared.triggerSuccessPulse()
    }
    
    func fetchLocalRecord(for scanId: String, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
        activeLocalRecord = (try? modelContext.fetch(descriptor))?.first
    }
}
