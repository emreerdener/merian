import Foundation
import SwiftData

/// P1-L1 local ownership only. The fenced preparation repository owns all writes.
/// Scalar IDs are validated references, never implicit relationships or AI admission.
@Model
final class PhotoPreparationReference {
    @Attribute(.unique) var id: UUID
    var packageID: UUID
    var assetID: UUID
    var ownerID: UUID
    var roleRaw: String
    var ordinal: Int64
    var revision: Int64
    var isLive: Bool

    init(
        id: UUID,
        packageID: UUID,
        assetID: UUID,
        ownerID: UUID,
        roleRaw: String,
        ordinal: Int64,
        revision: Int64,
        isLive: Bool
    ) {
        self.id = id
        self.packageID = packageID
        self.assetID = assetID
        self.ownerID = ownerID
        self.roleRaw = roleRaw
        self.ordinal = ordinal
        self.revision = revision
        self.isLive = isLive
    }
}
