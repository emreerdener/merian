import Foundation

/// Execution state only. A completed analysis is read through owner history, never synthesized here.
struct ObservationAnalysisReceipt: Sendable, Equatable {
    enum State: String, Sendable, CaseIterable {
        case admitted, dispatched, draft, complete
        case failedTerminal = "failed_terminal"
    }
    let observationID: UUID
    let analysisID: UUID
    let state: State

    static func decode(_ data: Data, request: ObservationReanalysisRequest) throws -> Self {
        guard data.count <= 4096,
              let row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(row.keys) == ["schema_version", "observation_id", "analysis_id", "state"],
              let version = row["schema_version"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 1,
              row["observation_id"] as? String == request.observationID.uuidString.lowercased(),
              row["analysis_id"] as? String == request.analysisID.uuidString.lowercased(),
              let rawState = row["state"] as? String, let state = State(rawValue: rawState) else {
            throw MerianError.invalidResponse
        }
        return Self(observationID: request.observationID, analysisID: request.analysisID, state: state)
    }
}

/// Exact saved identity; null source supports original server-admitted analyses.
struct ObservationAnalysisExecutionLookup: Sendable, Equatable {
    let observationID: UUID
    let analysisID: UUID
    let sourceAnalysisID: UUID?
    let requestDigest: String

    init(_ saved: ObservationReanalysisRequest) {
        observationID = saved.observationID; analysisID = saved.analysisID
        sourceAnalysisID = saved.sourceAnalysisID; requestDigest = saved.requestDigest
    }

    init(observationID: UUID, analysisID: UUID, sourceAnalysisID: UUID?, requestDigest: String) throws {
        guard observationID != analysisID, sourceAnalysisID != observationID, sourceAnalysisID != analysisID,
              requestDigest.utf8.count == 64, requestDigest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw MerianError.invalidResponse
        }
        self.observationID = observationID; self.analysisID = analysisID
        self.sourceAnalysisID = sourceAnalysisID; self.requestDigest = requestDigest
    }

    func object() -> [String: Any] {
        ["schema_version": 1, "observation_id": observationID.uuidString.lowercased(),
         "analysis_id": analysisID.uuidString.lowercased(),
         "source_analysis_id": sourceAnalysisID.map { $0.uuidString.lowercased() as Any } ?? NSNull(), "request_digest": requestDigest]
    }
}

/// Read-only observation of execution, never a dispatch grant or retirement proof.
struct ObservationAnalysisExecutionStatus: Sendable, Equatable {
    enum State: String, Sendable, CaseIterable {
        case absent, admitted, dispatched, draft, complete
        case failedTerminal = "failed_terminal"
    }
    let state: State

    init(data: Data, request: ObservationAnalysisExecutionLookup, ownerID: UUID) throws {
        guard data.count <= 4096,
              let row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(row.keys) == ["schema_version", "owner_id", "observation_id", "analysis_id", "source_analysis_id", "request_digest", "state"],
              let version = row["schema_version"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 1,
              row["owner_id"] as? String == ownerID.uuidString.lowercased(),
              row["observation_id"] as? String == request.observationID.uuidString.lowercased(),
              row["analysis_id"] as? String == request.analysisID.uuidString.lowercased(),
              request.sourceAnalysisID == nil && row["source_analysis_id"] is NSNull ||
                  request.sourceAnalysisID != nil && row["source_analysis_id"] as? String == request.sourceAnalysisID?.uuidString.lowercased(),
              row["request_digest"] as? String == request.requestDigest,
              let raw = row["state"] as? String, let state = State(rawValue: raw) else {
            throw MerianError.invalidResponse
        }
        self.state = state
    }
}

/// One retained retirement identity. Creating this value grants no mutation authority.
struct ObservationAnalysisRetirementRequest: Sendable, Equatable {
    let operationID: UUID
    let execution: ObservationAnalysisExecutionLookup
    let body: Data

    init(operationID: UUID, execution: ObservationAnalysisExecutionLookup) throws {
        guard operationID != execution.observationID, operationID != execution.analysisID,
              operationID != execution.sourceAnalysisID else { throw MerianError.invalidResponse }
        self.operationID = operationID; self.execution = execution
        body = try JSONSerialization.data(withJSONObject: execution.object().merging([
            "operation_id": operationID.uuidString.lowercased()
        ]) { _, value in value }, options: [.sortedKeys])
        guard body.count <= 2048 else { throw MerianError.invalidResponse }
    }

    init(savedBody: Data) throws {
        guard savedBody.count <= 2048,
              let row = try JSONSerialization.jsonObject(with: savedBody) as? [String: Any],
              Set(row.keys) == ["schema_version", "operation_id", "observation_id", "analysis_id", "source_analysis_id", "request_digest"],
              let version = row["schema_version"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 1,
              let digest = row["request_digest"] as? String else { throw MerianError.invalidResponse }
        func uuid(_ key: String) throws -> UUID {
            guard let text = row[key] as? String, let value = UUID(uuidString: text), value.uuidString.lowercased() == text else {
                throw MerianError.invalidResponse
            }
            return value
        }
        let source: UUID? = row["source_analysis_id"] is NSNull ? nil : try uuid("source_analysis_id")
        let execution = try ObservationAnalysisExecutionLookup(observationID: uuid("observation_id"), analysisID: uuid("analysis_id"),
                                                              sourceAnalysisID: source, requestDigest: digest)
        try self.init(operationID: uuid("operation_id"), execution: execution)
        guard body == savedBody else { throw MerianError.invalidResponse }
    }
}

/// Exact terminal server proof; neither an error nor absent status can create this value.
struct ObservationAnalysisRetirementReceipt: Sendable, Equatable {
    let request: ObservationAnalysisRetirementRequest
    let data: Data

    init(data: Data, request: ObservationAnalysisRetirementRequest) throws {
        guard data.count <= 4096,
              var row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(row.keys) == ["schema_version", "operation_id", "observation_id", "analysis_id", "source_analysis_id", "request_digest", "state"],
              row.removeValue(forKey: "state") as? String == "retired_before_dispatch",
              try ObservationAnalysisRetirementRequest(savedBody: JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])) == request else {
            throw MerianError.invalidResponse
        }
        self.request = request; self.data = data
    }
}
