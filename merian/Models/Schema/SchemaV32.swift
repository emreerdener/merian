import Foundation
import SwiftData

// Added in V32:
//   OfflineQueuedScan.isUploaded — Bool flag (default false) marking that all image files
//   for this scan have been confirmed received by R2 staging. Prevents re-uploading
//   already-staged files across app restarts when inference hasn't yet processed the scan.
//
// NOTE: References global model types — freeze when V33 is created.
enum MerianSchemaV32: VersionedSchema {
    static var versionIdentifier = Schema.Version(32, 0, 0)

    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self, ScanCollection.self, PendingCloudDeletionTask.self]
    }
}
