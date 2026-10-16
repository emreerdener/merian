import Foundation
import SwiftData

/// Inactive SMA-1 ownership. No file or server authority follows from a row.
@Model
final class SharedMediaInventoryRecord {
    @Attribute(.unique) var id: UUID
    var rootIdentity: String
    var storeIdentity: String
    var generation: UUID
    var revision: Int64
    var modeRaw: String
    var phaseRaw: String
    var cursor: String

    init(id: UUID, rootIdentity: String, storeIdentity: String, generation: UUID, revision: Int64, modeRaw: String, phaseRaw: String, cursor: String) {
        self.id = id
        self.rootIdentity = rootIdentity
        self.storeIdentity = storeIdentity
        self.generation = generation
        self.revision = revision
        self.modeRaw = modeRaw
        self.phaseRaw = phaseRaw
        self.cursor = cursor
    }
}
