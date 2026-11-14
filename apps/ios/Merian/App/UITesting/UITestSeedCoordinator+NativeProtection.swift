import Foundation
import SwiftData

#if DEBUG
extension UITestSeedCoordinator {
    /// Startup fixture preflight only. The sole caller runs synchronously before
    /// queue/background writers are configured; this helper is not a lock.
    /// Refusal cannot save, roll back, or erase a user's unsaved context.
    @MainActor
    static func canResetFixtureState(container: ModelContainer) -> Bool {
        guard !container.mainContext.hasChanges else { return false }
        let context = ModelContext(container); context.autosaveEnabled = false
        do {
            guard try !SharedMediaStorageLookup.hasLiabilities(in: context) else { return false }
            var queues = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate {
                $0.mediaAuthorityRaw != "legacy" || $0.sharedMediaConsumerID != nil
            }); queues.fetchLimit = 1
            var scans = FetchDescriptor<LocalScanRecord>(predicate: #Predicate {
                $0.mediaAuthorityRaw != "legacy" || $0.sharedMediaConsumerID != nil
            }); scans.fetchLimit = 1
            var analyses = FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate {
                $0.mediaAuthorityRaw != "legacy" || $0.sharedMediaConsumerID != nil
            }); analyses.fetchLimit = 1
            guard try context.fetch(queues).isEmpty, try context.fetch(scans).isEmpty,
                  try context.fetch(analyses).isEmpty else { return false }
            var jobs = FetchDescriptor<OfflineJobRecord>(sortBy: [SortDescriptor(\.id)])
            jobs.fetchLimit = 100
            while true {
                let page = try context.fetch(jobs)
                for job in page {
                    if job.kind == .scanIngestion || job.id.hasPrefix("scan-ingestion:") {
                        guard SharedMediaLegacyQueueAccess.permitsMetadata(job.metadataJSON) else { return false }
                    } else if let json = job.metadataJSON, let data = json.data(using: .utf8),
                              let fields = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              fields.keys.contains(SharedMediaLegacyQueueAccess.receivingKey) {
                        return false
                    }
                }
                guard page.count == 100 else { break }
                jobs.fetchOffset = (jobs.fetchOffset ?? 0) + page.count
            }
            return true
        } catch { return false }
    }
}
#endif
