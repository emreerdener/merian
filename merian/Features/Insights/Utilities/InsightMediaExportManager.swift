import SwiftUI

// MARK: - Core Discovery Media Export Engine
@MainActor
final class InsightMediaExportManager {
    // MARK: - Singleton
    static let shared = InsightMediaExportManager()

    // Isolated session for downloading R2/Cloudflare media payloads during share/export operations.
    private static let mediaSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()
    
    // MARK: - Single Item Export
    func saveUserPhotos(liveData: Data?, validPaths: [String], referenceImageUrl: String?, completion: @escaping (Int) -> Void) {
        let refUrls: [String] = referenceImageUrl?.components(separatedBy: ",").filter { !$0.isEmpty } ?? []
        
        Task {
            let photosSaved = await ExportProcessingActor.shared.saveUserPhotos(
                liveData: liveData,
                validPaths: validPaths,
                refUrls: refUrls
            )
            completion(photosSaved)
        }
    }
    
    // MARK: - Single Item Sharing
    func shareDiscovery(commonName: String, scientificName: String, liveData: Data?, historicPath: String?, referenceImageUrl: String?, presentShareSheet: @escaping ([Any]) -> Void) {
        var items: [Any] = [
            "Check out this \(commonName) (\(scientificName)) I discovered using Merian!"
        ]
        
        let refUrls: [String] = referenceImageUrl?.components(separatedBy: ",").filter { !$0.isEmpty } ?? []
        let safeCloudUrl = refUrls.first(where: { $0.contains("merian.app") })?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        Task {
            let extractedImage = await ExportProcessingActor.shared.extractImage(liveData: liveData, historicPath: historicPath)
            
            if let image = extractedImage {
                items.insert(image, at: 0)
                await MainActor.run { presentShareSheet(items) }
            } else if let urlStr = safeCloudUrl, let url = URL(string: urlStr) {
                if let (data, _) = try? await InsightMediaExportManager.mediaSession.data(from: url),
                   let cgImage = autoreleasepool(invoking: { ImageDownsampler.downsample(data: data, maxSize: 2048) }) {
                    items.insert(UIImage(cgImage: cgImage), at: 0)
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
        let payloads = records.map { scan -> SavePhotosPayload in
            let paths = scan.capturedMediaJSON.map(MediaJSONParser.imagePaths(jsonString:)) ?? []
            return SavePhotosPayload(localImagePath: paths.first, additionalImagePaths: paths.count > 1 ? Array(paths.dropFirst()) : nil, referenceImageUrl: scan.referenceImageUrl)
        }
        
        Task {
            let photosSaved = await ExportProcessingActor.shared.batchSaveUserPhotos(payloads: payloads)
            completion(photosSaved)
        }
    }
    
    // MARK: - Batch Item Sharing
    func batchShareDiscovery(records: [LocalScanRecord], presentShareSheet: @escaping ([Any]) -> Void) {
        let payloads = records.map { scan -> SharePayload in
            let path = scan.capturedMediaJSON.flatMap(MediaJSONParser.primaryImagePath(jsonString:))
            return SharePayload(commonName: scan.commonName, scientificName: scan.scientificName, localImagePath: path, referenceImageUrl: scan.referenceImageUrl)
        }
        
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
                let extractedImage = await ExportProcessingActor.shared.extractThumbnail(from: payload.localImagePath)
                
                if let image = extractedImage {
                    items.append(image)
                } else {
                    let refUrls = payload.referenceImageUrl?.components(separatedBy: ",").filter { !$0.isEmpty } ?? []
                    if let safeCloudUrl = refUrls.first(where: { $0.contains("merian.app") })?.trimmingCharacters(in: .whitespacesAndNewlines), let url = URL(string: safeCloudUrl) {
                        // Limit batch RAM footprint by streaming and downsampling if it was massive, but here we fall back to generic data mapping since these are small cloud thumbnails
                        if let (data, _) = try? await InsightMediaExportManager.mediaSession.data(from: url),
                           let cgImage = autoreleasepool(invoking: { ImageDownsampler.downsample(data: data, maxSize: 2048) }) {
                            items.append(UIImage(cgImage: cgImage))
                        }
                    }
                }
            }
            
            await MainActor.run { presentShareSheet(items) }
        }
    }
}

// MARK: - Dedicated Processing Actor
actor ExportProcessingActor {
    static let shared = ExportProcessingActor()

    // Isolated session for downloading R2 media for photo-library saves and batch exports.
    private static let mediaSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()
    
    func saveUserPhotos(liveData: Data?, validPaths: [String], refUrls: [String]) async -> Int {
        var photosSaved = 0
        
        if let data = liveData {
            let success = await PhotoLibraryManager.shared.saveImageManual(imageData: data)
            if success { photosSaved += 1 }
        }
        
        for path in validPaths {
            let url = URL.documentsDirectory.appendingPathComponent(path)
            let success = await PhotoLibraryManager.shared.saveImageManual(fileURL: url)
            if success { photosSaved += 1 }
        }
        
        for urlStr in refUrls {
            let cleanStr = urlStr.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanStr.contains("merian.app"), let url = URL(string: cleanStr) {
                do {
                    let (fileURL, _) = try await ExportProcessingActor.mediaSession.download(from: url)
                    let success = await PhotoLibraryManager.shared.saveImageManual(fileURL: fileURL)
                    if success { photosSaved += 1 }
                    try? FileManager.default.removeItem(at: fileURL)
                } catch {
                    MerianLog.network.error("Failed to download R2 media asset: \(error, privacy: .private)")
                }
            }
        }
        
        return photosSaved
    }
    
    func batchSaveUserPhotos(payloads: [InsightMediaExportManager.SavePhotosPayload]) async -> Int {
        var photosSaved = 0
        
        for payload in payloads {
            var validPaths: [String] = []
            if let p = payload.localImagePath { validPaths.append(p) }
            if let extras = payload.additionalImagePaths { validPaths.append(contentsOf: extras) }
            
            for path in validPaths {
                let url = URL.documentsDirectory.appendingPathComponent(path)
                let success = await PhotoLibraryManager.shared.saveImageManual(fileURL: url)
                if success { photosSaved += 1 }
            }
            
            let refUrls = payload.referenceImageUrl?.components(separatedBy: ",").filter { !$0.isEmpty } ?? []
            for urlStr in refUrls {
                let cleanStr = urlStr.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleanStr.contains("merian.app"), let url = URL(string: cleanStr) {
                    do {
                        let (fileURL, _) = try await ExportProcessingActor.mediaSession.download(from: url)
                        let success = await PhotoLibraryManager.shared.saveImageManual(fileURL: fileURL)
                        if success { photosSaved += 1 }
                        try? FileManager.default.removeItem(at: fileURL)
                    } catch {
                        MerianLog.network.error("Failed to download R2 media asset: \(error, privacy: .private)")
                    }
                }
            }
        }
        return photosSaved
    }
    
    func extractImage(liveData: Data?, historicPath: String?) -> UIImage? {
        return autoreleasepool {
            if let live = liveData, let cgImage = ImageDownsampler.downsample(data: live, maxSize: 2048) {
                return UIImage(cgImage: cgImage)
            } else if let validPath = historicPath {
                let url = URL.documentsDirectory.appendingPathComponent(validPath)
                if let cgImage = ImageDownsampler.downsample(url: url, maxSize: 2048) {
                    return UIImage(cgImage: cgImage)
                }
            }
            return nil
        }
    }
    
    func extractThumbnail(from localPath: String?) async -> UIImage? {
        if let validPath = localPath {
            let fileURL = URL.documentsDirectory.appendingPathComponent(validPath)
            if let cgImage = ImageDownsampler.downsample(url: fileURL, maxSize: 1024) {
                return UIImage(cgImage: cgImage)
            }
        }
        return nil
    }
}
