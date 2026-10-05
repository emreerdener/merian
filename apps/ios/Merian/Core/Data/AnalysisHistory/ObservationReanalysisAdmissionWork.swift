import Foundation

/// Advisory ownership is private metadata. It never changes the queue's bound-execution fields.
struct ObservationReanalysisAdmissionWork: Equatable, Sendable {
    enum Phase: String, Sendable { case filesPending = "files_pending", admissionPending = "admission_pending" }
    enum State: String, Sendable { case pending, running, waiting, held }
    enum Hold: String, Sendable { case evidenceUnavailable, consentRequired, reconciliationRequired, retryLimit }
    let preparation: ObservationReanalysisPreparationIntent
    let phase: Phase
    let state: State
    let attempt: Int
    let updatedAt: Date?
    let nextRetryAt: Date?
    let hold: Hold?

    init(preparation: ObservationReanalysisPreparationIntent, phase: Phase, state: State = .pending,
         attempt: Int = 0, updatedAt: Date? = nil, nextRetryAt: Date? = nil, hold: Hold? = nil) throws {
        guard preparation.action == .submit, (0...1_000_000).contains(attempt),
              [updatedAt, nextRetryAt].compactMap({ $0 }).allSatisfy({ $0.timeIntervalSince1970.isFinite }) else { throw MerianError.invalidResponse }
        switch state {
        case .pending: guard attempt == 0, updatedAt == nil, nextRetryAt == nil, hold == nil else { throw MerianError.invalidResponse }
        case .running: guard attempt > 0, updatedAt != nil, nextRetryAt == nil, hold == nil else { throw MerianError.invalidResponse }
        case .waiting:
            guard attempt > 0, let updatedAt, let nextRetryAt, nextRetryAt > updatedAt, hold == nil else { throw MerianError.invalidResponse }
        case .held: guard attempt > 0, updatedAt != nil, nextRetryAt == nil, hold != nil else { throw MerianError.invalidResponse }
        }
        self.preparation = preparation; self.phase = phase; self.state = state; self.attempt = attempt
        self.updatedAt = updatedAt; self.nextRetryAt = nextRetryAt; self.hold = hold
    }

    func due(now: Date, canPreflight: Bool) -> Date? {
        guard phase == .filesPending || canPreflight else { return nil }
        switch state {
        case .pending: return now
        case .running: return updatedAt
        case .waiting: return nextRetryAt
        case .held: return nil
        }
    }

    func storedData() throws -> Data {
        let row: [String: Any] = ["version": 6, "phase": phase.rawValue,
            "preparation": try JSONSerialization.jsonObject(with: preparation.storedData()),
            "state": state.rawValue, "attempt": attempt,
            "updated_at": updatedAt.map { $0.timeIntervalSince1970 as Any } ?? NSNull(),
            "next_retry_at": nextRetryAt.map { $0.timeIntervalSince1970 as Any } ?? NSNull(),
            "hold": hold.map { $0.rawValue as Any } ?? NSNull()]
        let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys, .withoutEscapingSlashes])
        guard data.count <= 1_048_576 else { throw MerianError.invalidResponse }
        return data
    }

    static func decode(_ data: Data) throws -> Self {
        if let preparation = try? ObservationReanalysisPreparationIntent.decode(data), preparation.action == .submit {
            return try .init(preparation: preparation, phase: .filesPending)
        }
        if let submitted = try? ObservationReanalysisSubmissionIntent.decode(data) {
            return try .init(preparation: submitted.preparation, phase: .admissionPending)
        }
        guard data.count <= 1_048_576, let row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(row.keys) == ["version", "phase", "preparation", "state", "attempt", "updated_at", "next_retry_at", "hold"],
              number(row["version"]) == 6,
              let phaseText = row["phase"] as? String, let phase = Phase(rawValue: phaseText),
              let stateText = row["state"] as? String, let state = State(rawValue: stateText),
              let attempt = number(row["attempt"]), (0...1_000_000).contains(attempt), attempt.rounded() == attempt,
              let preparation = row["preparation"] as? [String: Any] else { throw MerianError.invalidResponse }
        let hold: Hold?
        if row["hold"] is NSNull { hold = nil } else {
            guard let text = row["hold"] as? String, let decoded = Hold(rawValue: text) else { throw MerianError.invalidResponse }
            hold = decoded
        }
        return try .init(preparation: .decode(JSONSerialization.data(withJSONObject: preparation)), phase: phase,
            state: state, attempt: Int(attempt), updatedAt: date(row["updated_at"]), nextRetryAt: date(row["next_retry_at"]), hold: hold)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }
    private static func date(_ value: Any?) throws -> Date? {
        if value is NSNull { return nil }
        guard let value = number(value) else { throw MerianError.invalidResponse }
        return Date(timeIntervalSince1970: value)
    }
}
