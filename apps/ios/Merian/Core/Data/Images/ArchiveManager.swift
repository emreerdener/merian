import Foundation
import Observation

// MARK: - Dataset Archive Download Orchestrator
@MainActor
@Observable final class ArchiveManager {
    // MARK: - Singleton Architecture
    static let shared = ArchiveManager()

    // Isolated session for downloading generated export archives.
    // 300 s resource timeout to handle large ZIP payloads on slow connections.
    private static let mediaSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()

    private init() {}

    // MARK: - File System Analytics
    func getAvailableDiskSpace() -> Int64 {
        do {
            let fileURL = URL(fileURLWithPath: NSHomeDirectory())
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let available = values.volumeAvailableCapacityForImportantUsage {
                return available
            }
        } catch {
            MerianLog.data.debug("ArchiveManager: Failed to query true APFS space: \(error, privacy: .private)")
        }
        return 0
    }

    /// Downloads generated dataset archives while protecting cellular bandwidth via strict file caching.
    func downloadArchive(id: String, url: URL) async throws -> URL {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw URLError(.cannotCreateFile)
        }

        let filename = "dataset_archive_\(id).zip"
        let fileURL = documentsDirectory.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }

        let (tempURL, response) = try await ArchiveManager.mediaSession.download(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        try FileManager.default.moveItem(at: tempURL, to: fileURL)
        return fileURL
    }
}
