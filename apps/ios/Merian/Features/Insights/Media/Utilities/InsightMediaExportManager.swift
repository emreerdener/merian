import SwiftUI

enum ApprovedRemoteMedia {
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

enum ExportMediaURLResolver {
    static func localURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed)
        }
        if let url = URL(string: trimmed), url.isFileURL {
            return url
        }
        if URLComponents(string: trimmed)?.scheme != nil {
            return nil
        }
        return URL.documentsDirectory.appendingPathComponent(trimmed)
    }
}

struct MediaSaveResult: Sendable, Equatable {
    private(set) var photosAttempted = 0
    private(set) var photosSaved = 0
    private(set) var videosAttempted = 0
    private(set) var videosSaved = 0

    var totalAttempted: Int {
        photosAttempted + videosAttempted
    }

    var totalSaved: Int {
        photosSaved + videosSaved
    }

    var hasFailures: Bool {
        totalSaved < totalAttempted
    }

    var successMessage: String {
        var components: [String] = []
        if photosSaved > 0 {
            components.append("\(photosSaved) photo\(photosSaved == 1 ? "" : "s")")
        }
        if videosSaved > 0 {
            components.append("\(videosSaved) video\(videosSaved == 1 ? "" : "s")")
        }

        let savedDescription: String
        if components.count == 2 {
            savedDescription = "\(components[0]) and \(components[1])"
        } else {
            savedDescription = components.first ?? "media"
        }

        let baseMessage = "Saved \(savedDescription) to your camera roll."
        return hasFailures ? "\(baseMessage) Some items couldn't be saved." : baseMessage
    }

    mutating func record(_ mediaKind: PhotoLibraryMediaKind, success: Bool) {
        switch mediaKind {
        case .photo:
            photosAttempted += 1
            if success { photosSaved += 1 }
        case .video:
            videosAttempted += 1
            if success { videosSaved += 1 }
        }
    }

    mutating func merge(_ other: MediaSaveResult) {
        photosAttempted += other.photosAttempted
        photosSaved += other.photosSaved
        videosAttempted += other.videosAttempted
        videosSaved += other.videosSaved
    }
}

// MARK: - Core Discovery Media Export Engine
@MainActor
final class InsightMediaExportManager {
    // MARK: - Singleton
    static let shared = InsightMediaExportManager()
    
    // MARK: - Single Item Export
    func saveUserMedia(
        liveData: Data?,
        imagePaths: [String],
        videoPaths: [String],
        referenceImageUrl: String?,
        completion: @escaping (MediaSaveResult) -> Void
    ) {
        let payload = Self.makeSaveMediaPayload(
            imagePaths: imagePaths,
            videoPaths: videoPaths,
            referenceImageUrl: referenceImageUrl
        )

        Task {
            let result = await ExportProcessingActor.shared.saveUserMedia(
                liveData: liveData,
                payload: payload
            )
            completion(result)
        }
    }
    
    // MARK: - Single Item Sharing
    func shareDiscovery(commonName: String, scientificName: String, liveData: Data?, historicPath: String?, referenceImageUrl: String?, presentShareSheet: @escaping ([Any]) -> Void) {
        var items: [Any] = [
            "Check out this \(commonName) (\(scientificName)) I discovered using Naturebook!"
        ]
        let historicRemoteURLs = ApprovedRemoteMedia.urls(from: historicPath)
        let historicLocalPath = historicRemoteURLs.isEmpty ? historicPath : nil
        let safeCloudURLs = historicRemoteURLs + ApprovedRemoteMedia.urls(from: referenceImageUrl)
        
        Task {
            let extractedImage = await ExportProcessingActor.shared.extractImage(liveData: liveData, historicPath: historicLocalPath)
            
            if let image = extractedImage {
                items.insert(image, at: 0)
            } else {
                for safeCloudURL in safeCloudURLs {
                    if let remoteImage = await ExportProcessingActor.shared.extractRemoteImage(from: safeCloudURL, maxSize: 2048) {
                        items.insert(remoteImage, at: 0)
                        break
                    }
                }
            }

            await MainActor.run { presentShareSheet(items) }
        }
    }

    // MARK: - Sendable Transport Payloads
    struct SaveMediaPayload: Sendable, Equatable {
        let localImageURLs: [URL]
        let approvedRemotePhotoURLs: [URL]
        let localVideoURLs: [URL]
        let approvedRemoteVideoURLs: [URL]
    }

    struct SharePayload: Sendable {
        let commonName: String
        let scientificName: String
        let localImagePath: String?
        let approvedRemoteURLs: [URL]
    }

    // MARK: - Batch Item Export
    func batchSaveUserMedia(
        records: [LocalScanRecord],
        completion: @escaping (MediaSaveResult) -> Void
    ) {
        let payloads = records.map { scan -> SaveMediaPayload in
            let media = scan.capturedMediaSnapshot.activeScanMedia
            return Self.makeSaveMediaPayload(
                imagePaths: media.imagePathsForUpload,
                videoPaths: media.videoPaths,
                referenceImageUrl: scan.referenceImageUrl
            )
        }
        
        Task {
            let result = await ExportProcessingActor.shared.batchSaveUserMedia(payloads: payloads)
            completion(result)
        }
    }

