import SwiftUI

// MARK: - View

/// Full-screen text-first input field for Describe identification.
///
/// The view is intentionally decoupled from `InferenceEngine` and `CaptureWorkspaceViewModel` —
/// it only produces an `ObservationContext` value and delivers it via `onSubmit`.
/// All network orchestration and multi-modal routing lives in `CaptureWorkspaceViewModel.submitDescribe`.
///
/// Layout contract with `CaptureWorkspaceView`:
/// - Fills the full page frame (same size as the camera and audio pages).
/// - The fixed `MediaModeToggle` overlay sits above this view in the Z-stack and
///   always remains interactive; this view must NOT place anything above the
///   `safeAreaInsets.top + 64` band.
struct DescribeInputView: View {
    var captureMode: CaptureMode

    @Binding var context: ObservationContext
    @FocusState private var isTextFieldFocused: Bool
    @Environment(SpeechManager.self) private var speechManager

    let coordinator: CaptureActionCoordinator

    @State private var promptManager = DescribePromptManager()
    @State private var isDescribeQuestionsSheetPresented: Bool = false

    // MARK: - Dictation state

    @State private var dictationTask: Task<Void, Never>?
    @State private var inferenceDebounceTask: Task<Void, Never>?

    // MARK: - Derived

    private var topSafeArea: CGFloat {
        let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        return windowScene?.windows.first?.safeAreaInsets.top ?? 59
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color(UIColor.systemBackground)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    // Top spacer: device safe area + MediaModeToggle (16pt padding + ~44pt height) + 20pt gap.
                    Spacer().frame(height: topSafeArea + 60)

                    // MARK: Question Header
                    VStack(alignment: .leading, spacing: 0) {

                        // Navigation row: dots flush left (decorative only), buttons flush right.
                        HStack {
                            HStack(spacing: 5) {
                                ForEach(promptManager.activeQuestions.indices, id: \.self) { idx in
                                    Circle()
                                        .fill(idx == promptManager.activeQuestionIndex
                                              ? Color.primary
                                              : Color.primary.opacity(0.2))
                                        .frame(width: 6, height: 6)
                                }
                            }.animation(.easeInOut(duration: 0.3), value: promptManager.activeQuestionIndex)

                            Spacer()

                            HStack(spacing: 4) {
                                Button(action: previousQuestion) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.primary)
                                        .frame(width: 44, height: 44)
                                }
                                Button(action: advanceQuestion) {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.primary)
                                        .frame(width: 44, height: 44)
                                }
                            }
                        }

                    // MARK: Question Header
                    DescribePromptHeader(
                        promptManager: promptManager,
                        appendTag: appendTag,
                        advanceQuestion: advanceQuestion
                    )
                    } // Closes VStack(alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                    // MARK: Text Area
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(UIColor.secondarySystemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(
                                        isTextFieldFocused
                                            ? Color.primary.opacity(0.3)
                                            : Color.primary.opacity(0.12),
                                        lineWidth: 0.5
                                    )
                            )

                        TextField(
                            "e.g., A bright green beetle with gold stripes resting on an oak leaf...",
                            text: $context.freeText,
                            axis: .vertical
                        )
                        .lineLimit(5...10)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .focused($isTextFieldFocused)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 48)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(minHeight: 160)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)

                    Spacer() // Absorbs extra vertical space

                    // Bottom spacer: clears the global tab bar / scan toolbar
                    Spacer().frame(height: 250)
                }
                .frame(minHeight: proxy.size.height)
            }
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: context.freeText) { _, newText in
                if newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    promptManager.resetFunnel()
                    return
                }
                guard !promptManager.isFunnelActive else {
                    inferenceDebounceTask?.cancel()
                    inferenceDebounceTask = nil
                    return
                }
                inferenceDebounceTask?.cancel()
                inferenceDebounceTask = Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    guard !Task.isCancelled else { return }
                    guard !promptManager.isFunnelActive else { return }
                    if let subjectId = SubjectKeywordMatcher.infer(from: newText) {
                        promptManager.activateFunnel(for: subjectId)
                    }
                }
            }
            .onChange(of: captureMode) { _, newMode in
                if newMode != .describe {
                    isTextFieldFocused = false
                    stopDictation()
                    inferenceDebounceTask?.cancel()
                    inferenceDebounceTask = nil
                }
            }
            .onChange(of: coordinator.isDictationRequested) { _, requested in
                if requested {
                    startDictation()
                } else {
                    stopDictation()
                }
            }
            .onChange(of: speechManager.isRecording) { _, isRecording in
                if !isRecording && coordinator.isDictationRequested {
                    // Sync the button state if the SpeechManager halts intrinsically (e.g., error/timeout)
                    coordinator.isDictationRequested = false
                }
            }
            .onChange(of: coordinator.tocRequestID) { _, id in
                if id != nil {
                    isDescribeQuestionsSheetPresented = true
                }
            }
        }
        .sheet(isPresented: $isDescribeQuestionsSheetPresented) {
            DescribeQuestionsSheet(
                promptManager: promptManager
            )
        }
        }
    }

    // MARK: - Helpers
    
    private func startDictation() {
        let base = context.freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        dictationTask = Task {
            do {
                try await speechManager.startDictation { transcribed in
                    guard !transcribed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    context.freeText = base.isEmpty ? transcribed : base + " " + transcribed
                }
            } catch {
                coordinator.isDictationRequested = false
            }
        }
    }
    
    private func stopDictation() {
        guard dictationTask != nil || coordinator.isDictationRequested else { return }
        speechManager.stopDictation()
        dictationTask?.cancel()
        dictationTask = nil
        coordinator.isDictationRequested = false
    }

    private func advanceQuestion() {
        let count = promptManager.activeQuestions.count
        guard count > 0 else { return }
        let next = (promptManager.activeQuestionIndex + 1) % count
        withAnimation(.easeInOut(duration: 0.4)) {
            promptManager.activeQuestionIndex = next
        }
    }

    private func previousQuestion() {
        let count = promptManager.activeQuestions.count
        guard count > 0 else { return }
        let prev = (promptManager.activeQuestionIndex - 1 + count) % count
        withAnimation(.easeInOut(duration: 0.4)) {
            promptManager.activeQuestionIndex = prev
        }
    }

    /// Inserts the tag's optimized AI text fragment into freeText, maintaining
    /// natural sentence flow.
    private func appendTag(_ tag: GuidedQuestion.Tag) {
        DescribeTagTracker.shared.recordUsage(for: tag.tagId)
        
        // Handle toggling off an active funnel
        if promptManager.activeQuestionIndex == 0 && promptManager.activeSubjectId == tag.tagId {
            promptManager.resetFunnel()
            
            // Try to gracefully remove the text insertion
            let insertion = tag.aiText
            if !insertion.isEmpty {
                let capped = insertion.prefix(1).uppercased() + insertion.dropFirst()
                var text = context.freeText
                
                if let range = text.range(of: capped + ".") {
                    text.removeSubrange(range)
                } else if let range = text.range(of: ", " + insertion) {
                    text.removeSubrange(range)
                } else if let range = text.range(of: insertion) {
                    text.removeSubrange(range)
                } else if let range = text.range(of: capped) {
                    text.removeSubrange(range)
                }
                
                context.freeText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return
        }
        
        let insertion = tag.aiText
        if !insertion.isEmpty {
            let trimmed = context.freeText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                context.freeText = insertion.prefix(1).uppercased() + insertion.dropFirst()
            } else {
                let endsWithSentence = trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?")
                if endsWithSentence {
                    let capped = insertion.prefix(1).uppercased() + insertion.dropFirst()
                    context.freeText = trimmed + " " + capped + "."
                } else {
                    context.freeText = trimmed + ", " + insertion
                }
            }
        }
        
        // Funnel activation: subject tags on Q1 switch the question sequence
        if promptManager.activeQuestionIndex == 0 {
            if promptManager.activeSubjectId != tag.tagId {
                if subjectFunnels[tag.tagId] != nil {
                    promptManager.resetFunnel()
                    promptManager.activateFunnel(for: tag.tagId)
                } else if promptManager.isFunnelActive {
                    promptManager.resetFunnel()
                }
            }
        }
    }
}

