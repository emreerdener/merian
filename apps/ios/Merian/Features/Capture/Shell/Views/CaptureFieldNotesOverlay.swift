import SwiftUI

/// One outer presentation owns the editor, nested prompts, and dismissal barrier.
/// The same observation toolbar stays above the keyboard while editing.
struct CaptureFieldNotesOverlay<Toolbar: View>: View {
    let workspace: CaptureWorkspaceViewModel
    let session: CaptureFieldNotesSession
    let speechManager: SpeechManager
    @ViewBuilder let toolbar: () -> Toolbar

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isTextFocused: Bool
    @State private var isVisible = false
    @State private var isExpanded = false
    @State private var showsPrompts = false
    private let presentation = DescribePresentationDependencies.live

    private var context: Binding<ObservationContext> {
        Binding(get: { workspace.descriptionDraft }, set: {
            _ = workspace.autosaveFieldNotes($0, session: session)
        })
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Color.black.opacity(isVisible ? 0.2 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: close)
                    .accessibilityHidden(true)
                if isVisible {
                    VStack(spacing: 12) {
                        Spacer(minLength: 0)
                        editor
                            .frame(maxHeight: isExpanded ? .infinity : geometry.size.height * 0.6)
                            .modifier(CaptureTrayGlass(isExpanded: true))
                            .clipShape(RoundedRectangle(cornerRadius: 28))
                        toolbar()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onAppear {
            guard session.isPresented else { dismissPresentation(); return }
            withAnimation(animation) { isVisible = true }
        }
        .onChange(of: session.isPresented) { _, presented in
            if !presented { dismissPresentation() }
        }
        .onChange(of: isTextFocused) { _, focused in
            if focused { withAnimation(animation) { isExpanded = true } }
        }
        .onChange(of: session.prompts.progress) { _, _ in
            workspace.saveFieldNotesProgress(session: session)
        }
        .onChange(of: speechManager.isRecording) { _, recording in
            guard !session.isSubmitting else { return }
            session.input.speechRecordingDidChange(
                isRecording: recording, isRequested: session.isDictationRequested,
                onRequestEnded: { session.isDictationRequested = false }
            )
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { session.stopInput() }
        }
        .task(id: workspace.descriptionDraft.freeText) {
            guard workspace.acceptsFieldNotesWrite(session) else { return }
            session.input.descriptionDidChange(
                text: workspace.descriptionDraft.freeText,
                isReanalysis: workspace.describePromptFlow.isReanalysis,
                isFunnelActive: session.prompts.isFunnelActive,
                shouldApplySubject: {
                    workspace.acceptsFieldNotesWrite(session) && !session.prompts.isFunnelActive
                },
                onDescriptionEmptied: { session.prompts.resetFunnel() },
                onSubjectInferred: { session.prompts.activateFunnel(for: $0) }
            )
        }
        .onDisappear { session.stopInput() }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            Button(action: close) {
                Capsule().fill(.secondary).frame(width: 36, height: 5)
                    .frame(width: 80, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Field notes")
            .accessibilityIdentifier("FieldNotesClose")
            .gesture(DragGesture(minimumDistance: 20).onEnded { value in
                if value.translation.height > 30 { close() }
            })

            NavigationStack {
                VStack(spacing: 0) {
                    notesHeader
                    notesContent
                }
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(isPresented: $showsPrompts) {
                    List {
                        ForEach(session.prompts.activeQuestions.indices, id: \.self) { index in
                            Button(session.prompts.displayPrompt(at: index)) {
                                guard workspace.acceptsFieldNotesWrite(session) else { return }
                                session.prompts.activeQuestionIndex = index
                                showsPrompts = false
                            }
                        }
                    }
                    .navigationTitle("Prompts")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar(.visible, for: .navigationBar)
                }
            }
            .disabled(session.isSubmitting || !session.isPresented)
        }
    }

    private var notesContent: some View {
        GeometryReader { viewport in
            ScrollViewReader { reader in
                ScrollView {
                    VStack(spacing: 8) {
                        if workspace.describePromptFlow.isReanalysis {
                            DescribeReanalysisHeaderView()
                        } else {
                            DescribeQuestionNavigationView(
                                questionCount: session.prompts.activeQuestions.count,
                                activeQuestionIndex: session.prompts.activeQuestionIndex,
                                selectionFeedback: presentation.selectionFeedback,
                                onPrevious: session.prompts.moveToPreviousQuestion,
                                onNext: session.prompts.advanceQuestion
                            )
                            DescribePromptTagsView(
                                promptViewModel: session.prompts,
                                tagFrequency: presentation.tagFrequency,
                                selectionFeedback: presentation.selectionFeedback,
                                onSelectTag: selectTag,
                                onAdvanceQuestion: session.prompts.advanceQuestion,
                                promptOverride: session.prompts.activeQuestionIndex == 0
                                    && !session.prompts.isFunnelActive ? "What did you notice?" : nil
                            )
                        }
                        CaptureFieldNotesTextEditor(text: context.freeText, focus: $isTextFocused)
                            .frame(height: min(220, max(44, viewport.size.height - 8)))
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                            .id("FieldNotesEditorViewport")
                        if let error = session.errorMessage {
                            Text(error).font(.callout).foregroundStyle(.red).padding(.horizontal)
                        }
                    }
                }
                .accessibilityIdentifier("FieldNotesContent")
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: isTextFocused) { _, focused in
                    if focused { reader.scrollTo("FieldNotesEditorViewport", anchor: .bottom) }
                }
                .onChange(of: viewport.size.height) { _, _ in
                    if isTextFocused { reader.scrollTo("FieldNotesEditorViewport", anchor: .bottom) }
                }
            }
        }
    }

    /// Explicit controls avoid the native compact navigation-bar button shrinking
    /// the Field notes targets below the design's 44-point touch regions.
    private var notesHeader: some View {
        HStack {
            if !workspace.describePromptFlow.isReanalysis {
                Button {
                    isTextFocused = false
                    isExpanded = true
                    showsPrompts = true
                } label: {
                    notesHeaderIcon("list.bullet")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Prompts")
                .accessibilityIdentifier("FieldNotesPrompts")
            } else {
                Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
            }
            Spacer()
            Text("Field notes")
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("FieldNotesTitle")
            Spacer()
            Button(action: toggleDictation) {
                notesHeaderIcon("microphone.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(session.isDictationRequested ? "Stop dictation" : "Dictate notes")
            .disabled(session.isSubmitting)
            .accessibilityIdentifier("FieldNotesDictation")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func notesHeaderIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 20))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .background(.primary.opacity(0.1), in: Circle())
            .contentShape(Circle())
    }

    private var animation: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.25) }

    private func close() { workspace.closeFieldNotes(sessionID: session.id) }

    private func dismissPresentation() {
        isTextFocused = false
        withAnimation(animation, completionCriteria: .removed) {
            isVisible = false
        } completion: {
            workspace.finishFieldNotesDismissal(sessionID: session.id)
        }
    }

    private func toggleDictation() {
        guard workspace.acceptsFieldNotesWrite(session), !session.isSubmitting else { return }
        session.isDictationRequested.toggle()
        session.input.dictationRequestDidChange(
            isRequested: session.isDictationRequested,
            baseText: workspace.descriptionDraft.freeText,
            onTranscript: { text in
                guard session.isDictationRequested else { return }
                var value = workspace.descriptionDraft
                value.freeText = text
                _ = workspace.autosaveFieldNotes(value, session: session)
            },
            onRequestEnded: { session.isDictationRequested = false }
        )
    }

    private func selectTag(_ tag: GuidedQuestion.Tag) {
        guard workspace.acceptsFieldNotesWrite(session), !session.isSubmitting else { return }
        presentation.recordTagUsage(tag.tagId)
        isTextFocused = false
        let removing = session.prompts.activeQuestionIndex == 0 && session.prompts.activeSubjectId == tag.tagId
        var value = workspace.descriptionDraft
        value.freeText = DescribeTextComposer.applying(tag, to: value.freeText, isRemoving: removing)
        guard workspace.autosaveFieldNotes(value, session: session) else { return }
        if removing {
            session.prompts.clearSubjectSelection()
        } else {
            session.prompts.applySubjectSelection(for: tag)
        }
    }
}

/// The finite input viewport owns caret scrolling; the surrounding prompt list
/// must not clip a growing multiline field at accessibility text sizes.
private struct CaptureFieldNotesTextEditor: View {
    @Binding var text: String
    let focus: FocusState<Bool>.Binding

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(focus.wrappedValue ? 0.3 : 0.12), lineWidth: 0.5)
                }
            TextEditor(text: $text)
                .font(.body)
                .foregroundStyle(.primary)
                .scrollContentBackground(.hidden)
                .focused(focus)
                .padding(.horizontal, 12)
                .accessibilityLabel("Add notes…")
                .accessibilityIdentifier("DescribeTextInput")
            if text.isEmpty {
                Text("Add notes…")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 17)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { focus.wrappedValue = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("DescribeTextArea")
    }
}
