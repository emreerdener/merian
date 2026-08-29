import Foundation

extension String {
    /// Returns surrounding-whitespace-trimmed content, or `nil` when no
    /// non-whitespace content remains.
    var trimmedNonEmptyValue: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
