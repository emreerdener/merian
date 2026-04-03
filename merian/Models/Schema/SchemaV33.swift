import Foundation
import SwiftData

// Added in V33:
//   OfflineQueuedScan.scanStateRaw  — Int (raw ScanQueueState) replacing isUploaded + isDeleted booleans.
//   OfflineQueuedScan.stagedR2Keys  — [String]? storing confirmed R2 object keys, eliminating
//                                     auth-dependent key reconstruction at inference time.
//
// Removed from OfflineQueuedScan in V33:
//   isUploaded (Bool) — superseded by scanStateRaw >= ScanQueueState.staged.rawValue
//   isDeleted  (Bool) — superseded by scanStateRaw == ScanQueueState.failed.rawValue
//
// NOTE: References global model types — freeze when V34 is created.
enum MerianSchemaV33: VersionedSchema {
    static var versionIdentifier = Schema.Version(33, 0, 0)

    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self, ScanCollection.self, PendingCloudDeletionTask.self]
    }
}
