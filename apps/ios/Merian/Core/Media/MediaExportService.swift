import Foundation
import UIKit

enum MediaExportSource: Sendable, Equatable {
    case local(URL)
    case approvedRemote(URL)
}

enum MediaExportSourceResolver {
    private static let approvedRemoteHosts: Set<String> = [
        "media.merian.app"
    ]

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

    static func approvedRemoteURLs(from rawValue: String?) -> [URL] {
        guard let rawValue else { return [] }

        return rawValue
            .components(separatedBy: ",")
            .compactMap { segment in
                let trimmed = segment.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard !trimmed.isEmpty,
                      let url = SecureTransportPolicy.httpsURL(from: trimmed),
                      isApprovedRemoteURL(url) else {
                    return nil
                }
                return url
            }
    }

    static func isApprovedRemoteURL(_ url: URL?) -> Bool {
        guard let url,
              SecureTransportPolicy.isSecureRemoteURL(url),
              let host = url.host?.lowercased() else {
            return false
        }
        return approvedRemoteHosts.contains(host)
    }

    static func approvedRedirectRequest(
        _ request: URLRequest
    ) -> URLRequest? {
        guard isApprovedRemoteURL(request.url) else { return nil }
        return request
    }

    static func sources(from rawValue: String?) -> [MediaExportSource] {
        guard let rawValue else { return [] }
        let remoteURLs = approvedRemoteURLs(from: rawValue)
        if !remoteURLs.isEmpty {
            return remoteURLs.map(MediaExportSource.approvedRemote)
        }
        guard let localURL = localURL(from: rawValue) else { return [] }
        return [.local(localURL)]
    }
}

enum MediaExportSizingPolicy {
    static let singleShareMaxPixelSize: CGFloat = 2_048
    static let batchShareMaxPixelSize: CGFloat = 1_024
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
            components.append(
                "\(photosSaved) photo\(photosSaved == 1 ? "" : "s")"
            )
        }
        if videosSaved > 0 {
            components.append(
                "\(videosSaved) video\(videosSaved == 1 ? "" : "s")"
            )
        }

        let savedDescription: String
        if components.count == 2 {
            savedDescription = "\(components[0]) and \(components[1])"
        } else {
            savedDescription = components.first ?? "media"
        }

        let baseMessage = "Saved \(savedDescription) to your camera roll."
        return hasFailures
            ? "\(baseMessage) Some items couldn't be saved."
            : baseMessage
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

struct MediaSaveRequest: Sendable, Equatable {
    let liveImageData: Data?
    let photoSources: [MediaExportSource]
    let videoSources: [MediaExportSource]

    static func make(
        liveImageData: Data?,
        imagePaths: [String],
        videoPaths: [String],
        referenceImageURL: String?
    ) -> Self {
        let referenceSources = MediaExportSourceResolver
            .approvedRemoteURLs(from: referenceImageURL)
            .map(MediaExportSource.approvedRemote)
        return Self(
            liveImageData: liveImageData,
            photoSources: imagePaths.flatMap {
                MediaExportSourceResolver.sources(from: $0)
            } + referenceSources,
            videoSources: videoPaths.flatMap {
                MediaExportSourceResolver.sources(from: $0)
            }
        )
    }
}

struct DiscoveryShareRequest: Sendable, Equatable {
    let message: String
    let liveImageData: Data?
    let imageSources: [MediaExportSource]

    static func make(
        commonName: String,
        scientificName: String,
        liveImageData: Data?,
        primaryImageReference: String?,
        fallbackImageReference: String?
    ) -> Self {
        Self(
            message: "Check out this \(commonName) (\(scientificName)) I discovered using Naturebook!",
            liveImageData: liveImageData,
            imageSources: MediaExportSourceResolver.sources(
                from: primaryImageReference
            ) + MediaExportSourceResolver.approvedRemoteURLs(
                from: fallbackImageReference
            ).map(MediaExportSource.approvedRemote)
        )
    }
}

