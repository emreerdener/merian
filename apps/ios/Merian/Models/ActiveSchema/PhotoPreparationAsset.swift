import Foundation
import SwiftData

/// P1-L1 local ownership only. The fenced preparation repository owns all writes.
/// Scalar IDs are validated references, never implicit relationships or AI admission.
@Model
final class PhotoPreparationAsset {
    @Attribute(.unique) var id: UUID
    var ownerID: UUID
    var generation: UUID
    var fileToken: String
    var contentType: String
    var byteCount: Int64
    var sha256: String
    var acquisitionKindRaw: String
    var cleanupStateRaw: String

    init(
        id: UUID,
        ownerID: UUID,
        generation: UUID,
        fileToken: String,
        contentType: String,
        byteCount: Int64,
        sha256: String,
        acquisitionKindRaw: String,
        cleanupStateRaw: String
    ) {
        self.id = id
        self.ownerID = ownerID
        self.generation = generation
        self.fileToken = fileToken
        self.contentType = contentType
        self.byteCount = byteCount
        self.sha256 = sha256
        self.acquisitionKindRaw = acquisitionKindRaw
        self.cleanupStateRaw = cleanupStateRaw
    }
}
