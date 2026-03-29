import Foundation
import SwiftData

// Removed: diagnosticPrimaryRationale, diagnosticDifferentiatorsJson
enum MerianSchemaV26: VersionedSchema {
    static var versionIdentifier = Schema.Version(26, 0, 0)

    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self, ScanCollection.self, PendingCloudDeletionTask.self]
    }
}
