import Foundation
import SwiftData

/// Immutable outgoing V64 acquisition receipt shape.
extension MerianSchemaV64 {
    /// Native acquisition recovery evidence. Raw rows never authorize a writer,
    /// media access, admission or cleanup. Terminal rows retain replay rejection.
    @Model
    final class SharedMediaAcquisitionReceiptRecord {
        @Attribute(.unique) var id: UUID
        var schemaVersion: Int
        var inventoryID: UUID
        var inventoryGeneration: UUID
        var ownerID: UUID
        private(set) var requestFingerprint: String
        var phaseRaw: String
        var terminalOutcomeRaw: String?
        var revision: Int64
        /// Lookup aids must agree with the canonical request; absent in tombstones.
        var packageID: UUID?
        var assetID: UUID?
        var requestData: Data?
        var resultData: Data?

        init(operationID: UUID, inventoryID: UUID, inventoryGeneration: UUID,
             ownerID: UUID, requestFingerprint: String, packageID: UUID,
             assetID: UUID, requestData: Data) {
            id = operationID
            schemaVersion = 1
            self.inventoryID = inventoryID
            self.inventoryGeneration = inventoryGeneration
            self.ownerID = ownerID
            self.requestFingerprint = requestFingerprint
            self.packageID = packageID
            self.assetID = assetID
            self.requestData = requestData
            resultData = nil
            phaseRaw = "reserved"
            terminalOutcomeRaw = nil
            revision = 0
        }
    }
}