struct BatchDiscoveryShareRequest: Sendable, Equatable {
    struct Discovery: Sendable, Equatable {
        let commonName: String
        let scientificName: String
        let imageSources: [MediaExportSource]

        init(
            commonName: String,
            scientificName: String,
            primaryImageReference: String?,
            fallbackImageReference: String?
        ) {
            self.commonName = commonName
            self.scientificName = scientificName
            self.imageSources = MediaExportSourceResolver.sources(
                from: primaryImageReference
            ) + MediaExportSourceResolver.approvedRemoteURLs(
                from: fallbackImageReference
            ).map(MediaExportSource.approvedRemote)
        }
    }

    let discoveries: [Discovery]

    var message: String {
        guard discoveries.count != 1 else {
            let discovery = discoveries[0]
            return "Check out this \(discovery.commonName) (\(discovery.scientificName)) I discovered using Naturebook!\n\(PublicBrand.websiteURL.absoluteString)"
        }

        var result = "Check out these \(discoveries.count) discoveries I made using Naturebook!\n"
        let displayLimit = 10
        for (index, discovery) in discoveries.enumerated() {
            if index < displayLimit {
                result += "• \(discovery.commonName) (\(discovery.scientificName))\n"
            } else if index == displayLimit {
                result += "• ...and \(discoveries.count - displayLimit) more!\n"
                break
            }
        }
        result += "\n\(PublicBrand.websiteURL.absoluteString)"
        return result
    }
}

enum MediaShareItem: Sendable {
    case image(SendableCGImage)
    case text(String)
}

struct MediaSharePayload: Sendable {
    let items: [MediaShareItem]

    @MainActor
    var activityItems: [Any] {
        items.map { item in
            switch item {
            case .image(let image):
                UIImage(cgImage: image.image)
            case .text(let text):
                text
            }
        }
    }
}

struct MediaExportService: Sendable {
    let save: @Sendable (MediaSaveRequest) async -> MediaSaveResult
    let batchSave: @Sendable ([MediaSaveRequest]) async -> MediaSaveResult
    let prepareShare: @Sendable (DiscoveryShareRequest) async -> MediaSharePayload
    let prepareBatchShare: @Sendable (
        BatchDiscoveryShareRequest
    ) async -> MediaSharePayload

    static var live: Self {
        let processor = MediaExportProcessor()
        return Self(
            save: { await processor.save($0) },
            batchSave: { await processor.batchSave($0) },
            prepareShare: { await processor.prepareShare($0) },
            prepareBatchShare: { await processor.prepareBatchShare($0) }
        )
    }
}

private final class MediaExportSessionDelegate:
    NSObject,
    URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(
            MediaExportSourceResolver.approvedRedirectRequest(request)
        )
    }
}

