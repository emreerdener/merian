import Foundation
import SwiftData

/// Inactive SMA-1 ownership. No file or server authority follows from a row.
@Model
final class SharedMediaLeaseRecord {
    @Attribute(.unique) var id: UUID
    var allocationID: UUID
    var processEpoch: UUID
    var purposeRaw: String
    var stateRaw: String

    init(id: UUID, allocationID: UUID, processEpoch: UUID, purposeRaw: String, stateRaw: String) {
        self.id = id
        self.allocationID = allocationID
        self.processEpoch = processEpoch
        self.purposeRaw = purposeRaw
        self.stateRaw = stateRaw
    }
}
