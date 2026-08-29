import SwiftData

@MainActor
struct ScanDeletionService {
    enum Result: Equatable {
        case notRequested
        case alreadyAbsent
        case deleted

        var shouldCompletePresentation: Bool {
            self != .notRequested
        }
    }

    struct Dependencies {
        let findRecord: @MainActor (
            _ scanID: String,
            _ modelContext: ModelContext
        ) -> LocalScanRecord?
        let eradicateRecord: @MainActor (
            _ record: LocalScanRecord,
            _ modelContext: ModelContext
        ) -> Void
        let triggerDestructiveFeedback: @MainActor () -> Void

        @MainActor
        static var live: Self {
            let container = AppDIContainer.shared
            return Self(
                findRecord: { scanID, modelContext in
                    var descriptor = FetchDescriptor<LocalScanRecord>(
                        predicate: #Predicate { $0.id == scanID }
                    )
                    descriptor.fetchLimit = 1
                    return try? modelContext.fetch(descriptor).first
                },
                eradicateRecord: { record, modelContext in
                    container.scanRepository.eradicateScan(
                        record: record,
                        modelContext: modelContext
                    )
                },
                triggerDestructiveFeedback: {
                    container.hapticManager.triggerErrorThump()
                }
            )
        }
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies? = nil) {
        self.dependencies = dependencies ?? .live
    }

    func delete(
        scanID: String?,
        in modelContext: ModelContext
    ) -> Result {
        guard let scanID else { return .notRequested }
        guard let record = dependencies.findRecord(
            scanID,
            modelContext
        ) else {
            return .alreadyAbsent
        }

        dependencies.triggerDestructiveFeedback()
        dependencies.eradicateRecord(record, modelContext)
        return .deleted
    }
}
