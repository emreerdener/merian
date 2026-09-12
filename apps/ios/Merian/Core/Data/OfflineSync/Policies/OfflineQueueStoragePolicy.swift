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

    private static func availableBytes(at url: URL) -> Int64 {
        guard let values = try? url.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ),
              let available = values.volumeAvailableCapacityForImportantUsage else {
            return 0
        }
        return available
    }
}
