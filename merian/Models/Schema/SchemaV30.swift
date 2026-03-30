import Foundation
import SwiftData

// Added in V30:
//   imageQualityScore — Gemini's photographic quality score (0–100) for the submitted image.
//
// NOTE: References global model types — freeze when V31 is created.
enum MerianSchemaV30: VersionedSchema {
    static var versionIdentifier = Schema.Version(30, 0, 0)

    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self, ScanCollection.self, PendingCloudDeletionTask.self]
    }
}
