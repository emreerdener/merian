import SwiftUI

/// Editable field-notes sheet presented from the insight flow.
struct FieldNotesSheet: View {
    @Binding var text: String
    let promptContext: FieldNotesPromptContext

    @Environment(SpeechManager.self) private var speechManager
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool
    @State private var draftText: String
    @State private var showDeleteConfirmation = false
    @State private var dictationTask: Task<Void, Never>?
    @State private var dictationErrorMessage: String?

    init(text: Binding<String>, promptContext: FieldNotesPromptContext) {
        self._text = text
        self.promptContext = promptContext
        self._draftText = State(initialValue: text.wrappedValue)
    }

    private var isDictating: Bool {
        dictationTask != nil && speechManager.isRecording
    }

    private var hasNotes: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                        if draftText.isEmpty {
                            Text("Write down what you noticed...")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.top, 18)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .onTapGesture {
                        isTextFieldFocused = true
                    }

                    dictationButton

                    if let dictationErrorMessage {
                        Text(dictationErrorMessage)
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
                            guard hasNotes else { return }
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
                        .disabled(!hasNotes)
                        .opacity(hasNotes ? 1 : 0.35)
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: {
                            commitDraft()
                            dismiss()
                        }) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.circle)
                        .tint(.blue)
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
            .onDisappear {
                stopDictation()
                commitDraft()
            }

            if showDeleteConfirmation {
                clearNotesConfirmationOverlay
            }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
        .presentationContentInteraction(.resizes)
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
        .disabled(speechManager.isStarting)
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
                        clearFieldNotes()
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

    private func clearFieldNotes() {
        stopDictation()
        isTextFieldFocused = false
        draftText = ""
        commitDraft()
        showDeleteConfirmation = false
        dismiss()
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
