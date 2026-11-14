import Foundation

/// Owns a temporary Scan artifact until the caller explicitly accepts it.
///
/// Explicit discard follows producer drain. Deinitialization is a fallback,
/// not an observable cleanup boundary: task results can retain this actor.
actor CaptureScanTemporaryFileLease {
    nonisolated let fileURL: URL

    private enum State { case owned, cleanupPending, accepted, discarded }
    private var state = State.owned

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func relinquishOwnership() throws -> URL {
        try Task.checkCancellation()
        guard state == .owned || state == .accepted else {
            throw CocoaError(.fileNoSuchFile)
        }
        state = .accepted
        return fileURL
    }

    /// Idempotent and cancellation-independent after the producer has exited.
    /// A failed unlink stays retryable, but can never be accepted afterward.
    func discard() throws {
        guard state == .owned || state == .cleanupPending else { return }
        state = .cleanupPending
        do { try FileManager.default.removeItem(at: fileURL) } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile { }
        state = .discarded
    }

    func discardReportingFailure() {
        do { try discard() } catch { MerianLog.hardware.error("Temporary capture artifact cleanup failed: \(error, privacy: .private)") }
    }

    deinit {
        switch state {
        case .owned, .cleanupPending:
            try? FileManager.default.removeItem(at: fileURL)
        case .accepted, .discarded:
            break
        }
    }
}
