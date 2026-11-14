import Foundation
import SwiftData

/// Distinguishes an uninitialized bounded graph from missing ownership metadata.
/// The fenced owner creates this with the complete initial membership set.
@Model
final class SharedMediaMembershipBootstrapRecord {
    @Attribute(.unique) var id: UUID
    var inventoryGeneration: UUID
    var contractVersion: Int
    var revision: Int64

    init(inventoryID: UUID, inventoryGeneration: UUID) {
        id = inventoryID
        self.inventoryGeneration = inventoryGeneration
        contractVersion = 1
        revision = 0
    }
}
