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
    static let categories = entries.reduce(into: [String]()) { result, entry in
        if result.last != entry.category { result.append(entry.category) }
    }
    static func name(for emoji: String) -> String { byEmoji[emoji]?.name ?? emoji }
    static func order(for emoji: String) -> Int { byEmoji[emoji]?.order ?? Int.max }
}
