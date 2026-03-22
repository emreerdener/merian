import Foundation

// MARK: - Concurrency DTO
struct SearchableScan: Sendable {
    // MARK: - Safe Properties
    let id: String
    let searchString: String
    let ecologyType: String
    let kingdom: String
    let className: String
}
