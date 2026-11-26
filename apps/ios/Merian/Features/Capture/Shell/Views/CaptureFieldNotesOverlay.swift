import SwiftUI

@MainActor
@Observable
private final class CaptureFieldNotesMotion {
    var isVisible = false
    var isExpanded = false
    var isDragging = false
    var dragTranslation: CGFloat = 0
}

/// Keep native glass and the grabber mounted while the editor expands/collapses.
struct CaptureFieldNotesOverlay<Toolbar: View>: View {
    let workspace: CaptureWorkspaceViewModel
    let speechManager: SpeechManager
    var toolbarBottomPadding: CGFloat = 0
    var onNavigation: (CapturePhotoReviewAction) -> Void = { _ in }
    var onOpenNotes: () -> Void = {}
    var onToolbarHeightChange: (CGFloat) -> Void = { _ in }
    @ViewBuilder let toolbar: () -> Toolbar
    @State private var motion = CaptureFieldNotesMotion()
    @State private var toolbarHeight: CGFloat = CaptureStagingToolbarMetrics.compactHeight
    @GestureState private var isGestureActive = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(HardwareOrchestrator.self) private var hardware

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                if workspace.isFieldNotesOccupied {
                    Color.black.opacity(motion.isVisible ? 0.2 : 0)
                        .contentShape(Rectangle()).onTapGesture(perform: close).accessibilityHidden(true)
                }
                VStack(spacing: 0) {
                    if let session = workspace.fieldNotesSession {
                        CaptureFieldNotesPanel(workspace: workspace, session: session, speechManager: speechManager,
                            availableHeight: max(0, geometry.size.height - toolbarHeight - toolbarBottomPadding - 24),
                            motion: motion, sheetDrag: sheetDrag, onNavigation: onNavigation)
                            .id(session.id)
                            .transition(.identity)
                    }
                    toolbar()
                        .environment(\.captureNotesVisible, motion.isVisible)
                        .environment(\.captureNotesOwnsGrabber, true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            toolbarHeight = $0
                            onToolbarHeightChange($0)
                        }
                        .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { value in
                            guard !workspace.isFieldNotesOccupied, value.translation.height < -30,
                                  abs(value.translation.height) > abs(value.translation.width) else { return }
                            onOpenNotes()
                        })
                }
                // Reserve the panel floor even while closed so the toolbar never changes anchors.
                .padding(.bottom, CaptureStagingToolbarMetrics.bottomInset)
                .background {
                    sheetBackground.clipShape(RoundedRectangle(cornerRadius: motion.isVisible ? 32 : 50))
                        .padding(.horizontal, 8).opacity(motion.isVisible ? 1 : 0)
                }
                .overlay(alignment: .top) { grabber }
                .environment(\.colorScheme, .dark)
                .padding(.bottom, toolbarBottomPadding)
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(workspace.isFieldNotesOccupied ? .isModal : [])
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
        }
        .onChange(of: workspace.fieldNotesSession?.id) { _, id in
            if id == nil { motion.isVisible = false; motion.isDragging = false; motion.dragTranslation = 0 }
        }
        .onChange(of: isGestureActive) { _, active in
            if !active, motion.isDragging, workspace.fieldNotesSession?.isPresented == true {
                withAnimation(animation) { motion.isDragging = false; motion.dragTranslation = 0 }
            }
        }
    }

    private var grabber: some View {
        Button {
            if workspace.isFieldNotesOccupied { close() } else { onOpenNotes() }
        } label: {
            VStack(spacing: 0) {
                CaptureNotesGrabber().padding(.top, motion.isVisible ? 6 : 34)
                Spacer(minLength: 0)
            }
            .frame(width: 80, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Keep the closed handle's 44-point target above the media buttons.
        .offset(y: motion.isVisible ? 0 : -28)
        .accessibilityLabel(workspace.isFieldNotesOccupied ? "Close Field notes" : "Open Field notes")
        .accessibilityHint("Double-tap or drag to expand or close")
        .accessibilityIdentifier(workspace.isFieldNotesOccupied ? "FieldNotesClose" : "FieldNotesOpen")
        .disabled(workspace.fieldNotesSession.map { !$0.isPresented || $0.isSubmitting } ?? workspace.areCaptureActionsBlocked)
        .highPriorityGesture(sheetDrag)
    }

    @ViewBuilder private var sheetBackground: some View {
        if reduceTransparency || !hardware.isGlassmorphismEnabled { Color(uiColor: .secondarySystemBackground) } else {
            Rectangle().fill(.regularMaterial).overlay(Color.black.opacity(0.18))
        }
    }
    private var animation: Animation? { reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86) }
    private func close() {
        if let session = workspace.fieldNotesSession { workspace.closeFieldNotes(sessionID: session.id) }
    }
    private var sheetDrag: AnyGesture<DragGesture.Value> {
        // The header moves with the panel; measure against the stationary screen.
        AnyGesture(DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .updating($isGestureActive) { _, active, _ in active = true }
            .onChanged { value in
                guard let session = workspace.fieldNotesSession, session.isPresented, !session.isSubmitting,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                if !motion.isDragging {
                    motion.isDragging = true
                    workspace.dependencies.feedback.selection("capture.field-notes.drag")
                }
                motion.dragTranslation = value.translation.height
            }
            .onEnded { value in
                if !workspace.isFieldNotesOccupied, value.translation.height < -30,
                   abs(value.translation.height) > abs(value.translation.width) { onOpenNotes(); return }
                guard let session = workspace.fieldNotesSession, session.isPresented, !session.isSubmitting,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                if value.translation.height > 80 || value.predictedEndTranslation.height > 160 {
                    close()
                } else {
                    withAnimation(animation) {
                        motion.isDragging = false
                        if value.translation.height < -30 { motion.isExpanded = true }
                        motion.dragTranslation = 0
                    }
                }
            })
    }

}

