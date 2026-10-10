import SwiftData

extension InsightSheetViewModel {
    /// Only admitted selected state may refresh the ordinary Insight. A preview
    /// never enters the inference engine, and a replaced route cannot be reloaded.
    @discardableResult
    func refreshAcknowledgedHistory(scanId: String, generation: UInt64, container: ModelContainer, inferenceEngine: InferenceEngine,
                                    expected: SelectedAnalysisReviewBaseline? = nil) -> SelectedAnalysisReviewBaseline? {
        guard isPresentingLocalRecord(scanId: scanId, generation: generation) else { return nil }
        let context = ModelContext(container)
        guard let record = try? ObservationHistorySyncService.enrolledScan(scanId, context: context),
              record.analysisOwnerAccountID?.caseInsensitiveCompare(dependencies.authenticationSnapshot().accountID ?? "") == .orderedSame else { return nil }
        if let expected {
            guard SelectedAnalysisReviewBaseline(scanID: record.id, ownerID: record.analysisOwnerAccountID,
                analysisID: record.selectedAnalysisID, revision: record.observationStateRevision) == expected else { return nil }
        }
        let baseline = loadSelectedReviewProjection(record, inferenceEngine: inferenceEngine)
        bindPresentedRecord(record, modelContext: context, selectedReviewBaseline: baseline)
        return baseline
    }
}
