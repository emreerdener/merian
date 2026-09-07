import Foundation

enum OfflineQueueStoragePolicy {
    static func canAdmitNewPayload(
        estimatedBytes: Int64,
        documentsDirectory: URL = .documentsDirectory
    ) -> Bool {
        guard estimatedBytes <= MerianConfig.offlineQueueSinglePayloadSoftLimitBytes else {
            return false
        }
        let available = availableBytes(at: documentsDirectory)
        guard available > 0 else { return true }
        return available - estimatedBytes >=
            MerianConfig.offlineQueueMinimumFreeDiskBytes
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
