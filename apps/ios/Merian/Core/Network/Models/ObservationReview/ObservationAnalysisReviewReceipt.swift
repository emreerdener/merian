import CoreFoundation
import Foundation

/// Historical outcome only. Current target and selected state must be reconciled separately.
struct ObservationAnalysisReviewReceipt: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        case applied(observationRevision: Int, reviewRevision: Int), revisionConflict, notVerified
    }
    let request: ObservationAnalysisReviewRequest
    let outcome: Outcome
    private init(request: ObservationAnalysisReviewRequest, outcome: Outcome) {
        self.request = request; self.outcome = outcome
    }
    /// Canonical owner-private receipt storage; decoding still verifies the full request binding.
    func encoded() throws -> Data {
        var row = try ObservationAnalysisReviewWire.object(request.encoded(), limit: 2048)
        switch outcome {
        case let .applied(observation, review):
            row["outcome"] = "applied"; row["observation_revision"] = observation; row["review_revision"] = review
        case .revisionConflict: row["outcome"] = "revision_conflict"
        case .notVerified: row["outcome"] = "not_verified"
        }
        let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        guard data.count <= 4096 else { throw MerianError.invalidResponse }
        return data
    }
    static func decode(_ data: Data, request: ObservationAnalysisReviewRequest) throws -> Self {
        let row = try ObservationAnalysisReviewWire.object(data, limit: 4096)
        guard let raw = row["outcome"] as? String,
              raw == "applied" || raw == "revision_conflict" || (raw == "not_verified" && request.decision.isConfirmation) else {
            throw MerianError.invalidResponse
        }
        let requestKeys = ObservationAnalysisReviewRequest.keys(confirmation: request.decision.isConfirmation, candidate: request.decision.isCandidate)
        let extra: Set<String> = raw == "applied" ? ["outcome", "observation_revision", "review_revision"] : ["outcome"]
        guard Set(row.keys) == requestKeys.union(extra),
              try ObservationAnalysisReviewRequest.decode(row.filter { requestKeys.contains($0.key) }) == request else {
            throw MerianError.invalidResponse
        }
        let outcome: Outcome
        switch raw {
        case "applied":
            let observation = try ObservationAnalysisReviewWire.integer(row["observation_revision"])
            let review = try ObservationAnalysisReviewWire.integer(row["review_revision"])
            guard observation == request.expectedObservationRevision + 1, review == request.expectedReviewRevision + 1 else {
                throw MerianError.invalidResponse
            }
            outcome = .applied(observationRevision: observation, reviewRevision: review)
        case "revision_conflict": outcome = .revisionConflict
        default: outcome = .notVerified
        }
        return Self(request: request, outcome: outcome)
    }
}

enum ObservationAnalysisReviewWire {
    static func object(_ data: Data, limit: Int) throws -> [String: Any] {
        guard data.count <= limit, let row = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MerianError.invalidResponse
        }
        return row
    }
    static func uuid(_ value: Any?) throws -> UUID {
        guard let text = value as? String, let id = UUID(uuidString: text), text == id.uuidString.lowercased() else {
            throw MerianError.invalidResponse
        }
        return id
    }
    static func integer(_ value: Any?) throws -> Int {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0, number.doubleValue <= 2_147_483_646,
              number.doubleValue.rounded() == number.doubleValue else { throw MerianError.invalidResponse }
        return number.intValue
    }
}
