import SwiftData

struct InferenceReviewSnapshot: Equatable, Sendable {
    let speciesId: String
    let aiReasoning: String?
}

struct InferenceReviewSnapshotService {
    typealias Load = @MainActor (
        _ scanId: String,
        _ modelContext: ModelContext
    ) throws -> InferenceReviewSnapshot?

    let load: Load

    static let live = InferenceReviewSnapshotService(
        load: { scanId, modelContext in
            var descriptor = FetchDescriptor<LocalScanRecord>(
                predicate: #Predicate { $0.id == scanId }
            )
            descriptor.fetchLimit = 1
            return try modelContext.fetch(descriptor).first.map {
                InferenceReviewSnapshot(
                    speciesId: $0.speciesId,
                    aiReasoning: $0.aiReasoning
                )
            }
        }
    )
}
