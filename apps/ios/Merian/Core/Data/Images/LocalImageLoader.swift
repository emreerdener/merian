import CoreImage
import Foundation
import SwiftUI

enum ExternalReferenceImagePolicy {
    private static let suppressedHost = "inaturalist-open-data.s3.amazonaws.com"
    private static let suppressedPathPrefix = "/photos/605615444/"

    /// Suppresses the disturbing roadkill photo exposed by GBIF occurrence 5938154750.
    /// Matching its iNaturalist media directory also catches resized filename variants
    /// and query strings without affecting any other European wildcat imagery.
    static func isAllowed(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        return host != suppressedHost || !path.hasPrefix(suppressedPathPrefix)
    }

    static func isAllowed(_ rawValue: String) -> Bool {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return true }
        return isAllowed(url)
    }

    static func sanitizedURL(_ rawValue: String?) -> String? {
        guard let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              isAllowed(trimmed) else {
            return nil
        }
        return trimmed
    }

    static func url(from rawValue: String?) -> URL? {
        guard let sanitized = sanitizedURL(rawValue),
              let url = URL(string: sanitized),
              isAllowed(url) else {
            return nil
        }
        return url
    }

    static func allowedURLStrings(from rawValue: String?) -> [String] {
        rawValue?
            .components(separatedBy: ",")
            .compactMap { sanitizedURL($0) } ?? []
    }

    static func sanitizedURLList(_ rawValue: String?) -> String? {
        let joined = allowedURLStrings(from: rawValue).joined(separator: ",")
        return joined.isEmpty ? nil : joined
    }
}

actor AsyncPermitPool {
    private var availablePermits: Int
    private var waiterOrder: [UUID] = []
    private var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    init(limit: Int) {
        availablePermits = max(1, limit)
    }

    func acquire() async -> Bool {
        guard !Task.isCancelled else { return false }
        if availablePermits > 0 {
            availablePermits -= 1
            return true
        }

        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: false)
                    return
                }
                waiterOrder.append(id)
                waiters[id] = continuation
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(id)
            }
        }
    }

    func release() {
        while let id = waiterOrder.first {
            waiterOrder.removeFirst()
            guard let continuation = waiters.removeValue(forKey: id) else { continue }
            continuation.resume(returning: true)
            return
        }
        availablePermits += 1
    }

    private func cancelWaiter(_ id: UUID) {
        guard let continuation = waiters.removeValue(forKey: id) else { return }
        waiterOrder.removeAll { $0 == id }
        continuation.resume(returning: false)
    }
}

enum RemoteImageRetryPolicy {
    static let maximumAttempts = 3

    static func shouldRetry(statusCode: Int) -> Bool {
        statusCode == 408 ||
            statusCode == 425 ||
            statusCode == 429 ||
            (500...599).contains(statusCode)
    }

    static func shouldRetry(urlErrorCode: URLError.Code) -> Bool {
        switch urlErrorCode {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .resourceUnavailable,
             .cannotLoadFromNetwork,
             .secureConnectionFailed,
             .badServerResponse,
             .zeroByteResource,
             .backgroundSessionWasDisconnected:
            return true
        default:
            // A reconnect changes the SwiftUI task identity and retries
            // .notConnectedToInternet without spinning while fully offline.
            return false
        }
    }

    static func delayMilliseconds(afterAttempt attempt: Int) -> Int {
        switch attempt {
        case 1: return 250
        default: return 750
        }
    }
}

private actor RemoteImageLoadDiagnostics {
    static let shared = RemoteImageLoadDiagnostics()

    private var lastLoggedAt: [String: Date] = [:]
    private let throttleInterval: TimeInterval = 30

    func recordHTTPFailure(url: URL, statusCode: Int) {
        let host = sanitizedHost(for: url)
        guard shouldLog(key: "\(host)|http|\(statusCode)") else { return }
        MerianLog.network.error(
            "LocalImageLoader: remote media HTTP failure host=\(host, privacy: .public) status=\(statusCode, privacy: .public)"
        )
    }

    func recordTransportFailure(url: URL, errorDomain: String, errorCode: Int) {
        let host = sanitizedHost(for: url)
        guard shouldLog(key: "\(host)|transport|\(errorDomain)|\(errorCode)") else { return }
        MerianLog.network.error(
            "LocalImageLoader: remote media transport failure host=\(host, privacy: .public) domain=\(errorDomain, privacy: .public) code=\(errorCode, privacy: .public)"
        )
    }

    func recordInvalidResponse(url: URL) {
        let host = sanitizedHost(for: url)
        guard shouldLog(key: "\(host)|invalid-response") else { return }
        MerianLog.network.error(
            "LocalImageLoader: remote media returned a non-HTTP response host=\(host, privacy: .public)"
        )
    }

    func recordDecodeFailure(url: URL) {
        let host = sanitizedHost(for: url)
        guard shouldLog(key: "\(host)|decode") else { return }
        MerianLog.network.error(
            "LocalImageLoader: remote media decode failed host=\(host, privacy: .public)"
        )
    }

    private func sanitizedHost(for url: URL) -> String {
        url.host?.lowercased() ?? "unknown"
    }

    private func shouldLog(key: String) -> Bool {
        let now = Date()
        if let lastLogged = lastLoggedAt[key],
           now.timeIntervalSince(lastLogged) < throttleInterval {
            return false
        }
        lastLoggedAt[key] = now
        return true
    }
}

