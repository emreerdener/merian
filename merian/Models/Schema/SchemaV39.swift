import Foundation
import SwiftData

// Added in V39:
//   LocalScanRecord.audioFilePaths — [String]?
//   LocalScanRecord.observationContextsJSON — [String]?
//   OfflineQueuedScan.audioFilePaths — [String]?
//   OfflineQueuedScan.observationContextsJSON — [String]?
enum MerianSchemaV39: VersionedSchema {
    static var versionIdentifier = Schema.Version(39, 0, 0)

    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self,
         ScanCollection.self, PendingCloudDeletionTask.self,
         UserSpeciesPreference.self]
    }
}