/// One outer presentation owns the editor, nested prompts, and dismissal barrier.
/// The same observation toolbar stays above the keyboard while editing.
private struct CaptureFieldNotesPanel: View {
    let workspace: CaptureWorkspaceViewModel
    let session: CaptureFieldNotesSession
    let speechManager: SpeechManager
    let availableHeight: CGFloat
    let motion: CaptureFieldNotesMotion
    let sheetDrag: AnyGesture<DragGesture.Value>
    var onNavigation: (CapturePhotoReviewAction) -> Void = { _ in }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isTextFocused: Bool
    @State private var hasFinishedDismissal = false
    @State private var showsPrompts = false
    @State private var contentHeight: CGFloat = 392
    @State private var promptHeight: CGFloat = 180
    @ScaledMetric(relativeTo: .body) private var minimumEditorHeight: CGFloat = 72
    @State private var headerHeight: CGFloat = 80
    private let presentation = DescribePresentationDependencies.live

    private var context: Binding<ObservationContext> {
        Binding(get: { workspace.descriptionDraft }, set: {
            _ = workspace.autosaveFieldNotes($0, session: session)
        })
    }

    var body: some View {
        let editorHeight = min(availableHeight, motion.isExpanded ? availableHeight : headerHeight + contentHeight)
        let draggedHeight = max(0, min(availableHeight, editorHeight - motion.dragTranslation))
        editor
            .frame(height: motion.isDragging ? draggedHeight : editorHeight)
            .frame(height: motion.isVisible ? draggedHeight : 0, alignment: .top)
            .clipped()
            .opacity(motion.isVisible ? 1 : 0)
            .accessibilityHidden(!motion.isVisible)
        .onAppear {
            guard session.isPresented else { dismissPresentation(); return }
            motion.isExpanded = false
            motion.isDragging = false
            motion.dragTranslation = 0
            workspace.dependencies.feedback.sheet("capture.field-notes.open")
            withAnimation(animation) { motion.isVisible = true }
        }
        .accessibilityAction(.escape, close)
        .onChange(of: session.isPresented) { _, presented in
            if !presented { dismissPresentation() }
        }
        .onChange(of: workspace.isInitialDraftWorkActive) { _, active in
            if !active { completeDismissalIfReady() }
        }
        .onChange(of: isTextFocused) { _, focused in
            if focused { withAnimation(animation) { motion.isExpanded = true } }
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
            notesHeader.padding(.top, 20).padding(.bottom, 16)
            .contentShape(Rectangle())
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
        List {
            ForEach(session.prompts.activeQuestions.indices, id: \.self) { index in
                Button {
                    guard workspace.acceptsFieldNotesWrite(session) else { return }
                    presentation.selectionFeedback()
                    session.prompts.activeQuestionIndex = index
                    showsPrompts = false
                } label: {
                    HStack {
                        Text(session.prompts.displayPrompt(at: index)).font(.body)
                        Spacer()
                        if index == session.prompts.activeQuestionIndex {
                            Image(systemName: "checkmark").fontWeight(.bold)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(index == session.prompts.activeQuestionIndex ? .isSelected : [])
                .accessibilityIdentifier("FieldNotesPrompt_\(index)")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("FieldNotesPromptList")
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
                        if !isTextFocused, !motion.isExpanded, !motion.isDragging { contentHeight = height }
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
        guard isTextFocused || motion.isExpanded || motion.isDragging else { return 180 }
        // Fit prompt cards and input together when possible. At accessibility
        // sizes, reserve a readable input viewport and let the prompts scroll.
        let minimum = min(minimumEditorHeight, max(44, viewportHeight - 24))
        return max(minimum, viewportHeight - promptHeight - 32)
    }

    /// Explicit controls avoid the native compact navigation-bar button shrinking
    /// the Field notes targets below the design's 44-point touch regions.
    private var notesHeader: some View {
        HStack {
            if showsPrompts {
                Button {
                    presentation.selectionFeedback()
                    showsPrompts = false
                } label: { notesHeaderIcon("chevron.left") }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to Field notes")
                .accessibilityIdentifier("FieldNotesPromptsBack")
            } else if !workspace.describePromptFlow.isReanalysis {
                Button {
                    isTextFocused = false
                    session.stopInput()
                    presentation.selectionFeedback()
                    motion.isExpanded = true
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
            Text(showsPrompts ? "Prompts" : "Field notes")
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("FieldNotesTitle")
            Spacer()
            if showsPrompts {
                Button("Reset", role: .destructive) {
                    workspace.resetFieldNotes(session: session)
                    presentation.selectionFeedback()
                    showsPrompts = false
                }
                .font(.body)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Reset field notes")
                .accessibilityIdentifier("FieldNotesReset")
            } else {
                Button(action: toggleDictation) {
                    notesHeaderIcon("microphone.fill", isRecording: isDictating)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(session.isDictationRequested ? "Stop dictation" : "Dictate notes")
                .accessibilityValue(isDictating ? "Recording" : (session.isDictationRequested ? "Starting" : "Off"))
                .accessibilityAddTraits(isDictating ? .isSelected : [])
                .disabled(session.isSubmitting)
                .accessibilityIdentifier("FieldNotesDictation")
            }
        }
        .padding(.horizontal, 16)
    }

    private var isDictating: Bool { session.isDictationRequested && speechManager.isRecording }

    private func notesHeaderIcon(_ name: String, isRecording: Bool = false) -> some View {
        Image(systemName: name)
            .font(.system(size: 20))
            .foregroundStyle(isRecording ? Color.white : Color.primary)
            .frame(width: 44, height: 44)
            .background(isRecording ? Color.red : Color.primary.opacity(0.1), in: Circle())
            .contentShape(Circle())
    }

    private var animation: Animation? { reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86) }

    private func close() { workspace.closeFieldNotes(sessionID: session.id) }

    private func dismissPresentation() {
        isTextFocused = false
        workspace.dependencies.feedback.sheet("capture.field-notes.close")
        withAnimation(animation, completionCriteria: .removed) {
            motion.isDragging = false
            motion.isVisible = false
            motion.dragTranslation = 0
        } completion: {
            hasFinishedDismissal = true
            completeDismissalIfReady()
        }
    }

    private func completeDismissalIfReady() {
        guard hasFinishedDismissal else { return }
        if let action = workspace.finishFieldNotesDismissal(sessionID: session.id) {
            onNavigation(action)
        }
    }

    private func toggleDictation() {
        guard workspace.acceptsFieldNotesWrite(session), !session.isSubmitting else { return }
        presentation.selectionFeedback()
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
