import SwiftUI

struct FieldNotesVisibilityConfiguration {
    let initialIsPublic: Bool
    let onSave: (String, Bool) async -> FieldNotesVisibilityUpdateFeedback
}

/// Editable field-notes sheet presented from the insight flow.
struct FieldNotesSheet: View {
    @Binding var text: String
    let promptContext: FieldNotesPromptContext
    let visibilityConfiguration: FieldNotesVisibilityConfiguration?

    @Environment(SpeechManager.self) private var speechManager
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool
    @State private var initialText: String
    @State private var initialIsPublic: Bool
    @State private var draftText: String
    @State private var draftIsPublic: Bool
    @State private var isSaving = false
    @State private var showDeleteConfirmation = false
    @State private var dictationTask: Task<Void, Never>?
    @State private var dictationErrorMessage: String?
    @State private var saveErrorMessage: String?
    @State private var didFinalizeBeforeDismiss = false

    init(
        text: Binding<String>,
        promptContext: FieldNotesPromptContext,
        visibilityConfiguration: FieldNotesVisibilityConfiguration? = nil
    ) {
        self._text = text
        self.promptContext = promptContext
        self.visibilityConfiguration = visibilityConfiguration
        self._initialText = State(initialValue: text.wrappedValue)
        self._initialIsPublic = State(initialValue: visibilityConfiguration?.initialIsPublic ?? false)
        self._draftText = State(initialValue: text.wrappedValue)
        self._draftIsPublic = State(initialValue: visibilityConfiguration?.initialIsPublic ?? false)
    }

    private var isDictating: Bool {
        dictationTask != nil && speechManager.isRecording
    }

    private var hasNotes: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var draftChanges: FieldNotesEditChanges {
        FieldNotesEditPolicy.changes(
            initialText: initialText,
            initialIsPublic: initialIsPublic,
            draftText: draftText,
            draftIsPublic: draftIsPublic
        )
    }

    var body: some View {
        ZStack {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    // MARK: - Text Field
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(uiColor: .systemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )

                        TextEditor(text: $draftText)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .focused($isTextFieldFocused)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .topLeading)

                        if draftText.isEmpty {
                            Text("Write down what you noticed...")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.top, 18)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 320, alignment: .topLeading)
                    .layoutPriority(1)
                    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .onTapGesture {
                        isTextFieldFocused = true
                    }

                    visibilityToggle

                    dictationButton

