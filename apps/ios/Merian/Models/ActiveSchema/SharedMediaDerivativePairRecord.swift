import Foundation
import SwiftData

/// Exact local replacement intent and publication authority for one AI/display pair.
@Model
final class SharedMediaDerivativePairRecord {
    @Attribute(.unique) var id: UUID
    var nonce: UUID
    var contractVersion: String
    var inventoryID: UUID
    var inventoryGeneration: UUID
    var expectedInventoryRevision: Int64
    var ownerID: UUID
    var packageID: UUID
    var draftGeneration: UUID
    var originalReferenceID: UUID
    var originalReferenceRevision: Int64
    var originalAssetID: UUID
    var originalAssetGeneration: UUID
    var ordinal: Int64
    var expectedPackageRevision: Int64
    var aiWorkID: UUID
    var displayWorkID: UUID
    var previousPairID: UUID?
    var phaseRaw: String
    var publishedRevision: Int64?

    init(
        id: UUID,
        nonce: UUID,
        inventoryID: UUID,
        inventoryGeneration: UUID,
        expectedInventoryRevision: Int64,
        ownerID: UUID,
        packageID: UUID,
        draftGeneration: UUID,
        originalReferenceID: UUID,
        originalReferenceRevision: Int64,
        originalAssetID: UUID,
        originalAssetGeneration: UUID,
        ordinal: Int64,
        expectedPackageRevision: Int64,
        aiWorkID: UUID,
        displayWorkID: UUID,
        previousPairID: UUID? = nil
    ) {
        self.id = id
        self.nonce = nonce
        self.inventoryID = inventoryID
        self.inventoryGeneration = inventoryGeneration
        self.expectedInventoryRevision = expectedInventoryRevision
        self.ownerID = ownerID
        self.packageID = packageID
        self.draftGeneration = draftGeneration
        self.originalReferenceID = originalReferenceID
        self.originalReferenceRevision = originalReferenceRevision
        self.originalAssetID = originalAssetID
        self.originalAssetGeneration = originalAssetGeneration
        self.ordinal = ordinal
        self.expectedPackageRevision = expectedPackageRevision
        self.aiWorkID = aiWorkID
        self.displayWorkID = displayWorkID
        self.previousPairID = previousPairID
        contractVersion = "sharedDerivativeV1"
        phaseRaw = "planned"
    }
}
