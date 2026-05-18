import Foundation

struct SpeciesObservationStatsResponse: Decodable {
    let schemaVersion: Int?
    let data: SpeciesObservationStatsEntry

    var effectiveSchemaVersion: Int { schemaVersion ?? 0 }
}

struct SpeciesObservationStatsEntry: Decodable, Equatable, Identifiable {
    let speciesId: String?
    let scientificName: String
    let source: SpeciesObservationStatsSource
    let status: SpeciesObservationStatsStatus
    let totalObservations: Int
    let lastObservationDate: String?
    let fetchedAt: String
    let providerErrors: [String]
    let seasonality: [SpeciesObservationMonthCount]
    let history: [SpeciesObservationHistoryCount]
    let lifeStage: [SpeciesObservationCategorySeries]

    var id: String { speciesId ?? scientificName }
}

struct SpeciesObservationStatsSource: Decodable, Equatable {
    let provider: String
    let scope: String
    let inaturalistTaxonId: Int?
    let fetchedAt: String
}

enum SpeciesObservationStatsStatus: Decodable, Equatable {
    case fresh
    case stale
    case noData
    case unavailable
    case partial
    case unknown(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "fresh":
            self = .fresh
        case "stale":
            self = .stale
        case "no_data":
            self = .noData
        case "unavailable":
            self = .unavailable
        case "partial":
            self = .partial
        default:
            self = .unknown(rawValue)
        }
    }
}

struct SpeciesObservationMonthCount: Decodable, Equatable, Identifiable {
    let month: Int
    let count: Int

    var id: Int { month }
    var hasObservations: Bool { count.signum() == 1 }
}

struct SpeciesObservationHistoryCount: Decodable, Equatable, Identifiable {
    let year: Int
    let month: Int
    let count: Int

    var id: String { "\(year)-\(month)" }
    var hasObservations: Bool { count.signum() == 1 }

    var date: Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = 1
        return components.date ?? .distantPast
    }
}

struct SpeciesObservationCategorySeries: Decodable, Equatable, Identifiable {
    let key: String
    let label: String
    let values: [SpeciesObservationMonthCount]

    var id: String { key }
}
