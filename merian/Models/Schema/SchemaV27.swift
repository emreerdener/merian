import Foundation
import SwiftData

// Added: lookalikesData — JSON-encoded [SimilarSpeciesEntry] blob persisting rich lookalike
// data (commonName, referenceImageUrl, iucnRedListStatus) through the SwiftData layer.
// similarSpecies [String]? is retained for backwards-compatible fallback when lookalikesData is nil.
//
// NOTE: This file intentionally references the global model types (LocalScanRecord, etc.) rather
// than frozen snapshots. The CURRENT active schema must reference global types so that all app
// code (@Query, context.insert, etc.) operates on the same entities as the container.
// Freezing happens when this version is RETIRED — i.e., when SchemaV28 is created. See:
//   .agents/workflows/schema_update.md — Step 1: snapshot the outgoing schema BEFORE modifying
//   any global models in ActiveSchema/.
enum MerianSchemaV27: VersionedSchema {
    static var versionIdentifier = Schema.Version(27, 0, 0)

    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self, ScanCollection.self, PendingCloudDeletionTask.self]
    }
}
