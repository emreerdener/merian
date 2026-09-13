import Foundation

enum ExploreMediaHealthStatus: String, Decodable, Equatable, Sendable {
    case degraded
    case quarantined
}

struct ExploreMediaIncident: Decodable, Identifiable, Equatable, Sendable {
    let postId: String
    let scanId: String
    let speciesCommonName: String?
    let mediaHealthStatus: ExploreMediaHealthStatus
    let missingMediaCount: Int
    let totalMediaCount: Int
    let mediaQuarantinedAt: String?
    let mediaHealthUpdatedAt: String
    let missingMediaUrls: [String]

    var id: String { postId }
}

struct ExploreMediaIncidentsResponse: Decodable {
    let data: [ExploreMediaIncident]

    private enum CodingKeys: String, CodingKey {
        case data
    }

    init(from decoder: Decoder) throws {
        // The current handler returns {"data":[...]}; an older deployed
        // handler returned the array directly. Accept both exact shapes so an
        // empty legacy [] remains a valid no-incidents result during rollout.
        if let legacyData = try? decoder.singleValueContainer()
            .decode([ExploreMediaIncident].self) {
            data = legacyData
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode([ExploreMediaIncident].self, forKey: .data)
    }
}
