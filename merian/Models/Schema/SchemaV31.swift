import Foundation
import SwiftData

// Added in V31:
//   isFlagged — boolean flag indicating the user reported this identification for manual review.
//
// NOTE: References global model types — freeze when V32 is created.
enum MerianSchemaV31: VersionedSchema {
    static var versionIdentifier = Schema.Version(31, 0, 0)

    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self, ScanCollection.self, PendingCloudDeletionTask.self]
    }
}
