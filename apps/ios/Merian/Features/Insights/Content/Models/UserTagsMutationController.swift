import SwiftData

enum UserTagsMutationController {
    static let maximumTagCount = 50
    static let maximumTagCharacters = 64
    static let maximumTagUTF8Bytes = 256

    @MainActor
    static func addTag(
        _ tag: String,
        to record: LocalScanRecord,
        modelContext: ModelContext
    ) -> Bool {
        let trimmed = tag.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        guard !record.customTags.contains(trimmed) else { return true }
        guard
            record.customTags.count < maximumTagCount,
            trimmed.count <= maximumTagCharacters,
            trimmed.utf8.count <= maximumTagUTF8Bytes
        else {
            return false
        }

        record.customTags.append(trimmed)
        guard persistTagMutation(modelContext: modelContext, logContext: "add custom tag") else { return false }
        syncTagsToCloud(record: record)
        ScanLibraryEvents.postSearchIndexUpdate(scanId: record.id)
        return true
    }

    @MainActor
    static func removeTag(
        _ tag: String,
        from record: LocalScanRecord,
        modelContext: ModelContext
    ) -> Bool {
        guard record.customTags.contains(tag) else { return true }
        record.customTags.removeAll { $0 == tag }
        guard persistTagMutation(modelContext: modelContext, logContext: "remove custom tag") else { return false }
        syncTagsToCloud(record: record)
        ScanLibraryEvents.postSearchIndexUpdate(scanId: record.id)
        return true
    }

    @MainActor
    @discardableResult
    private static func persistTagMutation(
        modelContext: ModelContext,
        logContext: String
    ) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            MerianLog.data.error("UserTagsMutationController: failed to save \(logContext, privacy: .public): \(error, privacy: .private)")
            return false
        }
    }

    @MainActor
    private static func syncTagsToCloud(record: LocalScanRecord) {
        let tags = record.customTags
        let scanId = record.id
        guard SupabaseManager.shared.isAuthenticated else { return }

        struct TagSyncRPCParameters: Encodable, Sendable {
            let p_scan_id: String
            let p_custom_tags: [String]
        }

        Task(priority: .background) {
            do {
                try await SupabaseManager.shared.client
                    .rpc(
                        "update_owned_scan_custom_tags",
                        params: TagSyncRPCParameters(
                            p_scan_id: scanId,
                            p_custom_tags: tags
                        )
                    )
                    .execute()
            } catch {
                MerianLog.data.error("UserTagsMutationController: failed to sync tags to cloud: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
