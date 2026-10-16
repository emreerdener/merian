import Foundation

enum ObservationConfirmationAction: String, Sendable {
    case primary = "confirm_primary", name = "confirm_name"
}

struct ObservationConfirmationUndoLookup: Equatable, Sendable {
    let observationID: UUID
    let analysisID: UUID
    let observationRevision: Int
    let reviewRevision: Int
    static let keys: Set<String> = ["schema_version", "observation_id", "analysis_id", "expected_observation_revision", "expected_review_revision"]

    func object() throws -> [String: Any] {
        guard (0...2_147_483_646).contains(observationRevision), (0...2_147_483_646).contains(reviewRevision) else {
            throw MerianError.invalidResponse
        }
        return ["schema_version": 1, "observation_id": observationID.uuidString.lowercased(),
                "analysis_id": analysisID.uuidString.lowercased(), "expected_observation_revision": observationRevision,
                "expected_review_revision": reviewRevision]
    }
}

struct ObservationConfirmationUndoReply: Equatable, Sendable {
    enum Reason: String, Sendable {
        case communityAuthority = "community_authority", notConfirmed = "not_confirmed", receiptUnavailable = "receipt_unavailable"
        case confirmationChanged = "confirmation_changed", revisionConflict = "revision_conflict"
        var message: String {
            switch self {
            case .communityAuthority: "A community decision cannot be undone as your confirmation."
            case .notConfirmed: "This identification is not currently confirmed by you."
            case .receiptUnavailable: "The original confirmation record is unavailable, so it cannot be undone."
            case .confirmationChanged, .revisionConflict: "This identification changed. Open it again before undoing confirmation."
            }
        }
    }
    enum Outcome: Equatable, Sendable {
        case available(UUID, ObservationConfirmationAction), unavailable(Reason)
    }
    let request: ObservationConfirmationUndoLookup
    let outcome: Outcome

    init(data: Data, request: ObservationConfirmationUndoLookup) throws {
        let row = try ObservationAnalysisReviewWire.object(data, limit: 4096)
        let available = row["status"] as? String == "available"
        guard available || row["status"] as? String == "unavailable",
              Set(row.keys) == ObservationConfirmationUndoLookup.keys.union(available
                ? ["status", "confirmation_operation_id", "confirmation_action"] : ["status", "reason"]),
              try ObservationAnalysisReviewWire.integer(row["schema_version"]) == 1,
              try ObservationAnalysisReviewWire.uuid(row["observation_id"]) == request.observationID,
              try ObservationAnalysisReviewWire.uuid(row["analysis_id"]) == request.analysisID,
              try ObservationAnalysisReviewWire.integer(row["expected_observation_revision"]) == request.observationRevision,
              try ObservationAnalysisReviewWire.integer(row["expected_review_revision"]) == request.reviewRevision else {
            throw MerianError.invalidResponse
        }
        self.request = request
        if available {
            guard let raw = row["confirmation_action"] as? String, let action = ObservationConfirmationAction(rawValue: raw) else {
                throw MerianError.invalidResponse
            }
            outcome = .available(try ObservationAnalysisReviewWire.uuid(row["confirmation_operation_id"]), action)
        } else {
            guard let raw = row["reason"] as? String, let reason = Reason(rawValue: raw) else { throw MerianError.invalidResponse }
            outcome = .unavailable(reason)
        }
    }
}
