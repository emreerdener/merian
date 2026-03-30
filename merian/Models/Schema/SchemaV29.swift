import Foundation
import SwiftData

// Added in V29:
//   userIdentificationOverride — scientific name user selected when overriding the AI (cloud-synced).
//   userConfirmedIdentification — user explicitly confirmed AI was correct (cloud-synced).
//
// NOTE: References global model types — freeze when V30 is created.
enum MerianSchemaV29: VersionedSchema {
    static var versionIdentifier = Schema.Version(29, 0, 0)

    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self, ScanCollection.self, PendingCloudDeletionTask.self]
    }
}
