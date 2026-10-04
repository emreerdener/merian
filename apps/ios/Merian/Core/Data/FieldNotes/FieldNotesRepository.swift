import Foundation
import SwiftData

@MainActor
enum FieldNotesRepository {
    struct Dependencies {
        var allowsMutation: @MainActor () -> Bool = { SupabaseManager.shared.allowsLocalLibraryMutation }
        var ownerID: @MainActor () -> UUID? = { SupabaseManager.shared.currentUser?.id }
        var didCommit: @MainActor (ModelContext) -> Void = { context in
            Task { await LibraryDetailsSyncService.drain(context: context, manager: .shared) }
        }
    }
    static func nonEmptyText(_ fieldNotes: String?) -> String? {
        guard let fieldNotes else { return nil }
        let trimmed = fieldNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : fieldNotes
    }

    static func trimmedNonEmptyText(_ fieldNotes: String?) -> String? {
        nonEmptyText(fieldNotes)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func fieldNotes(
        for scanId: String,
        modelContext: ModelContext,
        dependencies: Dependencies = Dependencies()
    ) -> String? {
        do {
            if let notes = nonEmptyText(
                try localRecord(for: scanId, modelContext: modelContext)?
                    .fieldNotes
            ) {
                FieldNotesStore.setFieldNotes(notes, for: scanId)
                return notes
            }

            // A completed restored snapshot proves a remote clear. A tag-only
            // client operation cannot prove an old bridge note was migrated.
            if try localRecord(for: scanId, modelContext: modelContext) != nil {
                let jobs = try modelContext.fetch(FetchDescriptor<OfflineJobRecord>(
                    predicate: #Predicate { $0.subjectId == scanId }
                ))
                if jobs.contains(where: { job in
                    guard job.id.hasPrefix("library-details:baseline:"), job.status == .complete,
                          let json = job.metadataJSON,
                          let mutation = try? JSONDecoder().decode(LibraryDetailsSyncService.Mutation.self, from: Data(json.utf8)) else { return false }
                    return mutation.scanID == scanId && mutation.ownerID == dependencies.ownerID() && mutation.fieldNotes == nil
                }) {
                    FieldNotesStore.setFieldNotes(nil, for: scanId)
                    return nil
                }
            }

            if let notes = nonEmptyText(
                try queuedScan(for: scanId, modelContext: modelContext)?
                    .fieldNotes
            ) {
                FieldNotesStore.setFieldNotes(notes, for: scanId)
                return notes
            }
        } catch {
            logReadFailure(error, scanId: scanId)
            return nil
        }

        if let legacyNotes = FieldNotesStore.fieldNotes(for: scanId) {
            _ = setFieldNotes(
                legacyNotes,
                for: scanId,
                modelContext: modelContext,
                dependencies: dependencies
            )
            return legacyNotes
        }

        return nil
    }

    @discardableResult
    static func setFieldNotes(
        _ fieldNotes: String?,
        for scanId: String,
        modelContext: ModelContext,
        dependencies: Dependencies = Dependencies()
    ) -> Bool {
        guard dependencies.allowsMutation() else { return false }
        let persistedText = nonEmptyText(fieldNotes)

        do {
            if let record = try localRecord(
                for: scanId,
                modelContext: modelContext
            ) {
                guard !sameStoredValue(record.fieldNotes, persistedText) else {
                    FieldNotesStore.setFieldNotes(persistedText, for: scanId)
                    return false
                }

                record.fieldNotes = persistedText
                guard let owner = dependencies.ownerID() else {
                    modelContext.rollback()
                    return false
                }
                try LibraryDetailsSyncService.stage(record, ownerID: owner, context: modelContext)
                return commitFieldNotesChange(
                    scanId: scanId,
                    persistedText: persistedText,
                    modelContext: modelContext,
                    dependencies: dependencies
                )
            }

            if let queuedScan = try queuedScan(
                for: scanId,
                modelContext: modelContext
            ) {
                guard !sameStoredValue(queuedScan.fieldNotes, persistedText) else {
                    FieldNotesStore.setFieldNotes(persistedText, for: scanId)
                    return false
                }

                queuedScan.fieldNotes = persistedText
                return commitFieldNotesChange(
                    scanId: scanId,
                    persistedText: persistedText,
                    modelContext: modelContext,
                    dependencies: dependencies
                )
            }
        } catch {
            modelContext.rollback()
            logReadFailure(error, scanId: scanId)
            return false
        }

        let previousBridgeText = FieldNotesStore.fieldNotes(for: scanId)
        FieldNotesStore.setFieldNotes(persistedText, for: scanId)
        return !sameStoredValue(previousBridgeText, persistedText)
    }

    @discardableResult
    static func promoteExternalFieldNotesIfLocalMissing(
        _ fieldNotes: String,
        for scanId: String,
        modelContext: ModelContext,
        dependencies: Dependencies = Dependencies()
    ) -> String? {
        if let existingNotes = self.fieldNotes(
            for: scanId,
            modelContext: modelContext,
            dependencies: dependencies
        ) {
            return existingNotes
        }

        guard let trimmedNotes = trimmedNonEmptyText(fieldNotes) else {
            return nil
        }
        guard setFieldNotes(
            trimmedNotes,
            for: scanId,
            modelContext: modelContext,
            dependencies: dependencies
        ) else {
            return nil
        }
        return trimmedNotes
    }

    private static func localRecord(
        for scanId: String,
        modelContext: ModelContext
    ) throws -> LocalScanRecord? {
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private static func queuedScan(
        for scanId: String,
        modelContext: ModelContext
    ) throws -> OfflineQueuedScan? {
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private static func sameStoredValue(_ lhs: String?, _ rhs: String?) -> Bool {
        trimmedNonEmptyText(lhs) == trimmedNonEmptyText(rhs) && lhs == rhs
    }

    private static func commitFieldNotesChange(
        scanId: String,
        persistedText: String?,
        modelContext: ModelContext,
        dependencies: Dependencies = Dependencies()
    ) -> Bool {
        do {
            try modelContext.save()
            FieldNotesStore.setFieldNotes(persistedText, for: scanId)
            dependencies.didCommit(modelContext)
            return true
        } catch {
            modelContext.rollback()
            MerianLog.data.error(
                "FieldNotesRepository: failed to save field notes for scan \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return false
        }
    }

    private static func logReadFailure(_ error: Error, scanId: String) {
        MerianLog.data.error(
            "FieldNotesRepository: failed to read field notes for scan \(scanId, privacy: .private): \(error, privacy: .private)"
        )
    }
}
