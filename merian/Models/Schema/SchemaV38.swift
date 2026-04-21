import Foundation
import SwiftData

// Added in V38:
//   LocalScanRecord.audioFilePath — String?
//     Local file path to the audio recording associated with this scan.
// NOTE: References global model types — freeze when V39 is created.
enum MerianSchemaV38: VersionedSchema {
    static var versionIdentifier = Schema.Version(38, 0, 0)

    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self,
         ScanCollection.self, PendingCloudDeletionTask.self,
         UserSpeciesPreference.self]
    }
}
