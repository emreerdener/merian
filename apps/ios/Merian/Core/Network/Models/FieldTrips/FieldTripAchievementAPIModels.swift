import Foundation

struct FirstFieldTripAwardResponse: Decodable {
    let data: FirstFieldTripAchievementProgress?
}

struct FirstFieldTripAchievementProgress: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case standardOuting = "standard_outing"
        case seasonalChallenge = "seasonal_challenge"
    }

    let kind: Kind
    let completedAt: String
    let templateSlug: String?
    let challengeId: String?
}
