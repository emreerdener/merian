import SwiftData

@ModelActor
actor IdentificationReviewDatabaseActor {
    func refinementSnapshot(
        scanId: String
    ) -> IdentificationReviewRefinementSnapshot? {
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        descriptor.propertiesToFetch = [\.id, \.fieldNotes]

        guard let record = try? modelContext.fetch(descriptor).first else {
            return nil
        }
        return IdentificationReviewRefinementSnapshot(
            scanId: record.id,
            initialDescription: record.fieldNotes
        )
    }
}
