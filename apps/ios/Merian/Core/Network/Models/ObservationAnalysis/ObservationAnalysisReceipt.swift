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
