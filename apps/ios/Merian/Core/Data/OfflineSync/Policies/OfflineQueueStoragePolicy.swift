import Foundation

enum OfflineQueueStoragePolicy {
    /// Minimum free disk space retained after admitting a queue payload.
    static let minimumFreeDiskBytes: Int64 = 100 * 1_024 * 1_024

    /// Soft ceiling for the bytes one queued payload may add.
    static let singlePayloadSoftLimitBytes: Int64 = 25 * 1_024 * 1_024

    static func canAdmitNewPayload(
        estimatedBytes: Int64,
        documentsDirectory: URL = .documentsDirectory
    ) -> Bool {
        guard estimatedBytes <= singlePayloadSoftLimitBytes else {
            return false
        }
        let available = availableBytes(at: documentsDirectory)
        guard available > 0 else { return true }
        return available - estimatedBytes >=
            minimumFreeDiskBytes
    }

    static func approximateBytes(for urls: [URL]) -> Int64 {
        urls.reduce(Int64(0)) { total, url in
            total + fileSize(at: url)
        }
    }

    static func estimatedBytes(for paths: [String]) -> Int64 {
        paths.reduce(Int64(0)) { total, path in
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return total }
            let candidates: [URL]
            if trimmed.hasPrefix("/") {
                candidates = [URL(fileURLWithPath: trimmed)]
            } else {
                candidates = [
                    URL.documentsDirectory.appendingPathComponent(trimmed),
                    FileManager.default.temporaryDirectory.appendingPathComponent(trimmed)
                ]
            }
            let size = candidates.lazy
                .compactMap { existingFileSize(at: $0) }
                .first ?? 0
            return total + size
        }
    }

    static func queuedMediaBytes(
        mediaItems: [SerializedMediaItem],
        inferenceImagePaths: [String]? = nil
    ) -> Int64 {
        let snapshot = CapturedMediaSnapshot(items: mediaItems)
        let paths = snapshot.thumbnailImagePaths
            + snapshot.audioPaths
            + snapshot.videoPaths
            + (inferenceImagePaths ?? [])
        let urls = Set(paths.compactMap(queuedMediaURL(for:)))
        return approximateBytes(for: Array(urls))
    }

    private static func availableBytes(at url: URL) -> Int64 {
        guard let values = try? url.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ),
              let available = values.volumeAvailableCapacityForImportantUsage else {
            return 0
        }
        return available
    }

    private static func fileSize(at url: URL) -> Int64 {
        existingFileSize(at: url) ?? 0
    }

    private static func existingFileSize(at url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?
            .int64Value
    }

    private static func queuedMediaURL(for path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("http://"),
              !trimmed.hasPrefix("https://") else {
            return nil
        }
        if let url = URL(string: trimmed), url.isFileURL {
            return url
        }
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed)
        }
        return URL.documentsDirectory.appendingPathComponent(trimmed)
    }
}
