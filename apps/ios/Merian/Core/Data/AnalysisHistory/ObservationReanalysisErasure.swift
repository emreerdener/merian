import Foundation
import SwiftData

/// Caller owns the parent transaction and save. Never performs I/O before commit.
enum ObservationReanalysisErasure {
    struct Cleanup: Sendable, Equatable {
        var childIDs: [String] = []
        var mediaPaths: [String] = []
    }

    static func removeChildren(of observationID: String, context: ModelContext) throws -> Cleanup {
        guard let parentID = UUID(uuidString: observationID) else { return Cleanup() }
        let parent = parentID.uuidString.lowercased()
        let query = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.parentObservationID == parent })
        var cleanup = Cleanup()
        // Parent linkage is the independent erasure index. Damaged kind, source,
        // owner or job metadata cannot strand children or authorize remote work.
        for child in try context.fetch(query) {
            if let childID = UUID(uuidString: child.id), childID.uuidString.lowercased() == child.id, child.id != parent {
                try ObservationReanalysisErasureReceipt(parentID: parentID, childID: childID).recordParentErasure(in: context)
            }
            cleanup.childIDs.append(child.id)
            let media = child.capturedMediaSnapshot
            let paths = media.thumbnailImagePaths + media.audioPaths + media.videoPaths
                + (child.inferenceImagePaths ?? []) + [child.coverImagePath].compactMap { $0 }
            cleanup.mediaPaths += paths.compactMap { ownedFile($0, childID: child.id) }
            if let job = try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: child.id)) {
                context.delete(job)
            }
            try context.deletePreferredGoalHint(scanId: child.id)
            context.delete(child)
        }
        cleanup.mediaPaths = Array(Set(cleanup.mediaPaths)).sorted()
        return cleanup
    }

    /// Future producers must copy private inputs into this child-owned namespace.
    /// References to parent/library files never confer deletion authority.
    static func ownedFile(_ path: String, childID: String) -> String? {
        guard let child = UUID(uuidString: childID), child.uuidString.lowercased() == childID else { return nil }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "ReanalysisQueue", parts[1] == childID,
              !parts[2].isEmpty, parts[2] != ".", parts[2] != "..",
              !parts[2].contains("\\"), !parts[2].contains(":") else { return nil }
        return URL.documentsDirectory.appendingPathComponent(path).path
    }
}
