import Foundation

struct SpeciesNameMigrationResult: Equatable {
    let scannedCount: Int
    let promotedCount: Int
    let preservedExistingCount: Int
    let removedLegacyCount: Int
    let failedCount: Int
}
