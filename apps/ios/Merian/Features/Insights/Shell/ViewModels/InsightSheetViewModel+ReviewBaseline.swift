import SwiftData

extension InsightSheetViewModel {
    /// Capture before the synchronous historical load. A rejected Auth-fenced load
    /// cannot authorize a new baseline just because the scan ID still matches.
    func loadSelectedReviewProjection(_ record: LocalScanRecord, inferenceEngine: InferenceEngine) -> SelectedAnalysisReviewBaseline? {
        let baseline = SelectedAnalysisReviewBaseline(scanID: record.id, ownerID: record.analysisOwnerAccountID,
            analysisID: record.selectedAnalysisID, revision: record.observationStateRevision)
        let generation = inferenceEngine.scanPresentationGeneration
        inferenceEngine.load(from: record)
        guard inferenceEngine.scanPresentationGeneration != generation,
              inferenceEngine.activeScanId?.caseInsensitiveCompare(record.id) == .orderedSame,
              inferenceEngine.speciesData?.scanId?.caseInsensitiveCompare(record.id) == .orderedSame else { return nil }
        return baseline
    }
}
