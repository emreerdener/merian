import Foundation

struct FieldTripCaptureContextResponse: Codable, Equatable, Sendable {
    let data: [FieldTripCaptureOuting]
}

struct FieldTripCaptureOuting: Codable, Equatable, Identifiable, Sendable {
    let userFieldTripId: String
    let templateId: String
    let templateSlug: String
    let outingTitle: String
    let lastEngagedAt: String
    let levelNumber: Int
    let levelTitle: String
    let completedCount: Int
    let targetCount: Int
    let targets: [FieldTripCaptureTarget]

    var id: String { userFieldTripId }
}

struct FieldTripCaptureTarget: Codable, Equatable, Identifiable, Sendable {
    let itemId: String
    let prompt: String
    let sortOrder: Int
    let hasGuide: Bool

    var id: String { itemId }
}

struct FieldTripPreferredGoal: Codable, Equatable, Sendable {
    let userFieldTripId: String
    let itemId: String
}

struct FieldTripScanContributionsResponse: Decodable {
    let data: [FieldTripScanContribution]
}

struct FieldTripScanContribution: Decodable, Identifiable, Equatable, Sendable {
    enum SourceKind: String, Decodable, Sendable {
        case standardOuting = "standard_outing"
        case event
    }

    let sourceKind: SourceKind
    let sourceId: String
    let userFieldTripId: String?
    let participationId: String?
    let templateId: String
    let challengeId: String?
    let title: String
    let slug: String
    let itemId: String
    let prompt: String
    let levelNumber: Int
    let levelTitle: String?
    let completedCount: Int
    let targetCount: Int
    let isComplete: Bool
    let artworkPrompt: String
    let artworkTemplateSlug: String?
    let destinationKind: String
    let destinationTemplateId: String?
    let destinationChecklistItemId: String?
    let destinationChallengeId: String?

    var id: String { "\(sourceKind.rawValue):\(sourceId)" }
}
