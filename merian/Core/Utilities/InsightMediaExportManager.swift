import SwiftUI

@MainActor
final class InsightMediaExportManager {
    static let shared = InsightMediaExportManager()
    
    func saveUserPhotos(liveData: Data?, validPaths: [String], referenceImageUrl: String?, completion: @escaping (Int) -> Void) {
        let refUrls: [String] = referenceImageUrl?.components(separatedBy: ",").filter { !$0.isEmpty } ?? []
        
        Task.detached(priority: .userInitiated) {
            var photosSaved = 0
            
            // 1. Live photo payload
            if let data = liveData {
                let success = await PhotoLibraryManager.shared.saveImageManual(imageData: data)
                if success { photosSaved += 1 }
            }
            
            // 2. Local historical images securely cached on disk
            for path in validPaths {
                let url = URL.documentsDirectory.appendingPathComponent(path)
                if let data = try? Data(contentsOf: url) {
                    let success = await PhotoLibraryManager.shared.saveImageManual(imageData: data)
                    if success { photosSaved += 1 }
                }
            }
            
            // 3. Remote user uploads explicitly filtering out GBIF/Wiki bounds
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
            
            let finalPhotosSaved = photosSaved
            await MainActor.run {
                completion(finalPhotosSaved)
            }
        }
    }
    
    func shareDiscovery(commonName: String, scientificName: String, liveData: Data?, historicPath: String?, referenceImageUrl: String?, presentShareSheet: @escaping ([Any]) -> Void) {
        var items: [Any] = [
            "Check out this \(commonName) (\(scientificName)) I discovered using Merian! \nhttps://merian.app"
        ]
        
        let refUrls: [String] = referenceImageUrl?.components(separatedBy: ",").filter { !$0.isEmpty } ?? []
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
                await MainActor.run { presentShareSheet(items) }
            } else if let urlStr = safeCloudUrl, let url = URL(string: urlStr) {
                if let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) {
                    items.insert(image, at: 0)
                }
                await MainActor.run { presentShareSheet(items) }
            } else {
                await MainActor.run { presentShareSheet(items) }
            }
        }
    }
}