    nonisolated static func makeSaveMediaPayload(
        imagePaths: [String],
        videoPaths: [String],
        referenceImageUrl: String?
    ) -> SaveMediaPayload {
        SaveMediaPayload(
            localImageURLs: imagePaths.compactMap { path in
                guard ApprovedRemoteMedia.firstURL(from: path) == nil else { return nil }
                return ExportMediaURLResolver.localURL(from: path)
            },
            approvedRemotePhotoURLs: imagePaths.flatMap { ApprovedRemoteMedia.urls(from: $0) }
                + ApprovedRemoteMedia.urls(from: referenceImageUrl),
            localVideoURLs: videoPaths.compactMap { path in
                guard ApprovedRemoteMedia.firstURL(from: path) == nil else { return nil }
                return ExportMediaURLResolver.localURL(from: path)
            },
            approvedRemoteVideoURLs: videoPaths.flatMap { ApprovedRemoteMedia.urls(from: $0) }
        )
    }
    
    // MARK: - Batch Item Sharing
    func batchShareDiscovery(records: [LocalScanRecord], presentShareSheet: @escaping ([Any]) -> Void) {
        let payloads = records.map { scan -> SharePayload in
            let path = scan.capturedMediaSnapshot.primaryImagePath
            let petLabel = scan.petIdentification?.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let commonName: String
            if let petLabel, !petLabel.isEmpty {
                commonName = petLabel
            } else {
                commonName = scan.commonName
            }
            return SharePayload(
                commonName: commonName,
                scientificName: scan.scientificName,
                localImagePath: path,
                approvedRemoteURLs: ApprovedRemoteMedia.urls(from: scan.referenceImageUrl)
            )
        }
        
        Task {
            var items: [Any] = []
            
            if payloads.count == 1 {
                let p = payloads[0]
                items.append("Check out this \(p.commonName) (\(p.scientificName)) I discovered using Naturebook!\n\(PublicBrand.websiteURL.absoluteString)")
            } else if payloads.count > 1 {
                var message = "Check out these \(payloads.count) discoveries I made using Naturebook!\n"
                let displayLimit = 10
                for (index, p) in payloads.enumerated() {
                    if index < displayLimit {
                        message += "• \(p.commonName) (\(p.scientificName))\n"
                    } else if index == displayLimit {
                        message += "• ...and \(payloads.count - displayLimit) more!\n"
                        break
                    }
                }
                message += "\n\(PublicBrand.websiteURL.absoluteString)"
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
    
    func saveUserMedia(
        liveData: Data?,
        payload: InsightMediaExportManager.SaveMediaPayload
    ) async -> MediaSaveResult {
        await saveMedia(liveData: liveData, payload: payload)
    }

    func batchSaveUserMedia(
        payloads: [InsightMediaExportManager.SaveMediaPayload]
    ) async -> MediaSaveResult {
        var result = MediaSaveResult()

        for payload in payloads {
            result.merge(await saveMedia(liveData: nil, payload: payload))
        }
        return result
    }

    private func saveMedia(
        liveData: Data?,
        payload: InsightMediaExportManager.SaveMediaPayload
    ) async -> MediaSaveResult {
        var result = MediaSaveResult()
        
        if let data = liveData {
            let success = await PhotoLibraryManager.shared.saveImageManual(imageData: data)
            result.record(.photo, success: success)
        }
        
        for url in payload.localImageURLs {
            let success = await PhotoLibraryManager.shared.saveImageManual(fileURL: url)
            result.record(.photo, success: success)
        }

        result.merge(await saveApprovedRemoteMedia(
            from: payload.approvedRemotePhotoURLs,
            mediaKind: .photo
        ))

        for url in payload.localVideoURLs {
            let success = await PhotoLibraryManager.shared.saveVideoManual(fileURL: url)
            result.record(.video, success: success)
        }

        result.merge(await saveApprovedRemoteMedia(
            from: payload.approvedRemoteVideoURLs,
            mediaKind: .video
        ))

        return result
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

    private func saveApprovedRemoteMedia(
        from remoteURLs: [URL],
        mediaKind: PhotoLibraryMediaKind
    ) async -> MediaSaveResult {
        var result = MediaSaveResult()

        for remoteURL in remoteURLs {
            let success: Bool
            do {
                let (fileURL, response) = try await ExportProcessingActor.mediaSession.download(from: remoteURL)
                defer { try? FileManager.default.removeItem(at: fileURL) }

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    result.record(mediaKind, success: false)
                    continue
                }

                switch mediaKind {
                case .photo:
                    success = await PhotoLibraryManager.shared.saveImageManual(fileURL: fileURL)
                case .video:
                    success = await PhotoLibraryManager.shared.saveVideoManual(fileURL: fileURL)
                }
            } catch {
                MerianLog.network.error("Failed to download R2 media asset: \(error, privacy: .private)")
                result.record(mediaKind, success: false)
                continue
            }
            result.record(mediaKind, success: success)
        }

        return result
    }
}
