import Foundation

struct ExploreEmojiEntry: Decodable, Identifiable {
    let emoji: String
    let name: String
    let category: String
    let keywords: String
    let aliases: [String]
    let order: Int
    var id: String { emoji }
}

enum ExploreEmojiCatalog {
    private struct Catalog: Decodable { let entries: [ExploreEmojiEntry] }
    static let entries: [ExploreEmojiEntry] = {
        guard let url = Bundle.main.url(forResource: "ExploreEmojiCatalog", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let catalog = try? JSONDecoder().decode(Catalog.self, from: data)
        else { return [] }
        return catalog.entries
    }()
    static let byEmoji = Dictionary(uniqueKeysWithValues: entries.map { ($0.emoji, $0) })
    // Keep the full catalog for existing reactions; only picker choices omit tone variants.
    static let pickerEntries = entries.filter { entry in
        !entry.emoji.unicodeScalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) }
    }
    static let pickerCategories: [String] = {
        var seen = Set<String>()
        return pickerEntries.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }()

    static func pickerEntries(matching query: String, category: String?) -> [ExploreEmojiEntry] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return pickerEntries.filter { entry in
            guard category == nil || entry.category == category else { return false }
            return search.isEmpty || entry.emoji == search || entry.name.localizedStandardContains(search)
                || entry.keywords.localizedStandardContains(search)
                || entry.category.localizedStandardContains(search)
        }
    }

    static func name(for emoji: String) -> String { byEmoji[emoji]?.name ?? emoji }
    static func order(for emoji: String) -> Int { byEmoji[emoji]?.order ?? Int.max }
}
