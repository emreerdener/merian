import Foundation

/// Identity of an acknowledged projection actually loaded into the visible engine.
/// Metadata refreshes must preserve this value instead of adopting a newer row.
struct SelectedAnalysisReviewBaseline: Equatable, Hashable {
    let observationID: UUID
    let ownerID: UUID
    let analysisID: UUID
    let revision: Int

    init?(scanID: String, ownerID: String?, analysisID: String?, revision: Int?) {
        guard let observation = UUID(uuidString: scanID), let ownerID, let owner = UUID(uuidString: ownerID),
              let analysisID, let analysis = UUID(uuidString: analysisID), let revision,
              revision > 0, revision <= 2_147_483_647 else { return nil }
        observationID = observation; self.ownerID = owner; self.analysisID = analysis; self.revision = revision
    }
}
