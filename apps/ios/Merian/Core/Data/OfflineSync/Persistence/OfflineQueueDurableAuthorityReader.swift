import Foundation
import SwiftData

/// Immutable scan/job authority projected from one fresh SwiftData context.
///
/// Retry and completed-result state is mirrored across two rows. Reading both
/// through one throwing boundary prevents a storage failure from being treated
/// as an absent marker or a zero retry count.
struct OfflineQueueDurableAuthority: Sendable, Equatable {
    let scanErrorCode: String?
    let jobErrorCode: String?
    let scanAttemptCount: Int
    let jobAttemptCount: Int
    let requiredVideoCount: Int

    var maximumAttemptCount: Int {
        max(0, max(scanAttemptCount, jobAttemptCount))
    }

    func containsErrorCode(
        matching predicate: (String?) -> Bool
    ) -> Bool {
        predicate(scanErrorCode) || predicate(jobErrorCode)
    }
}

enum OfflineQueueDurableAuthorityReadError: Error {
    case missingModelContainer
}

@MainActor
enum OfflineQueueDurableAuthorityReader {
    static func read(
        scanId: String,
        from container: ModelContainer
    ) throws -> OfflineQueueDurableAuthority {
        let context = ModelContext(container)
        var scanDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        scanDescriptor.fetchLimit = 1
        let scan = try context.fetch(scanDescriptor).first
        let job = try context.fetchOfflineJob(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        )

        return OfflineQueueDurableAuthority(
            scanErrorCode: scan?.queueLastErrorCode,
            jobErrorCode: job?.lastErrorCode,
            scanAttemptCount: scan?.queueAttemptCount ?? 0,
            jobAttemptCount: job?.attemptCount ?? 0,
            requiredVideoCount:
                scan?.capturedMediaSnapshot.videoPaths.count ?? 0
        )
    }
}

@MainActor
extension OfflineQueueManager {
    func durableQueueAuthority(
        scanId: String
    ) throws -> OfflineQueueDurableAuthority {
        guard let container = modelContext?.container else {
            throw OfflineQueueDurableAuthorityReadError.missingModelContainer
        }
        return try OfflineQueueDurableAuthorityReader.read(
            scanId: scanId,
            from: container
        )
    }

    func durableQueueAuthorityIfReadable(
        scanId: String,
        operation: String
    ) -> OfflineQueueDurableAuthority? {
        do {
            return try durableQueueAuthority(scanId: scanId)
        } catch {
            MerianLog.data.error(
                "\(operation, privacy: .public): durable authority fetch failed scanId=\(scanId, privacy: .private) error=\(error, privacy: .private)"
            )
            return nil
        }
    }
}
