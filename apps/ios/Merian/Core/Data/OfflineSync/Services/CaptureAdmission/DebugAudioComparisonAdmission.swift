#if DEBUG && targetEnvironment(simulator)
import SwiftData

/// Fail before funding or copying files: SwiftData uniqueness must never upsert a
/// second staged comparison over a queued or saved attempt with the fixed ID.
@MainActor
enum DebugAudioComparisonAdmission {
    static func isAvailable(scanId: String, context: ModelContext?) -> Bool {
        guard let context else { return false }
        do {
            var queued = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
            queued.fetchLimit = 1
            var saved = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
            saved.fetchLimit = 1
            return try context.fetch(queued).isEmpty && context.fetch(saved).isEmpty
        } catch {
            return false
        }
    }
}
#endif
