import Foundation

/// Owns a temporary Scan artifact until the caller explicitly accepts it.
///
/// Explicit discard follows producer drain. Deinitialization is a fallback,
/// not an observable cleanup boundary: task results can retain this actor.
actor CaptureScanTemporaryFileLease {
    nonisolated let fileURL: URL
    private let retirement: LegacyMediaFileRetirement?

    private enum State { case owned, cleanupPending, accepted, discarded }
    private var state = State.owned

    init(fileURL: URL) {
        self.fileURL = fileURL
        retirement = LegacyMediaFileRetirement.temporaryFile(at: fileURL)
    }

    /// Only a creation owner may supply this exact descriptor-derived receipt.
    init(fileURL: URL, retirement: LegacyMediaFileRetirement) {
        self.fileURL = fileURL
        self.retirement = retirement
    }

    /// Roll back a local prepare transaction before its result is handed to the caller.
    /// The receipt survives acceptance; this never acquires authority from a raw URL.
    func rollbackUnpublishedTransfer() throws {
        if state == .accepted { state = .owned }
        try discard()
    }

    func readOriginal(maximumBytes: Int) async throws -> Data {
        guard state == .owned, let retirement,
              let bytes = await FileIOActor.shared.readRetainedOriginal(retirement, maximumBytes: maximumBytes),
              state == .owned else { throw SharedMediaStorageFailure.conflict }
        return bytes
    }

    func relinquishOwnership() throws -> URL {
        try Task.checkCancellation()
        guard state == .owned || state == .accepted, retirement != nil else {
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
        if let retirement {
            guard retirement.retire() else { throw CocoaError(.fileWriteUnknown) }
        } else {
            // Missing at acquisition grants no permission over a later file.
            guard !FileManager.default.fileExists(atPath: fileURL.path) else { throw CocoaError(.fileWriteUnknown) }
        }
        state = .discarded
    }

    func discardReportingFailure() async {
        let complete = await FileIOActor.shared.settleProducerCleanup(owner: self) { try await self.discard() }
        if !complete { MerianLog.hardware.error("Temporary capture artifact cleanup remains owned for retry") }
    }

    deinit {
        switch state {
        case .owned, .cleanupPending:
            _ = retirement?.retire()
        case .accepted, .discarded:
            break
        }
    }
}