                    if let dictationErrorMessage {
                        Text(dictationErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let saveErrorMessage {
                        Text(saveErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                .navigationTitle("Field notes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(role: .destructive, action: {
                            guard hasNotes, !isSaving else { return }
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                showDeleteConfirmation = true
                            }
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.circle)
                        .tint(.red)
                        .disabled(!hasNotes || isSaving)
                        .opacity(hasNotes ? 1 : 0.35)
                        .accessibilityLabel("Clear field notes")
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: {
                            Task { await saveDraftAndClose() }
                        }) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.circle)
                        .tint(.accentColor)
                        .disabled(isSaving)
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
            }
            .onChange(of: speechManager.isRecording) { _, isRecording in
                if !isRecording {
                    dictationTask?.cancel()
                    dictationTask = nil
                }
            }
            .onChange(of: draftText) { _, newValue in
                if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    draftIsPublic = false
                }
            }
            .onDisappear {
                saveDraftOnDisappearIfNeeded()
            }

            if showDeleteConfirmation {
                clearNotesConfirmationOverlay
            }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
        .presentationContentInteraction(.resizes)
        .interactiveDismissDisabled(isSaving)
    }

    @ViewBuilder
    private var visibilityToggle: some View {
        if visibilityConfiguration != nil {
            Toggle(
                isOn: Binding(
                    get: { hasNotes && draftIsPublic },
                    set: { draftIsPublic = $0 && hasNotes }
                )
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show on Explore")
                        .font(.subheadline.weight(.semibold))

                    Text(visibilityDetailText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .disabled(!hasNotes || isSaving)
            .padding(12)
            .background(
                Color.primary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private var visibilityDetailText: String {
        if !hasNotes {
            return "Add field notes before showing them on Explore."
        }

        return draftIsPublic
            ? "Field notes appear on this post."
            : "Keep these field notes off this post."
    }

    private var dictationButton: some View {
        Button {
            HapticManager.shared.triggerMediumPulse()
            if isDictating {
                stopDictation()
            } else {
                startDictation()
            }
        } label: {
            ZStack {
                HStack(spacing: 10) {
                    Image(systemName: isDictating ? "stop.fill" : "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 18)

                    Text(isDictating ? "Stop dictation" : "Dictate field notes")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)

                HStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(isDictating ? .white : .primary)
                        .opacity(speechManager.isStarting ? 1 : 0)
                        .accessibilityHidden(!speechManager.isStarting)
                }
                .padding(.trailing, 18)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(isDictating ? .white : .primary)
            .background(
                Capsule(style: .continuous)
                    .fill(isDictating ? Color.red : Color.primary.opacity(0.08))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.primary.opacity(isDictating ? 0 : 0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(speechManager.isStarting || isSaving)
        .animation(.easeInOut(duration: 0.2), value: isDictating)
    }

    private var clearNotesConfirmationOverlay: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDeleteConfirmation = false
                    }
                }

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Clear field notes?")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("This removes the notes from this scan.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showDeleteConfirmation = false
                        }
                    } label: {
                        Text("Cancel")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )

                    Button(role: .destructive) {
                        Task { await clearFieldNotes() }
                    } label: {
                        Text("Clear")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.red)
                    )
                }
            }
            .padding(20)
            .frame(maxWidth: 340)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 24)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .zIndex(10)
    }

    private func clearFieldNotes() async {
        stopDictation()
        isTextFieldFocused = false
        draftText = ""
        draftIsPublic = false
        showDeleteConfirmation = false
        await saveDraftAndClose()
    }

    private func saveDraftAndClose() async {
        guard !isSaving else { return }

        stopDictation()
        isTextFieldFocused = false
        saveErrorMessage = nil

        let shouldPublish = hasNotes && draftIsPublic
        guard !draftChanges.isEmpty else {
            didFinalizeBeforeDismiss = true
            dismiss()
            return
        }

        commitDraft()

        guard let visibilityConfiguration else {
            didFinalizeBeforeDismiss = true
            dismiss()
            return
        }

        isSaving = true
        let feedback = await visibilityConfiguration.onSave(draftText, shouldPublish)
        isSaving = false

        switch feedback {
        case .success(let isPublic):
            draftIsPublic = isPublic
            didFinalizeBeforeDismiss = true
            dismiss()
        case .failure(let message):
            saveErrorMessage = message
        }
    }

    private func saveDraftOnDisappearIfNeeded() {
        stopDictation()

        guard !didFinalizeBeforeDismiss, !draftChanges.isEmpty else { return }

        let textToSave = draftText
        let shouldPublish = hasNotes && draftIsPublic
        commitDraft()

        guard let visibilityConfiguration else { return }

        Task {
            _ = await visibilityConfiguration.onSave(textToSave, shouldPublish)
        }
    }

    private func startDictation() {
        dictationErrorMessage = nil
        isTextFieldFocused = false
        let base = draftText.trimmingCharacters(in: .whitespacesAndNewlines)

        dictationTask = Task {
            do {
                try await speechManager.startDictation { transcribed in
                    let trimmedTranscription = transcribed.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedTranscription.isEmpty else { return }
                    draftText = base.isEmpty ? trimmedTranscription : base + " " + trimmedTranscription
                }
            } catch {
                dictationErrorMessage = error.localizedDescription
                dictationTask = nil
            }
        }
    }

    private func stopDictation() {
        speechManager.stopDictation()
        dictationTask?.cancel()
        dictationTask = nil
    }

    private func commitDraft() {
        guard text != draftText else { return }
        text = draftText
    }
}
