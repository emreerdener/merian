import Foundation

struct ChangelogCatalog: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let entries: [ChangelogEntry]

    static let supportedSchemaVersion = 1

    static func decode(from data: Data) throws -> ChangelogCatalog {
        let decoder = JSONDecoder()
        return try decoder.decode(ChangelogCatalog.self, from: data)
    }

    var newestEntriesFirst: [ChangelogEntry] {
        entries.sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date > rhs.date
            }

            return lhs.id > rhs.id
        }
    }
}

struct ChangelogEntry: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let version: String?
    let build: String?
    let date: String
    let title: String
    let imageAssetName: String?
    let sections: [ChangelogSection]

    var formattedDate: String {
        guard let parsedDate = Self.dateFormatter.date(from: date) else {
            return date
        }

        return Self.displayFormatter.string(from: parsedDate)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

struct ChangelogSection: Codable, Equatable, Identifiable, Sendable {
    let title: String
    let items: [String]

    var id: String {
        title
    }
}

@MainActor
@Observable
final class ChangelogStore {
    private(set) var entries: [ChangelogEntry]

    init(bundle: Bundle = .main) {
        entries = Self.loadEntries(bundle: bundle)
    }

    init(entries: [ChangelogEntry]) {
        self.entries = entries
    }

    private static func loadEntries(bundle: Bundle) -> [ChangelogEntry] {
        guard let url = bundle.url(
            forResource: "changelog",
            withExtension: "json"
        ) ?? bundle.url(
            forResource: "changelog",
            withExtension: "json",
            subdirectory: "Changelog"
        ) ?? bundle.url(
            forResource: "changelog",
            withExtension: "json",
            subdirectory: "Resources/Changelog"
        ),
              let data = try? Data(contentsOf: url),
              let catalog = try? ChangelogCatalog.decode(from: data),
              catalog.schemaVersion == ChangelogCatalog.supportedSchemaVersion else {
            return []
        }

        return catalog.newestEntriesFirst.filter { entry in
            switch entry.id {
            case "2026-07-08-field-trips":
                FieldTripsAvailability.isEnabled
            case "2026-07-19-field-trip-events-preview":
                FieldTripEventsAvailability.isEnabled
            default:
                true
            }
        }
    }
}
