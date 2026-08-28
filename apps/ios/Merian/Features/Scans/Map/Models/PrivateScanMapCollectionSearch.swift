import Foundation

enum PrivateScanMapCollectionSearch {
    private static let aliases = [
        "scan map",
        "map",
        "private",
        "locations",
        "your scans"
    ]

    static func matches(_ query: String) -> Bool {
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalizedQuery.isEmpty || aliases.contains {
            $0.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }
}
