import Foundation
import SwiftData

@MainActor
enum FieldNotesRepository {
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
        modelContext: ModelContext
    ) -> String? {
        do {
            if let notes = nonEmptyText(
                try localRecord(for: scanId, modelContext: modelContext)?
                    .fieldNotes
            ) {
                FieldNotesStore.setFieldNotes(notes, for: scanId)
                return notes
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
                modelContext: modelContext
            )
            return legacyNotes
        }

        return nil
    }

    @discardableResult
    static func setFieldNotes(
        _ fieldNotes: String?,
        for scanId: String,
        modelContext: ModelContext
    ) -> Bool {
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
                return commitFieldNotesChange(
                    scanId: scanId,
                    persistedText: persistedText,
                    modelContext: modelContext
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
                    modelContext: modelContext
                )
            }
        } catch {
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
        modelContext: ModelContext
    ) -> String? {
        if let existingNotes = self.fieldNotes(
            for: scanId,
            modelContext: modelContext
        ) {
            return existingNotes
        }

        guard let trimmedNotes = trimmedNonEmptyText(fieldNotes) else {
            return nil
        }
        guard setFieldNotes(
            trimmedNotes,
            for: scanId,
            modelContext: modelContext
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
        modelContext: ModelContext
    ) -> Bool {
        do {
            try modelContext.save()
            FieldNotesStore.setFieldNotes(persistedText, for: scanId)
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
