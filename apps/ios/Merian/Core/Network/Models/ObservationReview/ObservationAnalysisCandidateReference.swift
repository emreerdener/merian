import Foundation

/// Exact immutable member, not a display-array offset or a name-based lookup.
struct ObservationAnalysisCandidateReference: Encodable, Equatable, Sendable {
    let analysisID: UUID
    let ordinal: Int
    let scientificName: String

    init(analysisID: UUID, ordinal: Int, scientificName: String) throws {
        guard (0...1).contains(ordinal), ObservationAnalysisReviewRequest.isScientificName(scientificName) else {
            throw MerianError.invalidResponse
        }
        self.analysisID = analysisID; self.ordinal = ordinal; self.scientificName = scientificName
    }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.analysisID == rhs.analysisID && lhs.ordinal == rhs.ordinal && lhs.scientificName.utf8.elementsEqual(rhs.scientificName.utf8)
    }
    enum CodingKeys: String, CodingKey {
        case version, analysisID = "analysis_id", representation, ordinal
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(1, forKey: .version)
        try values.encode(analysisID.uuidString.lowercased(), forKey: .analysisID)
        try values.encode("stored_species_candidates_v1", forKey: .representation)
        try values.encode(ordinal, forKey: .ordinal)
    }
    static func decode(_ value: Any?, scientificName: String) throws -> Self {
        guard let row = value as? [String: Any], Set(row.keys) == ["version", "analysis_id", "representation", "ordinal"],
              try ObservationAnalysisReviewWire.integer(row["version"]) == 1,
              row["representation"] as? String == "stored_species_candidates_v1" else { throw MerianError.invalidResponse }
        return try .init(analysisID: ObservationAnalysisReviewWire.uuid(row["analysis_id"]),
                         ordinal: ObservationAnalysisReviewWire.integer(row["ordinal"]), scientificName: scientificName)
    }
}
