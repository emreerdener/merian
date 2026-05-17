import SwiftUI

private enum ApprovedRemoteMedia {
    private static let approvedHosts: Set<String> = ["media.merian.app"]

    static func urls(from rawValue: String?) -> [URL] {
        guard let rawValue else { return [] }

        return rawValue
            .components(separatedBy: ",")
            .compactMap { segment in
                let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty,
                      let components = URLComponents(string: trimmed),
                      components.scheme?.lowercased() == "https",
                      let host = components.host?.lowercased(),
                      approvedHosts.contains(host),
                      let url = components.url else {
                    return nil
                }
                return url
            }
    }

    static func firstURL(from rawValue: String?) -> URL? {
        urls(from: rawValue).first
    }
}

// MARK: - Core Discovery Media Export Engine
@MainActor
final class InsightMediaExportManager {
    // MARK: - Singleton
    static let shared = InsightMediaExportManager()
    
    // MARK: - Single Item Export
    func saveUserPhotos(liveData: Data?, validPaths: [String], referenceImageUrl: String?, completion: @escaping (Int) -> Void) {
        let approvedRemoteURLs = ApprovedRemoteMedia.urls(from: referenceImageUrl)
        
        Task {
            let photosSaved = await ExportProcessingActor.shared.saveUserPhotos(
                liveData: liveData,
                validPaths: validPaths,
                remoteURLs: approvedRemoteURLs
            )
            completion(photosSaved)
        }
    }
    
    // MARK: - Single Item Sharing
    func shareDiscovery(commonName: String, scientificName: String, liveData: Data?, historicPath: String?, referenceImageUrl: String?, presentShareSheet: @escaping ([Any]) -> Void) {
        var items: [Any] = [
            "Check out this \(commonName) (\(scientificName)) I discovered using Merian!"
        ]
        let safeCloudURL = ApprovedRemoteMedia.firstURL(from: referenceImageUrl)
        
        Task {
            let extractedImage = await ExportProcessingActor.shared.extractImage(liveData: liveData, historicPath: historicPath)
            
            if let image = extractedImage {
                items.insert(image, at: 0)
                await MainActor.run { presentShareSheet(items) }
            } else if let safeCloudURL,
                      let remoteImage = await ExportProcessingActor.shared.extractRemoteImage(from: safeCloudURL, maxSize: 2048) {
                items.insert(remoteImage, at: 0)
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
        let approvedRemoteURLs: [URL]
    }

    struct SharePayload: Sendable {
        let commonName: String
        let scientificName: String
        let localImagePath: String?
        let approvedRemoteURLs: [URL]
    }

    // MARK: - Batch Item Export
    func batchSaveUserPhotos(records: [LocalScanRecord], completion: @escaping (Int) -> Void) {
        let payloads = records.map { scan -> SavePhotosPayload in
            let paths = scan.capturedMediaSnapshot.imagePaths
            return SavePhotosPayload(
                localImagePath: paths.first,
                additionalImagePaths: paths.count > 1 ? Array(paths.dropFirst()) : nil,
                approvedRemoteURLs: ApprovedRemoteMedia.urls(from: scan.referenceImageUrl)
            )
        }
        
        Task {
            let photosSaved = await ExportProcessingActor.shared.batchSaveUserPhotos(payloads: payloads)
            completion(photosSaved)
        }
    }
    
    // MARK: - Batch Item Sharing
    func batchShareDiscovery(records: [LocalScanRecord], presentShareSheet: @escaping ([Any]) -> Void) {
        let payloads = records.map { scan -> SharePayload in
            let path = scan.capturedMediaSnapshot.primaryImagePath
            return SharePayload(
                commonName: scan.commonName,
                scientificName: scan.scientificName,
                localImagePath: path,
                approvedRemoteURLs: ApprovedRemoteMedia.urls(from: scan.referenceImageUrl)
            )
        }
        
        Task {
            var items: [Any] = []
            
            if payloads.count == 1 {
                let p = payloads[0]
                items.append("Check out this \(p.commonName) (\(p.scientificName)) I discovered using Merian!\nhttps://merian.earth")
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
                message += "\nhttps://merian.earth"
                items.append(message)
            }
            
            for payload in payloads {
                let extractedImage = await ExportProcessingActor.shared.extractThumbnail(from: payload.localImagePath)
                
                if let image = extractedImage {
                    items.append(image)
                } else if let safeCloudURL = payload.approvedRemoteURLs.first,
                          let remoteImage = await ExportProcessingActor.shared.extractRemoteImage(from: safeCloudURL, maxSize: 2048) {
                    items.append(remoteImage)
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
    
    func saveUserPhotos(liveData: Data?, validPaths: [String], remoteURLs: [URL]) async -> Int {
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

        photosSaved += await saveApprovedRemotePhotos(from: remoteURLs)
        
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

            photosSaved += await saveApprovedRemotePhotos(from: payload.approvedRemoteURLs)
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

    func extractRemoteImage(from remoteURL: URL, maxSize: CGFloat) async -> UIImage? {
        do {
            let (data, response) = try await ExportProcessingActor.mediaSession.data(from: remoteURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            return autoreleasepool {
                guard let cgImage = ImageDownsampler.downsample(data: data, maxSize: maxSize) else {
                    return nil
                }
                return UIImage(cgImage: cgImage)
            }
        } catch {
            MerianLog.network.error("Failed to download remote media preview: \(error, privacy: .private)")
            return nil
        }
    }

    private func saveApprovedRemotePhotos(from remoteURLs: [URL]) async -> Int {
        var photosSaved = 0

        for remoteURL in remoteURLs {
            do {
                let (fileURL, response) = try await ExportProcessingActor.mediaSession.download(from: remoteURL)
                defer { try? FileManager.default.removeItem(at: fileURL) }

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    continue
                }

                let success = await PhotoLibraryManager.shared.saveImageManual(fileURL: fileURL)
                if success { photosSaved += 1 }
            } catch {
                MerianLog.network.error("Failed to download R2 media asset: \(error, privacy: .private)")
            }
        }

        return photosSaved
    }
}
