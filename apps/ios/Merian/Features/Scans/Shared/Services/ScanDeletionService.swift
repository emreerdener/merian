import SwiftData

@MainActor
struct ScanDeletionService {
    enum Result: Equatable {
        case notRequested
        case alreadyAbsent
        case deleted
        case ownershipHeld

        var shouldCompletePresentation: Bool {
            self == .alreadyAbsent || self == .deleted
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
        ) -> Bool
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
                    ) != nil
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

        guard SharedMediaConsumerAuthority.permitsLegacyScanRemoval(raw: record.mediaAuthorityRaw, consumerID: record.sharedMediaConsumerID),
              (try? SharedMediaConsumerLookup.hasScanOwner(record.id, in: modelContext)) == false else { return .ownershipHeld }
        dependencies.triggerDestructiveFeedback()
        guard dependencies.eradicateRecord(record, modelContext) else { return .ownershipHeld }
        return .deleted
    }
}
