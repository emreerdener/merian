import Foundation

struct SpeciesPreferenceCloudRow: Decodable, Equatable, Sendable {
    let scientific_name: String
    let preferred_common_name: String?
    let updated_at: String
    let deleted_at: String?
}

struct SpeciesPreferenceCloudUpsert: Encodable, Equatable, Sendable {
    let user_id: String
    let scientific_name: String
    let preferred_common_name: String?
    let deleted_at: String?

    enum CodingKeys: String, CodingKey {
        case user_id
        case scientific_name
        case preferred_common_name
        case deleted_at
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(user_id, forKey: .user_id)
        try container.encode(scientific_name, forKey: .scientific_name)

        if let preferred_common_name {
            try container.encode(
                preferred_common_name,
                forKey: .preferred_common_name
            )
        } else {
            try container.encodeNil(forKey: .preferred_common_name)
        }

        if let deleted_at {
            try container.encode(deleted_at, forKey: .deleted_at)
        } else {
            try container.encodeNil(forKey: .deleted_at)
        }
    }
}
