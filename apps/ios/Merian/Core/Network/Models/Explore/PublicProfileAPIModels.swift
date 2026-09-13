import Foundation

struct PublicUsernameUpdateResponse: Decodable {
    let username: String
}

struct PublicDisplayNameUpdateResponse: Decodable {
    let displayName: String
}

struct PublicAvatarUpdateResponse: Decodable {
    let avatarUrl: String
}

struct PublicUsernameAvailabilityResponse: Decodable {
    let available: Bool
    let username: String
    let error: String?
}
