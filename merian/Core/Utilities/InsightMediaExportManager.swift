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
                let success = await PhotoLibraryManager.shared.saveImageManual(fileURL: url)
                if success { photosSaved += 1 }
            }
            
            // 3. Remote user uploads explicitly filtering out GBIF/Wiki bounds
            for urlStr in refUrls {
                let cleanStr = urlStr.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleanStr.contains("merian.app"), let url = URL(string: cleanStr) {
                    do {
                        let (fileURL, _) = try await URLSession.shared.download(from: url)
                        let success = await PhotoLibraryManager.shared.saveImageManual(fileURL: fileURL)
                        if success { photosSaved += 1 }
                        try? FileManager.default.removeItem(at: fileURL)
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
    
    func batchSaveUserPhotos(records: [LocalScanRecord], completion: @escaping (Int) -> Void) {
        Task.detached(priority: .userInitiated) {
            var photosSaved = 0
            
            for record in records {
                var validPaths: [String] = []
                if let p = record.localImagePath { validPaths.append(p) }
                if let extras = record.additionalImagePaths { validPaths.append(contentsOf: extras) }
                
                // 1. Local historical images securely cached on disk
                for path in validPaths {
                    let url = URL.documentsDirectory.appendingPathComponent(path)
                    let success = await PhotoLibraryManager.shared.saveImageManual(fileURL: url)
                    if success { photosSaved += 1 }
                }
                
                // 2. Remote user uploads explicitly filtering out GBIF/Wiki bounds
                let refUrls = record.referenceImageUrl?.components(separatedBy: ",").filter { !$0.isEmpty } ?? []
                for urlStr in refUrls {
                    let cleanStr = urlStr.trimmingCharacters(in: .whitespacesAndNewlines)
                    if cleanStr.contains("merian.app"), let url = URL(string: cleanStr) {
                        do {
                            let (fileURL, _) = try await URLSession.shared.download(from: url)
                            let success = await PhotoLibraryManager.shared.saveImageManual(fileURL: fileURL)
                            if success { photosSaved += 1 }
                            try? FileManager.default.removeItem(at: fileURL)
                        } catch {
                            print("Failed to map R2 cloud payload for UI download: \(error)")
                        }
                    }
                }
            }
            
            let finalPhotosSaved = photosSaved
            await MainActor.run {
                completion(finalPhotosSaved)
            }
        }
    }
    
    func batchShareDiscovery(records: [LocalScanRecord], presentShareSheet: @escaping ([Any]) -> Void) {
        Task {
            var items: [Any] = []
            
            for record in records {
                items.append("Check out this \(record.commonName) (\(record.scientificName)) I discovered using Merian! \nhttps://merian.app")
                
                let extractedImage = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                    if let validPath = record.localImagePath,
                       let data = try? Data(contentsOf: URL.documentsDirectory.appendingPathComponent(validPath)),
                       let image = UIImage(data: data) {
                        return image
                    }
                    return nil
                }.value
                
                if let image = extractedImage {
                    items.append(image)
                } else {
                    let refUrls = record.referenceImageUrl?.components(separatedBy: ",").filter { !$0.isEmpty } ?? []
                    if let safeCloudUrl = refUrls.first(where: { $0.contains("merian.app") })?.trimmingCharacters(in: .whitespacesAndNewlines), let url = URL(string: safeCloudUrl) {
                        // Limit batch RAM footprint by streaming and downsampling if it was massive, but here we fall back to generic data mapping since these are small cloud thumbnails
                        if let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) {
                            items.append(image)
                        }
                    }
                }
            }
            
            await MainActor.run { presentShareSheet(items) }
        }
    }
}
