import Foundation

enum SpeciesCommonNamePresentation {
    /// Produces the comparison key used to collapse near-identical display-name
    /// variants while preserving the first spelling supplied by the caller.
    static func normalizationKey(for value: String) -> String {
        var key = value
            .lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
            .replacingOccurrences(of: "-", with: "")
            .components(separatedBy: .whitespaces)
            .joined()
        if key.hasSuffix("s") {
            key.removeLast()
        }
        return key
    }

    static func removingFuzzyDuplicates(from names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter {
            seen.insert(normalizationKey(for: $0)).inserted
        }
    }
}
