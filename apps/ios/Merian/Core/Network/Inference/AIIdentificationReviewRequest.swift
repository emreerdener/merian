import Foundation

struct AIIdentificationReviewRequest: Codable, Equatable, Sendable {
    enum Action: String, Codable, Sendable { case carry, reject, undo, confirmPrimary = "confirm_primary", confirmName = "confirm_name" }
    let scanID: String
    let expectedRevision: Int
    let operationID: String
    let action: Action
    let scientificName: String?
    let expectedSpeciesReviewRevision: Int?
    var sourceScanID: String?
    var sourceRevision: Int?
    enum CodingKeys: String, CodingKey {
        case sourceScanID = "source_scan_id", sourceRevision = "source_revision"
        case scanID = "scan_id", expectedRevision = "expected_revision", operationID = "operation_id", action
        case scientificName = "scientific_name", expectedSpeciesReviewRevision = "expected_species_review_revision"
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(scanID, forKey: .scanID); try values.encode(expectedRevision, forKey: .expectedRevision)
        try values.encode(operationID, forKey: .operationID); try values.encode(action, forKey: .action)
        try values.encode(expectedSpeciesReviewRevision, forKey: .expectedSpeciesReviewRevision)
        if action == .carry {
            try values.encode(sourceScanID, forKey: .sourceScanID); try values.encode(sourceRevision, forKey: .sourceRevision)
        }
        if action == .confirmName { try values.encode(scientificName, forKey: .scientificName) }
    }
}
struct AIIdentificationReviewReceipt: Decodable, Sendable {
    let schemaVersion: Int
    let scanID: String
    let review: AIIdentificationReview
    let speciesReview: ConfirmedSpeciesReview?
    let confirmedSpeciesID: String?
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", scanID = "scan_id", review, speciesReview = "species_review", confirmedSpeciesID = "confirmed_species_id"
    }
}
