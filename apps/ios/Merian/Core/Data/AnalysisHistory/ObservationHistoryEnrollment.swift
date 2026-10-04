import Foundation

/// An ownership/import receipt, never proof of current selection or authority.
struct ObservationHistoryEnrollment {
    let baselineAnalysisID: UUID

    static func decode(_ data: Data, observationID: UUID, ownerID: UUID) throws -> Self {
        guard data.count <= 4096 else { throw ObservationHistoryError.invalidPage }
        let row = try ObservationHistoryPage.object(JSONSerialization.jsonObject(with: data),
            keys: ["schema_version", "owner_id", "observation_id", "baseline_analysis_id"])
        guard try ObservationHistoryPage.integer(row["schema_version"]) == 1,
              try ObservationHistoryPage.uuid(row["owner_id"]) == ownerID,
              try ObservationHistoryPage.uuid(row["observation_id"]) == observationID else {
            throw ObservationHistoryError.invalidPage
        }
        let baseline = try ObservationHistoryPage.uuid(row["baseline_analysis_id"])
        guard baseline != ownerID, baseline != observationID else { throw ObservationHistoryError.invalidPage }
        return Self(baselineAnalysisID: baseline)
    }
}
