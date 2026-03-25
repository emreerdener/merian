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
    
    /// Writes multiple physical arrays out to the Document Directory atomically.
    /// - Returns: An array of filenames representing the successfully written bounds.
    public func writeTemporaryImages(imageDatas: [Data]) -> [String] {
        var savedPaths: [String] = []
        let docs = URL.documentsDirectory
        
        for (i, data) in imageDatas.enumerated() {
            let filename: String
            if i == 0 {
                filename = "\(UUID().uuidString)_scan.webp"
            } else {
                filename = "\(UUID().uuidString)_additional_\(i).webp"
            }
            
            do {
                try data.write(to: docs.appendingPathComponent(filename), options: .atomic)
                savedPaths.append(filename)
            } catch {
                MerianLog.data.error("FileIOActor: Failed writing buffer \(i, privacy: .public): \(error, privacy: .private)")
            }
        }
        
        return savedPaths
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
