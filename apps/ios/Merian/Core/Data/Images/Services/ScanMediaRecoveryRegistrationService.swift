import Foundation
import SwiftData

actor ScanMediaRecoveryRegistrationService {
    private static let maximumBatchSize = 200

    struct Dependencies: Sendable {
        let hasLegacyRecoveryIndex: @Sendable () -> Bool
        let registerStrongEvidenceMappings:
            @Sendable ([LocalScanMediaRecoverySnapshot]) async -> Int
        let registerTimestampMappings:
            @Sendable ([LocalScanMediaRecoverySnapshot]) async -> Int

        static let live = Dependencies(
            hasLegacyRecoveryIndex: {
                LocalScanMediaRecoveryResolver.hasLegacyRecoveryIndex
            },
            registerStrongEvidenceMappings: { snapshots in
                LocalScanMediaRecoveryResolver
                    .registerStrongEvidenceRecoveryMappings(
                        for: snapshots
                    )
            },
            registerTimestampMappings: { snapshots in
                LocalScanMediaRecoveryResolver
                    .registerTimestampRecoveryMappings(
                        for: snapshots
                    )
            }
        )
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies = .live) {
        self.dependencies = dependencies
    }

    /// Builds process-local rescue mappings without blocking the launch actor or
    /// faulting the complete scan library into memory at once.
    ///
    /// A `nil` result means no rescue index exists. SwiftData failures throw so
    /// callers never mistake an unreadable library for an empty one.
    func registerMappings(
        in modelContainer: ModelContainer,
        batchSize: Int = 200
    ) async throws -> Int? {
        guard dependencies.hasLegacyRecoveryIndex() else { return nil }

        let boundedBatchSize = min(
            max(1, batchSize),
            Self.maximumBatchSize
        )
        let strongEvidenceCount = try await registerBatches(
            in: modelContainer,
            batchSize: boundedBatchSize,
            ordering: .scanID,
            register: dependencies.registerStrongEvidenceMappings
        )
        let timestampCount = try await registerBatches(
            in: modelContainer,
            batchSize: boundedBatchSize,
            ordering: .timestampThenScanID,
            register: dependencies.registerTimestampMappings
        )
        return strongEvidenceCount + timestampCount
    }

    private func registerBatches(
        in modelContainer: ModelContainer,
        batchSize: Int,
        ordering: SnapshotOrdering,
        register:
            @Sendable ([LocalScanMediaRecoverySnapshot]) async -> Int
    ) async throws -> Int {
        var offset = 0
        var registeredCount = 0

        while true {
            try Task.checkCancellation()
            let snapshots = try fetchSnapshots(
                in: modelContainer,
                offset: offset,
                limit: batchSize,
                ordering: ordering
            )
            guard !snapshots.isEmpty else { break }

            registeredCount += await register(snapshots)
            try Task.checkCancellation()

            offset += snapshots.count
            guard snapshots.count == batchSize else { break }
        }

        return registeredCount
    }

    private func fetchSnapshots(
        in modelContainer: ModelContainer,
        offset: Int,
        limit: Int,
        ordering: SnapshotOrdering
    ) throws -> [LocalScanMediaRecoverySnapshot] {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        var descriptor = FetchDescriptor<LocalScanRecord>(
            sortBy: ordering.sortDescriptors
        )
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = offset
        return try context.fetch(descriptor).map(
            LocalScanMediaRecoverySnapshot.init(record:)
        )
    }

    private enum SnapshotOrdering {
        case scanID
        case timestampThenScanID

        var sortDescriptors: [SortDescriptor<LocalScanRecord>] {
            switch self {
            case .scanID:
                [SortDescriptor(\.id)]
            case .timestampThenScanID:
                [SortDescriptor(\.timestamp), SortDescriptor(\.id)]
            }
        }
    }
}
