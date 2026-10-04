import SwiftData

extension InsightSheetViewModel {
    /// Only admitted selected state may refresh the ordinary Insight. A preview
    /// never enters the inference engine, and a replaced route cannot be reloaded.
    func refreshAcknowledgedHistory(scanId: String, generation: UInt64, container: ModelContainer, inferenceEngine: InferenceEngine) {
        guard isPresentingLocalRecord(scanId: scanId, generation: generation) else { return }
        let context = ModelContext(container)
        guard let record = try? ObservationHistorySyncService.enrolledScan(scanId, context: context),
              record.analysisOwnerAccountID?.caseInsensitiveCompare(dependencies.authenticationSnapshot().accountID ?? "") == .orderedSame else { return }
        inferenceEngine.load(from: record)
        bindPresentedRecord(record, modelContext: context)
    }
}
