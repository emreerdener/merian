import SwiftUI

/// Editable field-notes sheet presented from the Insight and Explore flows.
struct FieldNotesSheet: View {
    @Binding var text: String
    let promptContext: FieldNotesPromptContext
    let visibilityConfiguration: FieldNotesVisibilityConfiguration?

    @Environment(SpeechManager.self) private var speechManager
    private let dependencies: FieldNotesEditorDependencies?

    init(
        text: Binding<String>,
        promptContext: FieldNotesPromptContext,
        visibilityConfiguration: FieldNotesVisibilityConfiguration? = nil,
        dependencies: FieldNotesEditorDependencies? = nil
    ) {
        self._text = text
        self.promptContext = promptContext
        self.visibilityConfiguration = visibilityConfiguration
        self.dependencies = dependencies
    }

    var body: some View {
        FieldNotesEditorView(
            text: $text,
            visibilityConfiguration: visibilityConfiguration,
            speechManager: speechManager,
            dependencies: dependencies ?? .live(speechManager: speechManager)
        )
    }
}
