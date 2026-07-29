import SwiftData
import SwiftUI

extension InsightSheetViewModel {
    func presentFieldNotes(
        expectedScanId: String? = nil,
        expectedGeneration: UInt64? = nil
    ) {
        guard let scanId = currentFieldNotesScanId,
              expectedGeneration == nil ||
                expectedGeneration == scanBoundActionGeneration,
              expectedScanId == nil ||
                expectedScanId?.caseInsensitiveCompare(scanId) == .orderedSame else {
            return
        }
        state.fieldNotesPresentationScanId = scanId
        state.fieldNotesPresentationGeneration = scanBoundActionGeneration
        state.isFieldNotesSheetPresented = true
    }

    func updateFieldNotes(
        _ text: String,
        expectedScanId: String? = nil,
        expectedGeneration: UInt64? = nil,
        modelContext: ModelContext
    ) {
        guard let scanId = currentFieldNotesScanId,
              expectedGeneration == nil ||
                expectedGeneration == scanBoundActionGeneration,
              expectedScanId == nil ||
                expectedScanId?.caseInsensitiveCompare(scanId) == .orderedSame else {
            return
        }
        state.fieldNotesText = text
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state.dismissedFieldNotesCardScanId = nil
        }
        persistFieldNotes(text, modelContext: modelContext)
    }

    func dismissFieldNotesCard(
        expectedScanId: String? = nil,
        expectedGeneration: UInt64? = nil
    ) {
        guard let currentFieldNotesScanId,
              expectedGeneration == nil ||
                expectedGeneration == scanBoundActionGeneration,
              expectedScanId == nil ||
                expectedScanId?.caseInsensitiveCompare(currentFieldNotesScanId) == .orderedSame else {
            return
        }
        HapticManager.shared.triggerLightImpact()
        state.dismissedFieldNotesCardScanId = currentFieldNotesScanId
    }

    func syncFieldNotesFromCurrentScan(modelContext: ModelContext) {
        let currentScanId = currentFieldNotesScanId
        let existingDraft = state.fieldNotesText

        guard currentScanId != boundFieldNotesScanId else {
            guard let currentScanId else { return }

            let persistedFieldNotes = persistedFieldNotes(for: currentScanId, modelContext: modelContext) ?? ""
            if let currentRecord = fetchLocalRecord(scanId: currentScanId, modelContext: modelContext),
               currentRecord.fieldNotes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                let promotableFieldNotes = existingDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? persistedFieldNotes
                    : existingDraft
                if !promotableFieldNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    state.fieldNotesText = promotableFieldNotes
                    persistFieldNotes(promotableFieldNotes, modelContext: modelContext)
                    return
                }
            }

            if persistedFieldNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !existingDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                persistFieldNotes(existingDraft, modelContext: modelContext)
            } else if existingDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !persistedFieldNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state.fieldNotesText = persistedFieldNotes
            }
            return
        }

        let previousScanId = boundFieldNotesScanId
        boundFieldNotesScanId = currentScanId

        guard let currentScanId else {
            if previousScanId != nil {
                state.fieldNotesText = ""
            }
            return
        }

        let storedFieldNotes = persistedFieldNotes(for: currentScanId, modelContext: modelContext) ?? ""
        let hasExistingDraft = !existingDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasStoredFieldNotes = !storedFieldNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if previousScanId == nil, hasExistingDraft, !hasStoredFieldNotes {
            persistFieldNotes(existingDraft, modelContext: modelContext)
        } else {
            state.fieldNotesText = storedFieldNotes
        }
    }
    @discardableResult
    private func persistFieldNotes(_ text: String, modelContext: ModelContext) -> Bool {
        guard let scanId = currentFieldNotesScanId else { return false }
        boundFieldNotesScanId = scanId

        return FieldNotesRepository.setFieldNotes(
            text,
            for: scanId,
            modelContext: modelContext
        )
    }

    func syncComposerFieldNotes(_ notes: String?, modelContext: ModelContext) {
        let draftNotes = notes ?? ""
        state.fieldNotesText = draftNotes
        if !draftNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state.dismissedFieldNotesCardScanId = nil
        }
        _ = persistFieldNotes(draftNotes, modelContext: modelContext)
    }

    private func persistedFieldNotes(for scanId: String, modelContext: ModelContext) -> String? {
        FieldNotesRepository.fieldNotes(
            for: scanId,
            modelContext: modelContext
        )
    }

    func promotePublishedExploreFieldNotesIfLocalMissing(_ notes: String, modelContext: ModelContext) {
        guard let scanId = currentFieldNotesScanId,
              state.fieldNotesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        if let resolvedNotes = FieldNotesRepository.promoteExternalFieldNotesIfLocalMissing(
            notes,
            for: scanId,
            modelContext: modelContext
        ) {
            state.fieldNotesText = resolvedNotes
        }
    }

    func preserveLocalFieldNotesIfNeeded(_ notes: String, modelContext: ModelContext) {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if state.fieldNotesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state.fieldNotesText = notes
        }

        guard let scanId = currentFieldNotesScanId else { return }
        boundFieldNotesScanId = scanId

        _ = FieldNotesRepository.promoteExternalFieldNotesIfLocalMissing(
            notes,
            for: scanId,
            modelContext: modelContext
        )
    }
}
