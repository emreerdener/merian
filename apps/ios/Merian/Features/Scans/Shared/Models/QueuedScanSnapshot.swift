import Foundation

/// A value snapshot of the data a queued scan tile needs to render.
///
/// `LazyVGrid` accesses tiles after their backing SwiftData rows may have been
/// deleted. The Shell data store therefore copies queue fields into this value
/// before presentation so no lazy view retains an `OfflineQueuedScan` model.
struct QueuedScanSnapshot: Identifiable, Equatable, Sendable {
    /// Raw scan UUID used for deletion lookups and refresh tracking.
    let id: String
    let imagePath: String?
    let capturedMediaJSON: String?
    let queueState: ScanQueueState
    let timestamp: Date
    let queueNextRetryAt: Date?
    let queueLastErrorMessage: String?
    let queueNeedsAttention: Bool
    let approximateQueuedBytes: Int64

    var capturedMediaItems: [SerializedMediaItem] {
        var items = CapturedMediaSnapshot(
            jsonString: capturedMediaJSON
        ).items
        if items.isEmpty,
           let imagePath = imagePath?.trimmedNonEmptyValue {
            items = [
                .image(StoredMediaReference(legacyPath: imagePath))
            ]
        }
        return items
    }

    /// Namespaced identity for a grid that may briefly contain both a queued
    /// row and its same-ID completed record.
    var gridId: String { "q_\(id)" }

    /// Whether workers can advance this durable state without explicit user
    /// recovery.
    var isAutomaticRecoveryEligible: Bool {
        guard !queueNeedsAttention else { return false }
        switch queueState {
        case .pending, .uploading, .staged, .inferencing:
            return true
        case .externalImport, .failed:
            return false
        }
    }

    /// Whether automatic recovery can progress under the current network and
    /// large-video policy.
    func isAutomaticRecoveryEligibleForCurrentNetwork(
        isOnline: Bool,
        isConstrained: Bool,
        allowsVideoUploads: Bool,
        isForcedVideoUpload: Bool
    ) -> Bool {
        guard isOnline,
              !isConstrained,
              isAutomaticRecoveryEligible else {
            return false
        }
        guard queueState == .pending,
              capturedMediaItems.contains(where: { item in
                  if case .video = item {
                      return true
                  }
                  return false
              }) else {
            return true
        }
        return allowsVideoUploads || isForcedVideoUpload
    }

    var canRetryNow: Bool {
        queueState.isManualRetryEligible(
            needsAttention: queueNeedsAttention,
            nextRetryAt: queueNextRetryAt
        )
    }
}
