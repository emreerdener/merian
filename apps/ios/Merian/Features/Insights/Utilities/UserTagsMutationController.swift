import SwiftData

enum UserTagsMutationController {
    @MainActor
    static func addTag(
        _ tag: String,
        to record: LocalScanRecord,
        modelContext: ModelContext
    ) -> Bool {
        let trimmed = tag.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !record.customTags.contains(trimmed) else { return true }

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

        Task(priority: .background) {
            do {
                try await SupabaseManager.shared.client
                    .from("scans")
                    .update(["custom_tags": tags])
                    .eq("id", value: scanId)
                    .execute()
            } catch {
                MerianLog.data.error("UserTagsMutationController: failed to sync tags to cloud: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
