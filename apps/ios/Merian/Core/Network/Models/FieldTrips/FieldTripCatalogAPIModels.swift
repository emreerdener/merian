import Foundation

struct FieldTripsCatalogResponse: Decodable {
    let data: [FieldTripTemplate]
}

struct FieldTripTemplateDetailResponse: Decodable {
    let data: FieldTripTemplate
}

struct FieldTripStartResponse: Decodable {
    let data: FieldTripTemplate
}

struct FieldTripTemplate: Decodable, Identifiable, Equatable, Sendable {
    let templateId: String
    let slug: String
    let title: String
    let subtitle: String?
    let description: String?
    let coverImageUrl: String?
    let estimatedDurationMinutes: Int?
    let guideWhereToLook: String?
    let guideWhyItMatters: String?
    let guideSafetyEthics: String?
    let regionTags: [String]
    let seasonTags: [String]
    let habitatTags: [String]
    let difficulty: String
    let isProOnly: Bool
    let isRotatingFree: Bool
    let viewerHasAccess: Bool
    let accessKind: String
    let activeProgress: FieldTripProgress?
    let stoppedProgress: FieldTripProgress?
    let levels: [FieldTripLevel]

    var id: String { templateId }
}

struct FieldTripLevel: Decodable, Identifiable, Equatable, Sendable {
    let levelId: String
    let levelNumber: Int
    let title: String
    let description: String?
    let items: [FieldTripChecklistItem]

    var id: String { levelId }
}

struct FieldTripChecklistItem: Decodable, Identifiable, Equatable, Sendable {
    let itemId: String
    let prompt: String
    let matchType: String
    let guideTip: String?
    let guide: FieldTripChecklistItemGuide?
    let referenceSpecies: FieldTripReferenceSpecies?
    let isCompleted: Bool
    let completedAt: String?
    let completedCommonName: String?
    let completedScientificName: String?
    let completedScanId: String?

    var id: String { itemId }
}

struct FieldTripReferenceSpecies: Decodable, Equatable, Sendable {
    let scientificName: String
    let commonName: String
    let referenceImages: [SpeciesDictionaryReferenceImage]
}

struct FieldTripChecklistItemGuide: Decodable, Equatable, Sendable {
    let whereToLook: String?
    let bestConditions: String?
    let whatToNotice: String?
    let scanSafely: String?
}
