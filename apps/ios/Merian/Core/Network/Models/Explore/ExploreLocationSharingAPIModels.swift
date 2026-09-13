import Foundation

enum ExplorePostLocationSharing: String, CaseIterable, Identifiable, Decodable, Equatable {
    case open
    case obscured
    case privateLocation = "private"

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self).lowercased()
        switch rawValue {
        case "open":
            self = .open
        case "obscured":
            self = .obscured
        case "private", "hidden":
            self = .privateLocation
        default:
            self = .obscured
        }
    }
}
