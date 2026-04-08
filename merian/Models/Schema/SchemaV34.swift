import Foundation
import SwiftData

// Added in V34:
//   LocalScanRecord.alternativeCommonNames — [String]?
//     All known English vernacular synonyms beyond `commonName`, sourced from the
//     GBIF vernacular names endpoint during background enrichment.
//     Nil for scans captured before V34 or species not yet enriched; defaults to nil
//     on migration (lightweight — no backfill needed, data populates on next scan).
//
// NOTE: References global model types — freeze when V35 is created.
enum MerianSchemaV34: VersionedSchema {
    static var versionIdentifier = Schema.Version(34, 0, 0)

    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self, ScanCollection.self, PendingCloudDeletionTask.self]
    }
}
