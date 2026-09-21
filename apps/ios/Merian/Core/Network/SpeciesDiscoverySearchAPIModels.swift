import Foundation

enum SpeciesSearchResultKind: String, Codable, CaseIterable { case species, sightings }
enum SpeciesSearchGroup: String, Codable, CaseIterable {
    case plants, birds, insects, fungi, mammals
    case reptilesAmphibians = "reptiles_amphibians"
    var title: String {
        self == .reptilesAmphibians ? "Reptiles & amphibians" : rawValue.capitalized
    }
}
enum SpeciesSearchMedia: String, Codable, CaseIterable {
    case image, video, audio
    var title: String { self == .image ? "Photos" : rawValue.capitalized }
}
struct SpeciesSearchContext: Codable, Equatable {
    enum Mode: String, Codable { case name, description }
    var query: String
    var group: SpeciesSearchGroup?
    var media: SpeciesSearchMedia?
    var mode: Mode
}
struct SpeciesSearchCursor: Codable, Equatable {
    let id: String
    let rank: Double?
    let sharedAt: String?
    func encode(to encoder: Encoder) throws {
        enum Keys: String, CodingKey { case id, rank; case sharedAt = "shared_at" }
        var values = encoder.container(keyedBy: Keys.self)
        try values.encode(id, forKey: .id)
        try values.encodeIfPresent(rank, forKey: .rank)
        try values.encodeIfPresent(sharedAt, forKey: .sharedAt)
    }
}
struct SpeciesSearchRequest: Encodable, Equatable {
    let requestId: String
    let question: String?
    let context: SpeciesSearchContext?
    let resultKind: SpeciesSearchResultKind
    let cursor: SpeciesSearchCursor?
    enum CodingKeys: String, CodingKey {
        case requestId = "request_id", resultKind = "result_kind"
        case question, context, cursor
    }
}
struct SpeciesSearchMatch: Decodable, Equatable, Identifiable {
    let item: SpeciesDictionaryCatalogItem
    let excerpt: String
    var id: String { item.id }
}
struct SpeciesSearchResponse: Decodable {
    enum Status: String, Decodable { case results, clarification, unsupported }
    let schemaVersion: Int
    let requestId: String
    let resultKind: SpeciesSearchResultKind
    let status: Status
    let message: String
    let context: SpeciesSearchContext?
    let species: [SpeciesSearchMatch]
    let sightings: [ExplorePost]
    let nextCursor: SpeciesSearchCursor?
}
