struct FieldNotesVisibilityConfiguration {
    let initialIsPublic: Bool
    let onSave: (String, Bool) async -> FieldNotesVisibilityUpdateFeedback
}
