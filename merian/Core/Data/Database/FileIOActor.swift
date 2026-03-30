import Foundation
import os

/// Strictly isolated actor designed entirely to handle intense NVMe physical storage.
/// Bypasses the Main Actor AND the BackgroundDatabaseActor so that heavy 12 MP image reads
/// and massive file deletions never throttle the SQLite or UI threads.
public actor FileIOActor {
    
    public static let shared = FileIOActor()
    
    private init() {}

    public func validPaths(from paths: [String]) -> [String] {
        return paths.filter { path in
            if path.starts(with: "http") { return true }
            return FileManager.default.fileExists(atPath: URL.documentsDirectory.appendingPathComponent(path).path)
        }
    }
    
    /// Writes multiple image buffers to the Document Directory concurrently.
    ///
    /// Launches each write in a `Task.detached` so all disk writes proceed in parallel on worker
    /// threads, bypassing `FileIOActor`'s serial executor. On a 3-frame scan this cuts wall-clock
    /// write time from `3 × write_time` to `max(write_times)`.
    ///
    /// - Returns: Filenames in the **same order as `imageDatas`**, omitting any that failed to write.
    public func writeTemporaryImages(imageDatas: [Data]) async -> [String] {
        guard !imageDatas.isEmpty else { return [] }
        let docs = URL.documentsDirectory

        // Launch all writes concurrently before awaiting any result.
        // Each task targets a unique UUID filename — no file contention.
        let tasks: [Task<(index: Int, filename: String?), Never>] = imageDatas.enumerated().map { (i, data) in
            let filename = i == 0
                ? "\(UUID().uuidString)_scan.webp"
                : "\(UUID().uuidString)_additional_\(i).webp"
            return Task.detached(priority: .userInitiated) {
                do {
                    try data.write(to: docs.appendingPathComponent(filename), options: .atomic)
                    return (index: i, filename: filename)
                } catch {
                    MerianLog.data.error("FileIOActor: Failed writing buffer \(i, privacy: .public): \(error, privacy: .private)")
                    return (index: i, filename: nil)
                }
            }
        }

        // Collect results and restore original insertion order.
        var indexed: [(index: Int, filename: String)] = []
        for task in tasks {
            let result = await task.value
            if let filename = result.filename {
                indexed.append((index: result.index, filename: filename))
            }
        }
        return indexed.sorted { $0.index < $1.index }.map(\.filename)
    }
    
    /// Brutally purges an array of physical Sandboxed images off the OS bounds cleanly.
    public func deleteImages(at filenames: [String]) {
        let docs = URL.documentsDirectory
        for path in filenames {
            do {
                try FileManager.default.removeItem(at: docs.appendingPathComponent(path))
            } catch {
                MerianLog.data.debug("FileIOActor: Failed dropping file \(path, privacy: .private): \(error, privacy: .private)")
            }
        }
    }
}
