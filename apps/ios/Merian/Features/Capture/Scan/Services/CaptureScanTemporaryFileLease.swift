import Foundation

/// Owns a temporary Scan artifact until the caller explicitly accepts it.
///
/// A timeout race may finish its media worker after the structured operation
/// has already been cancelled. Keeping cleanup in this sendable owner ensures
/// an unconsumed result still deletes its file when the lease is released.
actor CaptureScanTemporaryFileLease {
    nonisolated let fileURL: URL

    private var hasRelinquishedOwnership = false

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func relinquishOwnership() throws -> URL {
        try Task.checkCancellation()
        hasRelinquishedOwnership = true
        return fileURL
    }

    deinit {
        guard !hasRelinquishedOwnership else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
