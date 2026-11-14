import Foundation

/// Literal owner-row/job observations, never original-result or execution authority.
struct ScanObservationResponse: Decodable, Sendable, Equatable {
    enum JobStatus: String, Decodable, Sendable {
        case processing, finalizing, retrying, failedRetryable = "failed_retryable"
        case failedTerminal = "failed_terminal", complete
    }
    let version: Int
    let phase: String
    let ownerID: String
    let scanID: String
    let rowExists: Bool
    let jobStatus: JobStatus?
    let originalResult: String
    private enum CodingKeys: String, CodingKey {
        case version, phase, ownerID = "owner_id", scanID = "scan_id"
        case rowExists = "row_exists", jobStatus = "job_status", originalResult = "original_result"
    }

    static func decode(_ data: Data, ownerID: UUID, scanID: UUID) throws -> Self {
        do {
            guard data.count <= 4096,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(object.keys) == ["version", "phase", "owner_id", "scan_id", "row_exists", "job_status", "original_result"] else {
                throw MerianError.invalidResponse
            }
            let value = try JSONDecoder().decode(Self.self, from: data)
            guard value.version == 1, value.phase == "observe", value.originalResult == "unavailable",
                  value.ownerID == ownerID.uuidString.lowercased(), value.scanID == scanID.uuidString.lowercased() else {
                throw MerianError.invalidResponse
            }
            return value
        } catch { throw MerianError.invalidResponse }
    }

    static func request(ownerID: UUID, scanID: UUID) throws -> Data {
        // No top-level scan_id/scans: legacy handlers must reject before repair,
        // including versions that predate the reserved marker/header guard.
        let bytes = try JSONSerialization.data(withJSONObject: ["initial_recovery": [
            "version": 1, "phase": "observe", "original": [
                "owner_id": ownerID.uuidString.lowercased(), "scan_id": scanID.uuidString.lowercased()
            ]
        ]], options: [.sortedKeys])
        guard bytes.count <= 1024 else { throw MerianError.invalidResponse }
        return bytes
    }
}
