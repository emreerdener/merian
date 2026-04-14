import Foundation
import SwiftData

// Added in V37:
//   LocalScanRecord.observationContextJSON — String?
//     Raw JSON of the ObservationContext staged by the user. NULL for image-only scans.
//   OfflineQueuedScan.observationContextJSON — String?
//     JSON-encoded ObservationContext preserved for offline-retry reconstruction.
//   OfflineQueuedScan.audioFilePath — String?
//     Reserved placeholder for a companion audio recording clip (future AudioRecordingView).
// NOTE: References global model types — freeze when V38 is created.
enum MerianSchemaV37: VersionedSchema {
    static var versionIdentifier = Schema.Version(37, 0, 0)

    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self,
         ScanCollection.self, PendingCloudDeletionTask.self,
         UserSpeciesPreference.self]
    }
}
