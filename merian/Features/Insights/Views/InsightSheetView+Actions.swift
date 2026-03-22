import SwiftUI
import SwiftData

// MARK: - Action Handlers
extension InsightSheetView {
    // MARK: - Lifecycle Handlers
    
    /// Triggers accessibility readout and initiates the New Discovery celebration UI if valid
    func evaluateVoiceOverAndCelebration() {
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
    /// Evaluates the end of an AI processing tick and drops standard haptic feedback if the scan isn't a "New Discovery" celebration instance
    func evaluateProcessingCompletion(isStillProcessing: Bool) {
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
    // MARK: - Media & Share Exports
    
    /// Pulls raw image data from memory, sandbox, and remote references, compiling them asynchronously to the user's iOS Photo Library
    func saveUserPhotos() {
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
    
    /// Compiles all scan attributes and calls the system `UIActivityViewController` pipeline
    func shareDiscovery() {
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
    
    /// Recursively isolates the active `UIWindow` controller hierarchy to mount UIKit sheets safely above SwiftUI environments
    func presentShareSheet(items: [Any]) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootVC = window.rootViewController else { return }
        
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        // Traverse safely up the stack to avoid overlapping presentation bounds
        var topController = rootVC
        while let presented = topController.presentedViewController {
            topController = presented
        }
        
        // Gracefully support iPad rendering anchors cleanly
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = topController.view
            popover.sourceRect = CGRect(x: topController.view.bounds.midX, y: topController.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        topController.present(activityVC, animated: true)
    }
    
    // MARK: - SwiftData Operations
    
    /// Fully eradicates the local scan instance from SwiftData, executing teardown of visual sandbox references natively
    func eradicateCurrentScan() {
        guard let targetId = inferenceEngine.speciesData?.scanId else { return }
        
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == targetId })
        let records = (try? modelContext.fetch(descriptor)) ?? []
        
        if let record = records.first {
            HapticManager.shared.triggerErrorThump()
            ScanRepository.shared.eradicateScan(record: record, modelContext: modelContext)
            dismiss()
        }
    }
    
    /// Reversibly mounts or drops a relational binding between the current `LocalScanRecord` and a targeted `ScanCollection`
    func toggleScanInCollection(_ collection: ScanCollection) {
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
    
    /// Instantiates a completely new `ScanCollection` container natively in SwiftData and inherently maps the active scan to it immediately
    func createNewCollection() {
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
    
    /// Isolates SwiftData query executions to actively hydrate relational attributes like custom user Folders/Collections dynamically.
    func fetchLocalRecord(for scanId: String) {
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
        activeLocalRecord = (try? modelContext.fetch(descriptor))?.first
    }
}
