import SwiftUI

struct FieldNotesEditorView: View {
    @Binding private var text: String
    private let visibilityConfiguration: FieldNotesVisibilityConfiguration?
    private let speechManager: SpeechManager

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool
    @State private var viewModel: FieldNotesEditorViewModel
    @State private var showDeleteConfirmation = false

    init(
        text: Binding<String>,
        visibilityConfiguration: FieldNotesVisibilityConfiguration?,
        speechManager: SpeechManager,
        dependencies: FieldNotesEditorDependencies
    ) {
        self._text = text
        self.visibilityConfiguration = visibilityConfiguration
        self.speechManager = speechManager
        self._viewModel = State(
            initialValue: FieldNotesEditorViewModel(
                initialText: text.wrappedValue,
                initialIsPublic:
                    visibilityConfiguration?.initialIsPublic ?? false,
                dependencies: dependencies
            )
        )
    }

    var body: some View {
        ZStack {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    FieldNotesTextEditor(
                        text: draftTextBinding,
                        isFocused: $isTextFieldFocused
                    )

                    if visibilityConfiguration != nil {
                        FieldNotesVisibilityToggle(
                            isPublic: draftVisibilityBinding,
                            hasNotes: viewModel.hasNotes,
                            isSaving: viewModel.isSaving,
                            detailText: viewModel.visibilityDetailText
                        )
                    }

                    FieldNotesDictationButton(
                        isDictating: viewModel.isDictating(
                            isSpeechRecording: speechManager.isRecording
                        ),
                        isStarting: speechManager.isStarting,
                        isSaving: viewModel.isSaving,
                        action: toggleDictation
                    )

                    if let dictationErrorMessage =
                        viewModel.dictationErrorMessage {
                        feedbackText(dictationErrorMessage)
                    }

                    if let saveErrorMessage = viewModel.saveErrorMessage {
                        feedbackText(saveErrorMessage)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                .navigationTitle("Field notes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { editorToolbar }
            }
            .onChange(of: speechManager.isRecording) { _, isRecording in
                viewModel.speechRecordingDidChange(isRecording: isRecording)
            }
            .onDisappear(perform: saveDraftOnDisappearIfNeeded)

            if showDeleteConfirmation {
                FieldNotesClearConfirmationOverlay(
                    onCancel: hideDeleteConfirmation,
                    onClear: {
                        Task { await clearFieldNotes() }
                    }
                )
            }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
        .presentationContentInteraction(.resizes)
        .interactiveDismissDisabled(viewModel.isSaving)
    }

    private var draftTextBinding: Binding<String> {
        Binding(
            get: { viewModel.draftText },
            set: { viewModel.updateDraftText($0) }
        )
    }

    private var draftVisibilityBinding: Binding<Bool> {
        Binding(
            get: { viewModel.hasNotes && viewModel.draftIsPublic },
            set: { viewModel.updateDraftVisibility($0) }
        )
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(role: .destructive, action: showClearConfirmation) {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .bold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .tint(.red)
            .disabled(!viewModel.hasNotes || viewModel.isSaving)
            .opacity(viewModel.hasNotes ? 1 : 0.35)
            .accessibilityLabel("Clear field notes")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await saveDraftAndClose() }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .tint(.accentColor)
            .disabled(viewModel.isSaving)
            .accessibilityLabel("Done editing field notes")
        }

        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") {
                isTextFieldFocused = false
            }
            .fontWeight(.semibold)
        }
    }

    private func feedbackText(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleDictation() {
        isTextFieldFocused = false
        viewModel.toggleDictation(
            isSpeechRecording: speechManager.isRecording
        )
    }

    private func showClearConfirmation() {
        guard viewModel.hasNotes, !viewModel.isSaving else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            showDeleteConfirmation = true
        }
    }

    private func hideDeleteConfirmation() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showDeleteConfirmation = false
        }
    }

    private func clearFieldNotes() async {
        isTextFieldFocused = false
        viewModel.clearDraft()
        showDeleteConfirmation = false
        await saveDraftAndClose()
    }

    private func saveDraftAndClose() async {
        isTextFieldFocused = false
        let shouldDismiss = await viewModel.saveDraft(
            visibilityConfiguration: visibilityConfiguration,
            onCommit: commitDraft
        )
        if shouldDismiss {
            dismiss()
        }
    }

    private func saveDraftOnDisappearIfNeeded() {
        let request = viewModel.prepareForDisappear(onCommit: commitDraft)
        guard let request, let visibilityConfiguration else { return }

        Task {
            _ = await visibilityConfiguration.onSave(
                request.text,
                request.isPublic
            )
        }
    }

    private func commitDraft(_ draft: String) {
        guard text != draft else { return }
        text = draft
    }
}
