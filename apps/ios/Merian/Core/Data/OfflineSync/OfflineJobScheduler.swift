import Foundation
import Network
import SwiftData

@MainActor
final class OfflineJobScheduler {
    static let shared = OfflineJobScheduler()

    private init() {}

    func drainRunnableJobs(using manager: OfflineQueueManager) async {
        guard manager.isOnline else { return }

        manager.syncPendingScans()
        manager.replayInferenceForUploadedScans()
        await manager.syncPendingDeletions()
        manager.syncCollectionsIfPending()
    }
}
