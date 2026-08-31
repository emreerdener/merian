import SwiftData

struct InsightFieldNotesDependencies {
    let fieldNotes:
        @MainActor (
            _ scanID: String,
            _ modelContext: ModelContext
        ) -> String?
    let setFieldNotes:
        @MainActor (
            _ text: String?,
            _ scanID: String,
            _ modelContext: ModelContext
        ) -> Bool
    let promoteExternalFieldNotesIfLocalMissing:
        @MainActor (
            _ text: String,
            _ scanID: String,
            _ modelContext: ModelContext
        ) -> String?
    let cardDismissFeedback: @MainActor () -> Void

    init(
        fieldNotes:
            @escaping @MainActor (
                _ scanID: String,
                _ modelContext: ModelContext
            ) -> String? = { _, _ in nil },
        setFieldNotes:
            @escaping @MainActor (
                _ text: String?,
                _ scanID: String,
                _ modelContext: ModelContext
            ) -> Bool = { _, _, _ in false },
        promoteExternalFieldNotesIfLocalMissing:
            @escaping @MainActor (
                _ text: String,
                _ scanID: String,
                _ modelContext: ModelContext
            ) -> String? = { _, _, _ in nil },
        cardDismissFeedback: @escaping @MainActor () -> Void = {}
    ) {
        self.fieldNotes = fieldNotes
        self.setFieldNotes = setFieldNotes
        self.promoteExternalFieldNotesIfLocalMissing =
            promoteExternalFieldNotesIfLocalMissing
        self.cardDismissFeedback = cardDismissFeedback
    }

    @MainActor
    static var live: Self {
        let hapticManager = AppDIContainer.shared.hapticManager
        return Self(
            fieldNotes: { scanID, modelContext in
                FieldNotesRepository.fieldNotes(
                    for: scanID,
                    modelContext: modelContext
                )
            },
            setFieldNotes: { text, scanID, modelContext in
                FieldNotesRepository.setFieldNotes(
                    text,
                    for: scanID,
                    modelContext: modelContext
                )
            },
            promoteExternalFieldNotesIfLocalMissing: { text, scanID, modelContext in
                FieldNotesRepository.promoteExternalFieldNotesIfLocalMissing(
                    text,
                    for: scanID,
                    modelContext: modelContext
                )
            },
            cardDismissFeedback: {
                hapticManager.triggerLightImpact()
            }
        )
    }
}