private actor MediaExportProcessor {
    private let mediaSession: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        self.mediaSession = URLSession(
            configuration: configuration,
            delegate: MediaExportSessionDelegate(),
            delegateQueue: nil
        )
    }

    func save(_ request: MediaSaveRequest) async -> MediaSaveResult {
        var result = MediaSaveResult()

        if let liveImageData = request.liveImageData, !Task.isCancelled {
            let success = await PhotoLibraryManager.shared.saveImageManual(
                imageData: liveImageData
            )
            result.record(.photo, success: success)
        }

        result.merge(await save(request.photoSources, as: .photo))
        result.merge(await save(request.videoSources, as: .video))
        return result
    }

    func batchSave(_ requests: [MediaSaveRequest]) async -> MediaSaveResult {
        var result = MediaSaveResult()
        for request in requests {
            guard !Task.isCancelled else { break }
            result.merge(await save(request))
        }
        return result
    }

    func prepareShare(_ request: DiscoveryShareRequest) async -> MediaSharePayload {
        if let image = await firstImage(
            liveImageData: request.liveImageData,
            sources: request.imageSources,
            maxSize: MediaExportSizingPolicy.singleShareMaxPixelSize
        ) {
            return MediaSharePayload(items: [.image(image), .text(request.message)])
        }
        return MediaSharePayload(items: [.text(request.message)])
    }

    func prepareBatchShare(
        _ request: BatchDiscoveryShareRequest
    ) async -> MediaSharePayload {
        var items: [MediaShareItem] = [.text(request.message)]
        for discovery in request.discoveries {
            guard !Task.isCancelled else { break }
            if let image = await firstImage(
                liveImageData: nil,
                sources: discovery.imageSources,
                maxSize: MediaExportSizingPolicy.batchShareMaxPixelSize
            ) {
                items.append(.image(image))
            }
        }
        return MediaSharePayload(items: items)
    }

    private func save(
        _ sources: [MediaExportSource],
        as mediaKind: PhotoLibraryMediaKind
    ) async -> MediaSaveResult {
        var result = MediaSaveResult()
        for source in sources {
            guard !Task.isCancelled else { break }
            let success: Bool
            switch source {
            case .local(let fileURL):
                success = await saveLocal(fileURL, as: mediaKind)
            case .approvedRemote(let remoteURL):
                success = await saveRemote(remoteURL, as: mediaKind)
            }
            result.record(mediaKind, success: success)
        }
        return result
    }

    private func saveLocal(
        _ fileURL: URL,
        as mediaKind: PhotoLibraryMediaKind
    ) async -> Bool {
        switch mediaKind {
        case .photo:
            await PhotoLibraryManager.shared.saveImageManual(fileURL: fileURL)
        case .video:
            await PhotoLibraryManager.shared.saveVideoManual(fileURL: fileURL)
        }
    }

    private func saveRemote(
        _ remoteURL: URL,
        as mediaKind: PhotoLibraryMediaKind
    ) async -> Bool {
        guard MediaExportSourceResolver.isApprovedRemoteURL(remoteURL) else {
            return false
        }
        do {
            let (fileURL, response) = try await mediaSession.download(
                from: remoteURL
            )
            defer { try? FileManager.default.removeItem(at: fileURL) }
            guard !Task.isCancelled,
                  let httpResponse = response as? HTTPURLResponse,
                  MediaExportSourceResolver.isApprovedRemoteURL(
                      httpResponse.url
                  ),
                  (200...299).contains(httpResponse.statusCode) else {
                return false
            }
            return await saveLocal(fileURL, as: mediaKind)
        } catch is CancellationError {
            return false
        } catch {
            MerianLog.network.error(
                "Failed to download remote media asset: \(error, privacy: .private)"
            )
            return false
        }
    }

    private func firstImage(
        liveImageData: Data?,
        sources: [MediaExportSource],
        maxSize: CGFloat
    ) async -> SendableCGImage? {
        if let liveImageData,
           let image = ImageDownsampler.downsample(
               data: liveImageData,
               maxSize: maxSize
           ) {
            return SendableCGImage(image: image)
        }

        for source in sources {
            guard !Task.isCancelled else { return nil }
            let image: CGImage?
            switch source {
            case .local(let fileURL):
                image = ImageDownsampler.downsample(
                    url: fileURL,
                    maxSize: maxSize
                )
            case .approvedRemote(let remoteURL):
                image = await remoteImage(from: remoteURL, maxSize: maxSize)
            }
            if let image {
                return SendableCGImage(image: image)
            }
        }
        return nil
    }

    private func remoteImage(
        from remoteURL: URL,
        maxSize: CGFloat
    ) async -> CGImage? {
        guard MediaExportSourceResolver.isApprovedRemoteURL(remoteURL) else {
            return nil
        }
        do {
            let (fileURL, response) = try await mediaSession.download(
                from: remoteURL
            )
            defer { try? FileManager.default.removeItem(at: fileURL) }
            guard !Task.isCancelled,
                  let httpResponse = response as? HTTPURLResponse,
                  MediaExportSourceResolver.isApprovedRemoteURL(
                      httpResponse.url
                  ),
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            return ImageDownsampler.downsample(url: fileURL, maxSize: maxSize)
        } catch is CancellationError {
            return nil
        } catch {
            MerianLog.network.error(
                "Failed to download remote media preview: \(error, privacy: .private)"
            )
            return nil
        }
    }
}
