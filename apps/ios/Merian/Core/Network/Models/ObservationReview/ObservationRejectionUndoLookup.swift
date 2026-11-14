import Foundation

struct ObservationRejectionUndoLookup: Equatable, Sendable {
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

struct ObservationRejectionUndoReply: Equatable, Sendable {
    enum Reason: String, Sendable {
        case communityAuthority = "community_authority", notRejected = "not_rejected", receiptUnavailable = "receipt_unavailable"
        case rejectionChanged = "rejection_changed", revisionConflict = "revision_conflict"
        var message: String {
            switch self {
            case .communityAuthority: "A community decision cannot be undone as your rejection."
            case .notRejected: "This identification is not currently marked incorrect by you."
            case .receiptUnavailable: "The original rejection record is unavailable, so it cannot be undone."
            case .rejectionChanged, .revisionConflict: "This identification changed. Open it again before undoing rejection."
            }
        }
    }
    enum Outcome: Equatable, Sendable {
        case available(UUID), unavailable(Reason)
    }
    let request: ObservationRejectionUndoLookup
    let outcome: Outcome

    init(data: Data, request: ObservationRejectionUndoLookup) throws {
        _ = try request.object()
        let row = try ObservationAnalysisReviewWire.object(data, limit: 4096)
        let available = row["status"] as? String == "available"
        guard available || row["status"] as? String == "unavailable",
              Set(row.keys) == ObservationRejectionUndoLookup.keys.union(available
                ? ["status", "rejection_operation_id"] : ["status", "reason"]),
              try ObservationAnalysisReviewWire.integer(row["schema_version"]) == 1,
              try ObservationAnalysisReviewWire.uuid(row["observation_id"]) == request.observationID,
              try ObservationAnalysisReviewWire.uuid(row["analysis_id"]) == request.analysisID,
              try ObservationAnalysisReviewWire.integer(row["expected_observation_revision"]) == request.observationRevision,
              try ObservationAnalysisReviewWire.integer(row["expected_review_revision"]) == request.reviewRevision else {
            throw MerianError.invalidResponse
        }
        self.request = request
        if available {
            outcome = .available(try ObservationAnalysisReviewWire.uuid(row["rejection_operation_id"]))
        } else {
            guard let raw = row["reason"] as? String, let reason = Reason(rawValue: raw) else { throw MerianError.invalidResponse }
            outcome = .unavailable(reason)
        }
    }
}
