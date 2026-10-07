import Foundation

/// Immutable protocol-9 decision. The durable caller supplies every identity and revision.
struct ObservationAnalysisReviewRequest: Encodable, Equatable, Sendable {
    enum Decision: Equatable, Sendable {
        case reject, undo(rejectionOperationID: UUID), undoConfirmation(confirmationOperationID: UUID), confirmPrimary, confirmName(String), confirmCandidate(ObservationAnalysisCandidateReference)
        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.reject, .reject), (.confirmPrimary, .confirmPrimary): true
            case let (.undo(left), .undo(right)), let (.undoConfirmation(left), .undoConfirmation(right)): left == right
            case let (.confirmName(left), .confirmName(right)): left.utf8.elementsEqual(right.utf8)
            case let (.confirmCandidate(left), .confirmCandidate(right)): left == right
            default: false
            }
        }
        var action: String {
            switch self {
            case .reject: "reject"
            case .undo: "undo"
            case .undoConfirmation: "undo_confirmation"
            case .confirmPrimary: "confirm_primary"
            case .confirmName, .confirmCandidate: "confirm_name"
            }
        }
        var isCandidate: Bool {
            if case .confirmCandidate = self { return true }; return false
        }
        var isConfirmation: Bool {
            switch self {
            case .confirmPrimary, .confirmName, .confirmCandidate: true
            case .reject, .undo, .undoConfirmation: false
            }
        }
    }
    let observationID: UUID
    let analysisID: UUID
    let operationID: UUID
    let expectedObservationRevision: Int
    let expectedReviewRevision: Int
    let decision: Decision

    init(observationID: UUID, analysisID: UUID, operationID: UUID,
         expectedObservationRevision: Int, expectedReviewRevision: Int, decision: Decision) throws {
        guard (0...2_147_483_646).contains(expectedObservationRevision),
              (0...2_147_483_646).contains(expectedReviewRevision) else { throw MerianError.invalidResponse }
        if case let .confirmName(name) = decision {
            guard Self.isScientificName(name) else { throw MerianError.invalidResponse }
        }
        if case let .confirmCandidate(reference) = decision, reference.analysisID != analysisID { throw MerianError.invalidResponse }
        self.observationID = observationID; self.analysisID = analysisID; self.operationID = operationID
        self.expectedObservationRevision = expectedObservationRevision; self.expectedReviewRevision = expectedReviewRevision
        self.decision = decision
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", observationID = "observation_id", analysisID = "analysis_id", operationID = "operation_id"
        case expectedObservationRevision = "expected_observation_revision", expectedReviewRevision = "expected_review_revision"
        case candidateReference = "candidate_reference"
        case action, undoOperationID = "undo_operation_id", scientificName = "scientific_name"
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(decision.isCandidate ? 2 : 1, forKey: .schemaVersion)
        try values.encode(observationID.uuidString.lowercased(), forKey: .observationID)
        try values.encode(analysisID.uuidString.lowercased(), forKey: .analysisID)
        try values.encode(operationID.uuidString.lowercased(), forKey: .operationID)
        try values.encode(expectedObservationRevision, forKey: .expectedObservationRevision)
        try values.encode(expectedReviewRevision, forKey: .expectedReviewRevision)
        try values.encode(decision.action, forKey: .action)
        switch decision {
        case .reject: try values.encodeNil(forKey: .undoOperationID)
        case let .undo(id), let .undoConfirmation(id): try values.encode(id.uuidString.lowercased(), forKey: .undoOperationID)
        case .confirmPrimary: try values.encodeNil(forKey: .scientificName)
        case let .confirmName(name): try values.encode(name, forKey: .scientificName)
        case let .confirmCandidate(reference):
            try values.encode(reference.scientificName, forKey: .scientificName)
            try values.encode(reference, forKey: .candidateReference)
        }
    }
    func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= 2048 else { throw MerianError.invalidResponse }
        return data
    }
    static func decode(_ data: Data) throws -> Self {
        try decode(ObservationAnalysisReviewWire.object(data, limit: 2048))
    }
    static func decode(_ row: [String: Any]) throws -> Self {
        guard let action = row["action"] as? String else { throw MerianError.invalidResponse }
        let confirmation = action == "confirm_primary" || action == "confirm_name"
        let version = try ObservationAnalysisReviewWire.integer(row["schema_version"])
        guard version == 1 || (version == 2 && action == "confirm_name"),
              Set(row.keys) == keys(confirmation: confirmation, candidate: version == 2) else { throw MerianError.invalidResponse }
        let decision: Decision
        switch action {
        case "reject":
            guard row["undo_operation_id"] is NSNull else { throw MerianError.invalidResponse }
            decision = .reject
        case "undo": decision = .undo(rejectionOperationID: try ObservationAnalysisReviewWire.uuid(row["undo_operation_id"]))
        case "undo_confirmation": decision = .undoConfirmation(confirmationOperationID: try ObservationAnalysisReviewWire.uuid(row["undo_operation_id"]))
        case "confirm_primary":
            guard row["scientific_name"] is NSNull else { throw MerianError.invalidResponse }
            decision = .confirmPrimary
        case "confirm_name":
            guard let name = row["scientific_name"] as? String else { throw MerianError.invalidResponse }
            decision = version == 2 ? .confirmCandidate(try .decode(row["candidate_reference"], scientificName: name)) : .confirmName(name)
        default: throw MerianError.invalidResponse
        }
        return try Self(observationID: ObservationAnalysisReviewWire.uuid(row["observation_id"]),
            analysisID: ObservationAnalysisReviewWire.uuid(row["analysis_id"]), operationID: ObservationAnalysisReviewWire.uuid(row["operation_id"]),
            expectedObservationRevision: ObservationAnalysisReviewWire.integer(row["expected_observation_revision"]),
            expectedReviewRevision: ObservationAnalysisReviewWire.integer(row["expected_review_revision"]), decision: decision)
    }
    static func keys(confirmation: Bool, candidate: Bool = false) -> Set<String> {
        let base: Set<String> = ["schema_version", "observation_id", "analysis_id", "operation_id", "expected_observation_revision",
         "expected_review_revision", "action", confirmation ? "scientific_name" : "undo_operation_id"]
        return candidate ? base.union(["candidate_reference"]) : base
    }
    static func isScientificName(_ name: String) -> Bool {
        // Match ECMAScript trim and UTF-16 length, not Swift grapheme or scalar count.
        let trim = CharacterSet(charactersIn: "\u{0009}\u{000A}\u{000B}\u{000C}\u{000D}\u{0020}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")
        return !name.isEmpty && name.utf16.count <= 160 && name == name.trimmingCharacters(in: trim)
            && !name.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
    }
}
