import Foundation
import SwiftData

// Added in V36:
//   LocalScanRecord.userReviewStateRaw — String
//     Stores the explicit user review state mapping to public.user_review_state.
// NOTE: References global model types — freeze when V37 is created.
enum MerianSchemaV36: VersionedSchema {
    static var versionIdentifier = Schema.Version(36, 0, 0)

    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self,
         ScanCollection.self, PendingCloudDeletionTask.self,
         UserSpeciesPreference.self]
    }
}
