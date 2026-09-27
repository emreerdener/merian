import Foundation

enum MapAppearance: String {
    case satellite
    case standard

    static func saved(in defaults: UserDefaults) -> Self {
        Self(rawValue: defaults.string(forKey: UserDefaultsKeys.mapAppearance) ?? "") ?? .satellite
    }
}

/// Only selected display labels are durable. Coordinates and typed queries are never stored.
struct RecentPlace: Codable, Equatable, Identifiable {
    let title: String
    let subtitle: String

    var id: String {
        [title, subtitle].map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        }.joined(separator: "\n")
    }

    var searchText: String {
        [title, subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

struct RecentPlaceStore {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var resetGeneration: Int { defaults.integer(forKey: UserDefaultsKeys.recentPlacesResetGeneration) }

    func places(for owner: UUID?) -> [RecentPlace] {
        guard let owner,
              let data = defaults.data(forKey: key(owner)),
              let places = try? JSONDecoder().decode([RecentPlace].self, from: data) else { return [] }
        return Array(places.filter { !$0.title.isEmpty }.prefix(10))
    }

    func record(_ place: RecentPlace, for owner: UUID?) {
        guard let owner, !place.title.isEmpty else { return }
        let updated = [place] + places(for: owner).filter { $0.id != place.id }
        save(Array(updated.prefix(10)), for: owner)
    }

    func remove(_ place: RecentPlace, for owner: UUID?) {
        guard let owner else { return }
        save(places(for: owner).filter { $0.id != place.id }, for: owner)
    }

    func clear(for owner: UUID?) {
        guard let owner else { return }
        defaults.removeObject(forKey: key(owner))
    }

    private func save(_ places: [RecentPlace], for owner: UUID) {
        guard let data = try? JSONEncoder().encode(places) else { return }
        defaults.set(data, forKey: key(owner))
    }

    private func key(_ owner: UUID) -> String {
        UserDefaultsKeys.recentPlacesPrefix + owner.uuidString.lowercased()
    }
}
