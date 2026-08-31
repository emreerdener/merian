import SwiftData

extension InsightSheetViewModel {
    func contentFactManager() -> FactManager {
        contentDependencies.factManager()
    }

    func performContentSelectionFeedback() {
        dependencies.selectionFeedback()
    }

    func performContentHeaderRevealFeedback() {
        contentDependencies.headerRevealFeedback()
    }

    func performFieldTripOpenFeedback() {
        contentDependencies.fieldTripOpenFeedback()
    }

    func openNonBiologicalScans() {
        dependencies.selectionFeedback()
        dependencies.requestNonBiologicalScans()
    }

    @discardableResult
    func requestRefinement(
        expectedScanId: String,
        expectedGeneration: UInt64,
        modelContext: ModelContext
    ) -> Bool {
        guard isPresentingLocalRecord(
            scanId: expectedScanId,
            generation: expectedGeneration
        ), inferenceEngine?.speciesData?.scanId?
            .caseInsensitiveCompare(expectedScanId) == .orderedSame else {
            return false
        }

        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == expectedScanId }
        )
        descriptor.fetchLimit = 1
        guard let record = try? modelContext.fetch(descriptor).first else {
            return false
        }

        dependencies.selectionFeedback()
        dependencies.requestRefinement(record.id, shareableFieldNotes)
        return true
    }
}