// MARK: - Core Image Processing Engine
/// Unifies APFS file rendering, sandbox extractions, and Cloudflare R2 loading autonomously handling physical cache networks natively.
actor LocalImageLoader {
    // MARK: - Singleton Architecture
    static let shared = LocalImageLoader()
    
    // MARK: - Thread-Safe Task Queues
    private var activeTasks: [String: Task<UIImage?, Never>] = [:]

    // Suspends excess decode tasks without blocking an OS thread. ImageIO still runs on
    // an explicit QoS queue so synchronous Core Graphics work never occupies a Swift
    // cooperative-executor thread.
    private static let decodePermits = AsyncPermitPool(limit: 4)
    private static let decodeQueue = DispatchQueue(
        label: "app.merian.image-decode",
        qos: .userInitiated,
        attributes: .concurrent
    )

    // Isolated session for media downloads (R2, Wikipedia thumbnails, GBIF images).
    // Separate from URLSession.shared to avoid inheriting the system-wide pool and to
    // enforce explicit timeouts without cross-contaminating auth sessions.
    private static let mediaSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.httpMaximumConnectionsPerHost = 4
        config.httpShouldSetCookies = false
        // Explore/profile thumbnails are immutable, versioned media URLs. Keep their
        // responses across view reconstruction and app launches instead of forcing R2
        // to serve the same bytes whenever the in-memory UIImage cache is cold.
        config.requestCachePolicy = .useProtocolCachePolicy
        config.urlCache = URLCache(
            memoryCapacity: 24 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "MerianMediaCache"
        )
        return URLSession(configuration: config)
    }()
    
    // MARK: - Asset Orchestration
    func loadImage(fromPath imagePath: String?, fallbackUrl: String? = nil, maxDimension: Int = 1024) async -> UIImage? {
        let safeImagePath: String?
        if let imagePath, imagePath.lowercased().starts(with: "http") {
            safeImagePath = ExternalReferenceImagePolicy.sanitizedURL(imagePath)
        } else {
            safeImagePath = imagePath
        }
        let safeFallbackUrl = ExternalReferenceImagePolicy.sanitizedURLList(fallbackUrl)

        guard let baseKey = safeImagePath ?? safeFallbackUrl else {
            return nil
        }
        
        let cacheKey = "\(baseKey)_\(maxDimension)"
        
        // 1. RAM Cache Hit
        if let cached = ImageCache.shared.get(forKey: cacheKey) {
            return cached
        }
        
        // 2. Thundering Herd Request Coalescing
        if let existingTask = activeTasks[cacheKey] {
            return await existingTask.value
        }
        
        let fetchTask = Task.detached(priority: .userInitiated) { () -> UIImage? in
            // 3. Remote URL Execution (if 'imagePath' is actually a cloud URL payload directly)
            if let safePath = safeImagePath, safePath.lowercased().starts(with: "http"), let remoteUrl = URL(string: safePath) {
                if let networkImage = await LocalImageLoader.fetchRemote(url: remoteUrl, cacheKey: cacheKey, maxSize: CGFloat(maxDimension)) {
                    return networkImage
                }
            }
            // 4. Local File Extraction directly off Main Thread
            else if let safePath = safeImagePath, !safePath.isEmpty, !safePath.lowercased().starts(with: "http") {
                if let image = await LocalImageLoader.loadLocal(
                    path: safePath,
                    cacheKey: cacheKey,
                    maxSize: CGFloat(maxDimension)
                ) {
                    return image
                }
            }

            // 5. Explicit Network Fallback explicitly routing legacy bounds
            if let fallbackUrlString = safeFallbackUrl {
                let urls = fallbackUrlString.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .compactMap { URL(string: $0) }

                for url in urls {
                    // We intentionally do NOT check `Task.isCancelled` here because this is a
                    // detached task serving multiple coalesced callers. We want it to finish caching.
                    if let networkImage = await LocalImageLoader.fetchRemote(url: url, cacheKey: cacheKey, maxSize: CGFloat(maxDimension)) {
                        return networkImage
                    }
                }
            }

            return nil
        }
        
        activeTasks[cacheKey] = fetchTask
        
        defer {
            if activeTasks[cacheKey] == fetchTask {
                activeTasks.removeValue(forKey: cacheKey)
            }
        }
        
        return await fetchTask.value
    }
    
    // MARK: - Prefetch API

    /// Warms the in-memory cache for a leading set of thumbnails before the grid renders.
    /// Results land in ImageCache so ScanThumbnail.task gets an immediate cache hit instead
    /// of starting a cold decode after the cell becomes visible.
    ///
    /// Uses .utility priority: runs immediately and freely on background threads without
    /// competing with the main render loop or camera capture (which runs on its own
    /// DispatchQueue entirely outside the Swift concurrency thread pool).
    /// Concurrency is capped at 4 to avoid thermal spikes on older devices.
    nonisolated func prefetch(
        records: [(imagePath: String?, fallbackUrl: String?)],
        maxDimension: Int
    ) {
        Task(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                var inFlight = 0
                for record in records {
                    if inFlight >= 4 {
                        await group.next()
                        inFlight -= 1
                    }
                    group.addTask(priority: .utility) {
                        _ = await self.loadImage(
                            fromPath: record.imagePath,
                            fallbackUrl: record.fallbackUrl,
                            maxDimension: maxDimension
                        )
                    }
                    inFlight += 1
                }
            }
        }
    }

    // MARK: - Nonisolated Fetch Helpers
    // Static nonisolated functions so the Task.detached body above never re-enters the actor's
    // executor mid-operation. All I/O and CGImage work runs on the detached task's thread pool;
    // only the final ImageCache.shared.set call crosses into the cache (which is @unchecked Sendable).

    /// Decodes a local APFS file path into a UIImage without touching the actor's executor.
    private static nonisolated func loadLocal(
        path: String,
        cacheKey: String,
        maxSize: CGFloat
    ) async -> UIImage? {
        let url: URL
        if path.hasPrefix("/") {
            url = URL(fileURLWithPath: path)
        } else if let fileURL = URL(string: path), fileURL.isFileURL {
            url = fileURL
        } else {
            let filename = (path as NSString).lastPathComponent
            url = URL.documentsDirectory.appendingPathComponent(filename)
        }
        
        return await decodeImage(url: url, cacheKey: cacheKey, maxSize: maxSize)
    }

    /// Downloads a remote URL, downsamples, and caches — entirely off the actor executor.
    static nonisolated func fetchRemote(url: URL, cacheKey: String, maxSize: CGFloat = 500) async -> UIImage? {
        if Task.isCancelled || !ExternalReferenceImagePolicy.isAllowed(url) { return nil }

        for attempt in 1...RemoteImageRetryPolicy.maximumAttempts {
            if Task.isCancelled { return nil }

            do {
                var request = URLRequest(url: url)
                if attempt > 1 {
                    request.cachePolicy = .reloadIgnoringLocalCacheData
                }

                let (tempURL, response) = try await LocalImageLoader.mediaSession.download(for: request)
                defer { try? FileManager.default.removeItem(at: tempURL) }

                guard let httpResponse = response as? HTTPURLResponse else {
                    await RemoteImageLoadDiagnostics.shared.recordInvalidResponse(url: url)
                    return nil
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    if attempt < RemoteImageRetryPolicy.maximumAttempts,
                       RemoteImageRetryPolicy.shouldRetry(statusCode: httpResponse.statusCode),
                       await waitBeforeRemoteRetry(afterAttempt: attempt) {
                        continue
                    }

                    await RemoteImageLoadDiagnostics.shared.recordHTTPFailure(
                        url: url,
                        statusCode: httpResponse.statusCode
                    )
                    return nil
                }

                if Task.isCancelled { return nil }
                if let image = await decodeImage(
                    url: tempURL,
                    cacheKey: cacheKey,
                    maxSize: maxSize
                ) {
                    return image
                }

                if attempt < RemoteImageRetryPolicy.maximumAttempts,
                   await waitBeforeRemoteRetry(afterAttempt: attempt) {
                    continue
                }

                await RemoteImageLoadDiagnostics.shared.recordDecodeFailure(url: url)
                return nil
            } catch is CancellationError {
                return nil
            } catch {
                let nsError = error as NSError
                let urlErrorCode = (error as? URLError)?.code

                if attempt < RemoteImageRetryPolicy.maximumAttempts,
                   let urlErrorCode,
                   RemoteImageRetryPolicy.shouldRetry(urlErrorCode: urlErrorCode),
                   await waitBeforeRemoteRetry(afterAttempt: attempt) {
                    continue
                }

                if urlErrorCode != .cancelled {
                    await RemoteImageLoadDiagnostics.shared.recordTransportFailure(
                        url: url,
                        errorDomain: nsError.domain,
                        errorCode: nsError.code
                    )
                }
                return nil
            }
        }

        return nil
    }

    private static nonisolated func waitBeforeRemoteRetry(afterAttempt attempt: Int) async -> Bool {
        do {
            try await Task.sleep(
                for: .milliseconds(RemoteImageRetryPolicy.delayMilliseconds(afterAttempt: attempt))
            )
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    private static nonisolated func decodeImage(
        url: URL,
        cacheKey: String,
        maxSize: CGFloat
    ) async -> UIImage? {
        guard await decodePermits.acquire() else { return nil }
        if Task.isCancelled {
            await decodePermits.release()
            return nil
        }

        let image: UIImage? = await withCheckedContinuation { continuation in
            decodeQueue.async {
                guard let cgImage = ImageDownsampler.downsample(url: url, maxSize: maxSize) else {
                    continuation.resume(returning: nil)
                    return
                }
                let result = UIImage(cgImage: cgImage)
                ImageCache.shared.set(result, forKey: cacheKey)
                continuation.resume(returning: result)
            }
        }
        await decodePermits.release()
        return image
    }
}
