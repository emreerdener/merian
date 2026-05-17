import Foundation

public extension Array {
    /// Safely accesses an element at the specified index.
    /// Returns `nil` if the index is out of bounds, preventing fatal runtime index crashes.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Array where Element: Hashable {
    /// Returns the array with duplicate elements removed, preserving original order.
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

// MARK: - Common Name Fuzzy Deduplication

extension String {
    /// Normalization key for collapsing near-identical common name variants.
    /// Strips apostrophes (straight and curly), hyphens, and whitespace, then lowercases.
    /// A trailing 's' is also stripped so singular/plural pairs
    /// ("Lamb's-ear" / "Lamb's-ears") map to the same key.
    var commonNameKey: String {
        var s = self
            .lowercased()
            .replacingOccurrences(of: "'", with: "")   // straight apostrophe
            .replacingOccurrences(of: "\u{2019}", with: "") // right single quotation mark
            .replacingOccurrences(of: "-", with: "")
            .components(separatedBy: .whitespaces)
            .joined()
        if s.hasSuffix("s") { s.removeLast() }
        return s
    }
}

extension Array where Element == String {
    /// Returns the array with near-duplicate common name variants removed, preserving order.
    /// Variants that differ only by apostrophe style, hyphenation, spacing, or a trailing 's'
    /// (e.g. "Hare's Foot Inkcap" / "Hare'sfoot Inkcap", "Lamb's-ear" / "Lamb's-ears")
    /// are treated as the same name; the first occurrence is kept.
    func removingFuzzyDuplicateNames() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0.commonNameKey).inserted }
    }
}
