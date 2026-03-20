import SwiftUI
import SwiftData

// MARK: - Action Handlers
extension InsightSheetView {
    
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
    
    func saveUserPhotos() {
        guard !isSavingPhotos else { return }
        isSavingPhotos = true
        
        Task {
            var photosSaved = 0
            
            // 1. Live photo payload
            if let liveData = inferenceEngine.activeImageData {
                let success = await PhotoLibraryManager.shared.saveImageManual(imageData: liveData)
                if success { photosSaved += 1 }
            }
            
            // 2. Local historical images securely cached on disk
            for path in inferenceEngine.validHistoricImagePaths {
                let url = URL.documentsDirectory.appendingPathComponent(path)
                if let data = try? Data(contentsOf: url) {
                    let success = await PhotoLibraryManager.shared.saveImageManual(imageData: data)
                    if success { photosSaved += 1 }
                }
            }
            
            // 3. Remote user uploads explicitly filtering out GBIF/Wiki bounds
            let refUrls: [String] = inferenceEngine.speciesData?.referenceImageUrl?.components(separatedBy: ",").filter { !$0.isEmpty } ?? []
            for urlStr in refUrls {
                let cleanStr = urlStr.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleanStr.contains("merian.app"), let url = URL(string: cleanStr) {
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        let success = await PhotoLibraryManager.shared.saveImageManual(imageData: data)
                        if success { photosSaved += 1 }
                    } catch {
                        print("Failed to map R2 cloud payload for UI download: \(error)")
                    }
                }
            }
            
            await MainActor.run {
                isSavingPhotos = false
                if photosSaved > 0 {
                    HapticManager.shared.triggerSuccessPulse()
                    showSaveSuccessAlert = true
                }
            }
        }
    }
    
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
    
    func shareDiscovery() {
        var items: [Any] = [
            "Check out this \(commonName) (\(scientificName)) I discovered using Merian! \nhttps://merian.app"
        ]
        
        let liveData = inferenceEngine.activeImageData
        let historicPath = inferenceEngine.validHistoricImagePaths.first
        let refUrls: [String] = inferenceEngine.speciesData?.referenceImageUrl?.components(separatedBy: ",").filter { !$0.isEmpty } ?? []
        let safeCloudUrl = refUrls.first(where: { $0.contains("merian.app") })?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        Task {
            let extractedImage = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                if let live = liveData, let image = UIImage(data: live) {
                    return image
                } else if let validPath = historicPath,
                          let data = try? Data(contentsOf: URL.documentsDirectory.appendingPathComponent(validPath)),
                          let image = UIImage(data: data) {
                    return image
                }
                return nil
            }.value
            
            if let image = extractedImage {
                items.insert(image, at: 0)
                await MainActor.run { presentShareSheet(items: items) }
            } else if let urlStr = safeCloudUrl, let url = URL(string: urlStr) {
                if let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) {
                    items.insert(image, at: 0)
                }
                await MainActor.run { presentShareSheet(items: items) }
            } else {
                await MainActor.run { presentShareSheet(items: items) }
            }
        }
    }
    
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
}
