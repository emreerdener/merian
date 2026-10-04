import Foundation

/// Exact identity of the prepared private server selection transaction.
struct ObservationHistorySelectionRequest: Codable, Equatable {
    let schema_version: Int
    let observation_id: String
    let analysis_id: String
    let operation_id: String
    let expected_observation_revision: Int
    let expected_review_revision: Int

    init(observation: UUID, analysis: UUID, operation: UUID = UUID(), revision: Int, review: Int) {
        schema_version = 1
        observation_id = observation.uuidString.lowercased()
        analysis_id = analysis.uuidString.lowercased()
        operation_id = operation.uuidString.lowercased()
        expected_observation_revision = revision
        expected_review_revision = review
    }

    func validate() throws {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(self))
        let row = try ObservationHistoryPage.object(object, keys: ["schema_version", "observation_id", "analysis_id",
            "operation_id", "expected_observation_revision", "expected_review_revision"])
        for key in ["observation_id", "analysis_id", "operation_id"] { _ = try ObservationHistoryPage.uuid(row[key]) }
        guard schema_version == 1, observation_id != analysis_id,
              expected_observation_revision > 0, expected_observation_revision < 2_147_483_646,
              expected_review_revision >= 0, expected_review_revision <= expected_observation_revision else {
            throw ObservationHistoryError.invalidPage
        }
    }
}

struct ObservationHistorySelectionReceipt: Codable, Equatable {
    let schema_version: Int
    let operation_id: String
    let observation_id: String
    let previous_analysis_id: String
    let selected_analysis_id: String
    let observation_revision: Int
    let review_revision: Int

    static func decode(_ data: Data, request: ObservationHistorySelectionRequest, previous: String) throws -> Self {
        guard data.count <= 4_096 else { throw ObservationHistoryError.invalidPage }
        let row = try ObservationHistoryPage.object(JSONSerialization.jsonObject(with: data), keys:
            ["schema_version", "operation_id", "observation_id", "previous_analysis_id", "selected_analysis_id",
             "observation_revision", "review_revision"])
        for key in ["operation_id", "observation_id", "previous_analysis_id", "selected_analysis_id"] {
            _ = try ObservationHistoryPage.uuid(row[key])
        }
        _ = try ObservationHistoryPage.integer(row["schema_version"])
        _ = try ObservationHistoryPage.integer(row["observation_revision"])
        _ = try ObservationHistoryPage.integer(row["review_revision"])
        let receipt = try JSONDecoder().decode(Self.self, from: data)
        try request.validate()
        guard receipt.schema_version == 1, receipt.operation_id == request.operation_id,
              receipt.observation_id == request.observation_id, receipt.previous_analysis_id == previous,
              receipt.selected_analysis_id == request.analysis_id,
              receipt.observation_revision == request.expected_observation_revision + 1,
              receipt.review_revision == request.expected_review_revision else { throw ObservationHistoryError.invalidPage }
        return receipt
    }
}

/// Durable proof that this exact operation can never apply. It is not current
/// identification authority; the caller still reads and admits current state.
struct ObservationHistorySelectionRejection: Codable, Equatable {
    let schema_version: Int
    let operation_id: String
    let observation_id: String
    let analysis_id: String
    let expected_observation_revision: Int
    let expected_review_revision: Int
    let outcome: String

    static func decode(_ data: Data, request: ObservationHistorySelectionRequest) throws -> Self {
        guard data.count <= 4_096 else { throw ObservationHistoryError.invalidPage }
        let row = try ObservationHistoryPage.object(JSONSerialization.jsonObject(with: data), keys:
            ["schema_version", "operation_id", "observation_id", "analysis_id", "expected_observation_revision",
             "expected_review_revision", "outcome"])
        for key in ["schema_version", "expected_observation_revision", "expected_review_revision"] {
            _ = try ObservationHistoryPage.integer(row[key])
        }
        let rejected = try JSONDecoder().decode(Self.self, from: data)
        try request.validate()
        guard rejected.schema_version == 1, rejected.outcome == "revision_conflict",
              rejected.operation_id == request.operation_id, rejected.observation_id == request.observation_id,
              rejected.analysis_id == request.analysis_id,
              rejected.expected_observation_revision == request.expected_observation_revision,
              rejected.expected_review_revision == request.expected_review_revision else { throw ObservationHistoryError.invalidPage }
        return rejected
    }
}

enum ObservationHistorySelectionOutcome: Equatable {
    case selected(ObservationHistorySelectionReceipt)
    case rejected(ObservationHistorySelectionRejection)

    static func decode(_ data: Data, request: ObservationHistorySelectionRequest, previous: String) throws -> Self {
        guard data.count <= 4_096 else { throw ObservationHistoryError.invalidPage }
        let row = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if row?["outcome"] != nil { return .rejected(try .decode(data, request: request)) }
        return .selected(try .decode(data, request: request, previous: previous))
    }
}
