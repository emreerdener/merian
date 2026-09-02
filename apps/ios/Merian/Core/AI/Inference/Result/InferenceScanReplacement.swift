import Foundation
import SwiftData

/// Makes replacement metadata durable before authorizing original-scan deletion.
/// The engine immediately passes the returned record to ScanRepository for its
/// existing local-deletion/cloud-outbox transaction. Failure can leave two scans,
/// but must never leave neither a usable original nor its replacement metadata.
@MainActor
enum InferenceScanReplacement {
    static func transferMetadata(
        from originalScanId: String?,
        after outcome: InferenceLiveResultService.Outcome,
        modelContext: ModelContext?,
        saveMetadata: @MainActor (ModelContext) throws -> Void = { try $0.save() }
    ) -> LocalScanRecord? {
        guard case .persisted(let result) = outcome,
              let originalScanId,
              let replacementScanId = result.speciesData.scanId,
              !originalScanId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !replacementScanId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              originalScanId.caseInsensitiveCompare(replacementScanId) != .orderedSame,
              let context = modelContext else { return nil }

        do {
            // A pending insert in the presentation context is not durable proof.
            // Read the replacement through a fresh context before staging any
            // metadata or authorizing deletion of the original.
            let persistedContext = ModelContext(context.container)
            guard try record(id: replacementScanId, in: persistedContext) != nil,
                  let replacement = try record(id: replacementScanId, in: context),
                  let original = try record(id: originalScanId, in: context),
                  !replacement.isDeleted,
                  !original.isDeleted else { return nil }

            let previousTags = replacement.customTags
            let previousCollections = replacement.collections
            let previousNotes = replacement.fieldNotes
            replacement.customTags = original.customTags
            if let collections = original.collections, !collections.isEmpty {
                replacement.collections = collections
            }
            let replacementHasNotes = !(
                replacement.fieldNotes?
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
            )
            if let notes = original.fieldNotes?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !notes.isEmpty,
               !replacementHasNotes {
                replacement.fieldNotes = original.fieldNotes
            }
            // Identification review state belongs to the new analysis, not the
            // user's retained tags, collection memberships, or field notes.
            do {
                try saveMetadata(context)
            } catch {
                // Restore only our staged values. A context-wide rollback would
                // discard unrelated user edits in the presentation context.
                replacement.customTags = previousTags
                replacement.collections = previousCollections
                replacement.fieldNotes = previousNotes
                throw error
            }
            return original
        } catch {
            MerianLog.data.error("Reanalysis metadata could not be committed; preserving the original scan.")
            return nil
        }
    }

    private static func record(id: String, in context: ModelContext) throws -> LocalScanRecord? {
        var descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
