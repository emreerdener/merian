import SwiftUI

/// One outer presentation owns the editor, nested prompts, and dismissal barrier.
/// The same observation toolbar stays above the keyboard while editing.
struct CaptureFieldNotesOverlay<Toolbar: View>: View {
    let workspace: CaptureWorkspaceViewModel
    let session: CaptureFieldNotesSession
    let speechManager: SpeechManager
    var toolbarBottomPadding: CGFloat = 0
    @ViewBuilder let toolbar: () -> Toolbar

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isTextFocused: Bool
    @State private var isVisible = false
    @State private var isExpanded = false
    @State private var showsPrompts = false
    @State private var contentHeight: CGFloat = 392
    @State private var promptHeight: CGFloat = 180
    @ScaledMetric(relativeTo: .body) private var minimumEditorHeight: CGFloat = 72
    @State private var headerHeight: CGFloat = 80
    @State private var toolbarHeight: CGFloat = 74
    @State private var dragTranslation: CGFloat = 0
    @State private var isDragging = false
    @GestureState private var isGestureActive = false
    @Environment(HardwareOrchestrator.self) private var hardware
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
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
                let availableHeight = max(0, geometry.size.height - toolbarHeight - toolbarBottomPadding - 12)
                let editorHeight = min(availableHeight, isExpanded ? availableHeight : headerHeight + contentHeight)
                let draggedHeight = max(0, min(availableHeight, editorHeight - dragTranslation))
                VStack(spacing: 0) {
                    editor
                        .frame(height: isDragging ? draggedHeight : editorHeight)
                        .frame(height: isVisible ? draggedHeight : 0, alignment: .top)
                        .clipped()
                        .opacity(isVisible ? 1 : 0)
                        .accessibilityHidden(!isVisible)
                    toolbar()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { toolbarHeight = $0 }
                }
                .background {
                    sheetBackground
                        .clipShape(RoundedRectangle(cornerRadius: isVisible ? 32 : 50, style: .continuous))
                        .padding(.horizontal, 8)
                        .opacity(isVisible ? 1 : 0)
                }
                .environment(\.colorScheme, .dark)
                .padding(.bottom, toolbarBottomPadding)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onAppear {
            guard session.isPresented else { dismissPresentation(); return }
            workspace.dependencies.feedback.sheet("capture.field-notes.open")
            withAnimation(animation) { isVisible = true }
        }
        .accessibilityAction(.escape, close)
        .onChange(of: session.isPresented) { _, presented in
            if !presented { dismissPresentation() }
        }
        .onChange(of: isGestureActive) { _, active in
            // Gesture cancellation does not call onEnded (e.g. interruption).
            if !active, isDragging, session.isPresented {
                withAnimation(animation) {
                    isDragging = false
                    dragTranslation = 0
                }
            }
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

    @ViewBuilder
    private var sheetBackground: some View {
        if reduceTransparency || !hardware.isGlassmorphismEnabled {
            Color(uiColor: .secondarySystemBackground)
        } else {
            Rectangle().fill(.regularMaterial).overlay(Color.black.opacity(0.18))
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                notesHeader.padding(.top, 20).padding(.bottom, 16)
                Button(action: close) {
                    VStack {
                        Capsule().fill(.secondary).frame(width: 36, height: 5).padding(.top, 6)
                        Spacer(minLength: 0)
                    }
                    .frame(width: 80, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Field notes")
                .accessibilityHint("Double-tap to close, or drag the header down")
                .accessibilityIdentifier("FieldNotesClose")
            }
            .contentShape(Rectangle())
            // A recognized drag must cancel the close handle's tap, including
            // when a title drag starts inside its accessible hit region.
            .highPriorityGesture(sheetDrag)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
            if showsPrompts {
                promptsPage
            } else {
                notesContent
            }
        }
        .padding(.horizontal, 8)
        .disabled(session.isSubmitting || !session.isPresented)
    }

    private var promptsPage: some View {
        NavigationStack {
            List {
                ForEach(session.prompts.activeQuestions.indices, id: \.self) { index in
                    Button(session.prompts.displayPrompt(at: index)) {
                        guard workspace.acceptsFieldNotesWrite(session) else { return }
                        session.prompts.activeQuestionIndex = index
                        showsPrompts = false
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Prompts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showsPrompts = false } label: {
                        Label("Field notes", systemImage: "chevron.left")
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private var sheetDrag: some Gesture {
        // The header moves with the panel; measure against the stationary screen.
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .updating($isGestureActive) { _, active, _ in active = true }
            .onChanged { value in
                guard session.isPresented, !session.isSubmitting,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                if !isDragging {
                    isDragging = true
                    workspace.dependencies.feedback.selection("capture.field-notes.drag")
                }
                dragTranslation = value.translation.height
            }
            .onEnded { value in
                guard session.isPresented, !session.isSubmitting,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                if value.translation.height > 80 || value.predictedEndTranslation.height > 160 {
                    close()
                } else {
                    withAnimation(animation) {
                        isDragging = false
                        if value.translation.height < -30 { isExpanded = true }
                        dragTranslation = 0
                    }
                }
            }
    }

    private var notesContent: some View {
        GeometryReader { viewport in
            ScrollViewReader { reader in
                ScrollView {
                    VStack(spacing: 8) {
                        VStack(spacing: 8) {
                            if workspace.describePromptFlow.isReanalysis {
                                DescribeReanalysisHeaderView()
                            } else {
                                if session.prompts.activeQuestionIndex > 0 || session.prompts.isFunnelActive {
                                    DescribeQuestionNavigationView(
                                        questionCount: session.prompts.activeQuestions.count,
                                        activeQuestionIndex: session.prompts.activeQuestionIndex,
                                        selectionFeedback: presentation.selectionFeedback,
                                        onPrevious: session.prompts.moveToPreviousQuestion,
                                        onNext: session.prompts.advanceQuestion
                                    )
                                }
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
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { promptHeight = $0 }
                        CaptureFieldNotesTextEditor(text: context.freeText, focus: $isTextFocused)
                            .frame(height: textEditorHeight(in: viewport.size.height))
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                            .id("FieldNotesEditorViewport")
                        if let error = session.errorMessage {
                            Text(error).font(.callout).foregroundStyle(.red).padding(.horizontal)
                        }
                    }
                    .padding(.top, 16)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        // Keep the resting detent independent of the flexible editor
                        // while dragging, expanded, or accommodating the keyboard.
                        if !isTextFocused, !isExpanded, !isDragging { contentHeight = height }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
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

    private func textEditorHeight(in viewportHeight: CGFloat) -> CGFloat {
        guard isTextFocused || isExpanded || isDragging else { return 180 }
        // Fit prompt cards and input together when possible. At accessibility
        // sizes, reserve a readable input viewport and let the prompts scroll.
        let minimum = min(minimumEditorHeight, max(44, viewportHeight - 24))
        return max(minimum, viewportHeight - promptHeight - 32)
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
    }

    private func notesHeaderIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 20))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .background(.primary.opacity(0.1), in: Circle())
            .contentShape(Circle())
    }

    private var animation: Animation? { reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86) }

    private func close() { workspace.closeFieldNotes(sessionID: session.id) }

    private func dismissPresentation() {
        isTextFocused = false
        workspace.dependencies.feedback.sheet("capture.field-notes.close")
        withAnimation(animation, completionCriteria: .removed) {
            isDragging = false
            isVisible = false
            dragTranslation = 0
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
