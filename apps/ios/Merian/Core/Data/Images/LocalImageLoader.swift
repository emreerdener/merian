import Foundation
import UIKit

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

    func recordLocalRecovery(url: URL) {
        let host = sanitizedHost(for: url)
        guard shouldLog(key: "\(host)|local-recovery") else { return }
        MerianLog.network.info(
            "LocalImageLoader: recovered durable scan image from Documents host=\(host, privacy: .public)"
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

/// Coalesces local and remote image loads behind bounded, off-actor decoding.
actor LocalImageLoader {
    struct Dependencies: Sendable {
        let existingLocalImageURL: @Sendable (URL) -> URL?
        let decodeImage:
            @Sendable (URL, String, CGFloat) async -> UIImage?
        let loadLocalImage:
            @Sendable (String, String, CGFloat) async -> UIImage?
        let fetchRemoteImage:
            @Sendable (URL, String, CGFloat) async -> UIImage?
        let recordLocalRecovery: @Sendable (URL) async -> Void
        let enqueueCloudRepair: @Sendable (URL, URL) async -> Void

        static let live = Dependencies(
            existingLocalImageURL: { remoteURL in
                LocalScanMediaRecoveryResolver.existingLocalImageURL(
                    for: remoteURL
                )
            },
            decodeImage: { url, cacheKey, maxSize in
                await LocalImageLoader.decodeImage(
                    url: url,
                    cacheKey: cacheKey,
                    maxSize: maxSize
                )
            },
            loadLocalImage: { path, cacheKey, maxSize in
                await LocalImageLoader.loadLocal(
                    path: path,
                    cacheKey: cacheKey,
                    maxSize: maxSize
                )
            },
            fetchRemoteImage: { url, cacheKey, maxSize in
                await LocalImageLoader.fetchRemote(
                    url: url,
                    cacheKey: cacheKey,
                    maxSize: maxSize
                )
            },
            recordLocalRecovery: { url in
                await RemoteImageLoadDiagnostics.shared.recordLocalRecovery(
                    url: url
                )
            },
            enqueueCloudRepair: { sourceURL, localURL in
                await CloudScanImageRepairActor.shared.enqueue(
                    sourceUrl: sourceURL,
                    localUrl: localURL
                )
            }
        )
    }

    static let shared = LocalImageLoader()

    private let dependencies: Dependencies
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

    init(dependencies: Dependencies = .live) {
        self.dependencies = dependencies
    }

    func loadImage(
        fromPath imagePath: String?,
        fallbackUrl: String? = nil,
        maxDimension: Int = 1024
    ) async -> UIImage? {
        let safeImagePath: String?
        if let imagePath {
            let trimmed = imagePath.trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = URL(string: trimmed),
               parsed.scheme != nil,
               !parsed.isFileURL {
                safeImagePath = ExternalReferenceImagePolicy.sanitizedURL(trimmed)
            } else {
                safeImagePath = trimmed.isEmpty ? nil : trimmed
            }
        } else {
            safeImagePath = nil
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
        
        let dependencies = dependencies
        let fetchTask = Task.detached(
            priority: .userInitiated
        ) { () -> UIImage? in
            // 3. Remote URL Execution (if 'imagePath' is actually a cloud URL payload directly)
            if let remoteUrl = ExternalReferenceImagePolicy.url(
                from: safeImagePath
            ) {
                if let localURL = dependencies.existingLocalImageURL(
                    remoteUrl
                ),
                   let localImage = await dependencies.decodeImage(
                       localURL,
                       cacheKey,
                       CGFloat(maxDimension)
                   ) {
                    await dependencies.recordLocalRecovery(remoteUrl)
                    await dependencies.enqueueCloudRepair(
                        remoteUrl,
                        localURL
                    )
                    return localImage
                }

                if let networkImage = await dependencies.fetchRemoteImage(
                    remoteUrl,
                    cacheKey,
                    CGFloat(maxDimension)
                ) {
                    return networkImage
                }
            }
            // 4. Local File Extraction directly off Main Thread
            else if let safePath = safeImagePath, !safePath.isEmpty {
                if let image = await dependencies.loadLocalImage(
                    safePath,
                    cacheKey,
                    CGFloat(maxDimension)
                ) {
                    return image
                }
            }

            // 5. Explicit Network Fallback explicitly routing legacy bounds
            if let fallbackUrlString = safeFallbackUrl {
                let urls = fallbackUrlString.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .compactMap { ExternalReferenceImagePolicy.url(from: $0) }

                for url in urls {
                    // We intentionally do NOT check `Task.isCancelled` here because this is a
                    // detached task serving multiple coalesced callers. We want it to finish caching.
                    if let localURL = dependencies.existingLocalImageURL(url),
                       let localImage = await dependencies.decodeImage(
                           localURL,
                           cacheKey,
                           CGFloat(maxDimension)
                    ) {
                        await dependencies.recordLocalRecovery(url)
                        await dependencies.enqueueCloudRepair(
                            url,
                            localURL
                        )
                        return localImage
                    }

                    if let networkImage = await dependencies.fetchRemoteImage(
                        url,
                        cacheKey,
                        CGFloat(maxDimension)
                    ) {
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
        if Task.isCancelled
            || !SecureTransportPolicy.isSecureRemoteURL(url)
            || !ExternalReferenceImagePolicy.isAllowed(url) {
            return nil
        }

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
