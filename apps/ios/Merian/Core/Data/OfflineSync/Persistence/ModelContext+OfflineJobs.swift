import Foundation
import SwiftData

extension ModelContext {
    func fetchOfflineJob(id: String) throws -> OfflineJobRecord? {
        var descriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try fetch(descriptor).first
    }

    @discardableResult
    func ensureOfflineJobRecord(
        id: String,
        kind: OfflineJobKind,
        subjectId: String? = nil,
        priority: Int = 0,
        approximateBytes: Int64 = 0,
        requiresUnconstrainedNetwork: Bool = false,
        allowsCellular: Bool = true,
        metadataJSON: String? = nil
    ) throws -> OfflineJobRecord {
        var descriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        if let existing = try fetch(descriptor).first {
            existing.kind = kind
            existing.subjectId = subjectId
            existing.priority = priority
            existing.status = existing.status == .complete ? .pending : existing.status
            existing.updatedAt = Date()
            existing.approximateBytes = approximateBytes
            existing.requiresUnconstrainedNetwork = requiresUnconstrainedNetwork
            existing.allowsCellular = allowsCellular
            existing.metadataJSON = metadataJSON
            return existing
        }

        let record = OfflineJobRecord(
            id: id,
            kind: kind,
            subjectId: subjectId,
            priority: priority,
            requiresUnconstrainedNetwork: requiresUnconstrainedNetwork,
            allowsCellular: allowsCellular,
            approximateBytes: approximateBytes,
            metadataJSON: metadataJSON
        )
        insert(record)
        return record
    }
}
