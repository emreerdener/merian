import SwiftUI

// MARK: - Core Discovery Media Export Engine
@MainActor
final class InsightMediaExportManager {
    // MARK: - Singleton
    static let shared = InsightMediaExportManager()
    
    // MARK: - Single Item Export
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
    
    // MARK: - Single Item Sharing
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
    
    // MARK: - Sendable Transport Payloads
    struct SavePhotosPayload: Sendable {
        let localImagePath: String?
        let additionalImagePaths: [String]?
        let referenceImageUrl: String?
    }

    struct SharePayload: Sendable {
        let commonName: String
        let scientificName: String
        let localImagePath: String?
        let referenceImageUrl: String?
    }

    // MARK: - Batch Item Export
    func batchSaveUserPhotos(records: [LocalScanRecord], completion: @escaping (Int) -> Void) {
        let payloads = records.map { SavePhotosPayload(localImagePath: $0.localImagePath, additionalImagePaths: $0.additionalImagePaths, referenceImageUrl: $0.referenceImageUrl) }
        
        Task.detached(priority: .userInitiated) {
            var photosSaved = 0
            
            for payload in payloads {
                var validPaths: [String] = []
                if let p = payload.localImagePath { validPaths.append(p) }
                if let extras = payload.additionalImagePaths { validPaths.append(contentsOf: extras) }
                
                // 1. Local historical images securely cached on disk
                for path in validPaths {
                    let url = URL.documentsDirectory.appendingPathComponent(path)
                    if let data = try? Data(contentsOf: url) {
                        let success = await PhotoLibraryManager.shared.saveImageManual(imageData: data)
                        if success { photosSaved += 1 }
                    }
                }
                
                // 2. Remote user uploads explicitly filtering out GBIF/Wiki bounds
                let refUrls = payload.referenceImageUrl?.components(separatedBy: ",").filter { !$0.isEmpty } ?? []
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
            }
            
            let finalPhotosSaved = photosSaved
            await MainActor.run {
                completion(finalPhotosSaved)
            }
        }
    }
    
    // MARK: - Batch Item Sharing
    func batchShareDiscovery(records: [LocalScanRecord], presentShareSheet: @escaping ([Any]) -> Void) {
        let payloads = records.map { SharePayload(commonName: $0.commonName, scientificName: $0.scientificName, localImagePath: $0.localImagePath, referenceImageUrl: $0.referenceImageUrl) }
        
        Task {
            var items: [Any] = []
            
            if payloads.count == 1 {
                let p = payloads[0]
                items.append("Check out this \(p.commonName) (\(p.scientificName)) I discovered using Merian!\nhttps://merian.app")
            } else if payloads.count > 1 {
                var message = "Check out these \(payloads.count) discoveries I made using Merian!\n"
                let displayLimit = 10
                for (index, p) in payloads.enumerated() {
                    if index < displayLimit {
                        message += "• \(p.commonName) (\(p.scientificName))\n"
                    } else if index == displayLimit {
                        message += "• ...and \(payloads.count - displayLimit) more!\n"
                        break
                    }
                }
                message += "\nhttps://merian.app"
                items.append(message)
            }
            
            for payload in payloads {
                let extractedImage = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                    if let validPath = payload.localImagePath {
                        let fileURL = URL.documentsDirectory.appendingPathComponent(validPath)
                        if let cgImage = ImageDownsampler.downsample(url: fileURL, maxSize: 1024) {
                            return UIImage(cgImage: cgImage)
                        }
                    }
                    return nil
                }.value
                
                if let image = extractedImage {
                    items.append(image)
                } else {
                    let refUrls = payload.referenceImageUrl?.components(separatedBy: ",").filter { !$0.isEmpty } ?? []
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
