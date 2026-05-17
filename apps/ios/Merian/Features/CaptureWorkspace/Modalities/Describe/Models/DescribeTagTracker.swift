import Foundation

/// A lightweight persistence wrapper for tracking how often a user selects specific Describe tags.
///
/// Designed to be called from `@MainActor` views. Tag IDs are used as stable persistence keys
/// to prevent data loss if human-readable labels are updated in the future.
@MainActor
final class DescribeTagTracker {
    static let shared = DescribeTagTracker()
    
    private let defaults = UserDefaults.standard
    private let prefix = "DescribeTagFreq_"
    
    private init() {}
    
    /// Retrieves the total number of times a specific tag has been selected.
    func frequency(for tagId: String) -> Int {
        return defaults.integer(forKey: prefix + tagId)
    }
    
    /// Increments the usage counter for a specific tag.
    func recordUsage(for tagId: String) {
        let current = frequency(for: tagId)
        defaults.set(current + 1, forKey: prefix + tagId)
    }
}