// MARK: - Subcomponents

private struct DescribePromptHeader: View {
    @Bindable var promptManager: DescribePromptManager
    let appendTag: (GuidedQuestion.Tag) -> Void
    let advanceQuestion: () -> Void
    
    private var sortedTags: [GuidedQuestion.Tag] {
        guard promptManager.activeQuestionIndex >= 0 && promptManager.activeQuestionIndex < promptManager.activeQuestions.count else { return [] }
        return promptManager.activeQuestions[promptManager.activeQuestionIndex].tags
            .enumerated()
            .sorted { a, b in
                let freqA = DescribeTagTracker.shared.frequency(for: a.element.tagId)
                let freqB = DescribeTagTracker.shared.frequency(for: b.element.tagId)
                if freqA != freqB { return freqA > freqB }
                if a.element.defaultWeight != b.element.defaultWeight {
                    return a.element.defaultWeight > b.element.defaultWeight
                }
                return a.offset < b.offset
            }
            .map(\.element)
    }
    
    var body: some View {
        // Heading text
        if promptManager.activeQuestions.indices.contains(promptManager.activeQuestionIndex) {
            Text(promptManager.activeQuestions[promptManager.activeQuestionIndex].prompt)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 35, alignment: .topLeading)
                .padding(.bottom, 8)
        }
        
        // Tags
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sortedTags, id: \.self) { tag in
                    let isSelectedFunnel = promptManager.activeQuestionIndex == 0 && tag.tagId == promptManager.activeSubjectId
                    Button(action: {
                        HapticManager.shared.triggerSelectionPulse()
                        let indexBeforeAppend = promptManager.activeQuestionIndex
                        appendTag(tag)
                        
                        if isSelectedFunnel { return } // Avoid auto-advance if they are unselecting
                        
                        if !promptManager.interactedQuestionIndices.contains(indexBeforeAppend) {
                            promptManager.interactedQuestionIndices.insert(indexBeforeAppend)
                            
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 350_000_000)
                                guard !Task.isCancelled else { return }
                                if promptManager.activeQuestionIndex == indexBeforeAppend {
                                    advanceQuestion()
                                }
                            }
                        }
                    }) {
                        if let imageName = tag.imageName {
                            VStack(spacing: 4) {
                                Image(imageName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 64, height: 64)
                                Text(tag.label)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(isSelectedFunnel ? Color(UIColor.systemBackground) : .primary)
                            .frame(width: 96, height: 112)
                            .background(isSelectedFunnel ? Color.primary : Color(UIColor.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        } else {
                            Text(tag.label)
                                .font(.subheadline)
                                .foregroundStyle(isSelectedFunnel ? Color(UIColor.systemBackground) : .primary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(isSelectedFunnel ? Color.primary : Color(UIColor.secondarySystemBackground))
                                .clipShape(Capsule())
                        }
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: promptManager.activeQuestionIndex)
        }
        .padding(.bottom, 16)
    }
}
