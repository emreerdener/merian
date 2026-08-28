import SwiftData

@MainActor
struct ScansShellDataStore {
    struct Dependencies {
        let eradicateScan: @MainActor (
            _ record: LocalScanRecord,
            _ modelContext: ModelContext
        ) -> Void

        @MainActor
        static var live: Self {
            let repository = AppDIContainer.shared.scanRepository
            return Self(
                eradicateScan: { record, modelContext in
                    repository.eradicateScan(
                        record: record,
                        modelContext: modelContext
                    )
                }
            )
        }
    }

    struct QueuedSnapshotResult {
        let snapshots: [QueuedScanSnapshot]
        let fetchedCount: Int
        let completedCount: Int
        let stateSummary: String
        let visibleIDSummary: String
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies? = nil) {
        self.dependencies = dependencies ?? .live
    }

    /// Reads the live queue through a fresh context and projects every row to a
    /// value snapshot before SwiftData can detach a deleted backing model.
    func queuedSnapshots(in modelContainer: ModelContainer) -> QueuedSnapshotResult {
        let readContext = ModelContext(modelContainer)
        let firstNonRunnableRaw = ScanQueueState.externalImport.rawValue
        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate<OfflineQueuedScan> {
                $0.scanStateRaw < firstNonRunnableRaw || $0.queueNeedsAttention
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let fetched = (try? readContext.fetch(descriptor)) ?? []
        let queuedIDs = fetched.map(\.id)

        let completedIDs: Set<String>
        if queuedIDs.isEmpty {
            completedIDs = []
        } else {
            let recordDescriptor = FetchDescriptor<LocalScanRecord>(
                predicate: #Predicate<LocalScanRecord> {
                    queuedIDs.contains($0.id)
                }
            )
            completedIDs = Set(
                ((try? readContext.fetch(recordDescriptor)) ?? []).map(\.id)
            )
        }

        let visibleQueuedScans = fetched.filter {
            !completedIDs.contains($0.id)
        }
        let snapshots = visibleQueuedScans.map(Self.snapshot)

        return QueuedSnapshotResult(
            snapshots: snapshots,
            fetchedCount: fetched.count,
            completedCount: completedIDs.count,
            stateSummary: Dictionary(grouping: fetched, by: \.scanStateRaw)
                .map { "\($0.key):\($0.value.count)" }
                .sorted()
                .joined(separator: ","),
            visibleIDSummary: visibleQueuedScans.map(\.id).joined(separator: ",")
        )
    }

    func biologicalRecords(in modelContext: ModelContext) -> [LocalScanRecord] {
        let descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate<LocalScanRecord> {
                $0.isBiological == true
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func selectedRecords(
        ids: Set<String>,
        limit: Int,
        in modelContext: ModelContext
    ) -> [LocalScanRecord] {
        let selectedIDs = Array(ids)
        guard !selectedIDs.isEmpty else { return [] }

        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate<LocalScanRecord> {
                selectedIDs.contains($0.id)
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = min(selectedIDs.count, limit)
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func delete(
        records: [LocalScanRecord],
        in modelContext: ModelContext
    ) {
        for record in records {
            dependencies.eradicateScan(record, modelContext)
        }
    }

    private static func snapshot(
        from queuedScan: OfflineQueuedScan
    ) -> QueuedScanSnapshot {
        let capturedMediaItems = queuedScan.serializedCapturedMediaItems
        return QueuedScanSnapshot(
            id: queuedScan.id,
            imagePath: queuedScan.coverImagePath,
            capturedMediaJSON: CapturedMediaSnapshot(
                items: capturedMediaItems
            ).jsonString,
            queueState: queuedScan.queueState,
            timestamp: queuedScan.timestamp,
            queueNextRetryAt: queuedScan.queueNextRetryAt,
            queueLastErrorMessage: queuedScan.queueLastErrorMessage,
            queueNeedsAttention: queuedScan.queueNeedsAttention,
            approximateQueuedBytes: QueuedScanContext.approximateQueuedBytes(
                mediaItems: capturedMediaItems,
                inferenceImagePaths: queuedScan.inferenceImagePaths
            )
        )
    }
}
