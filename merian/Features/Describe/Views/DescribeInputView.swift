import SwiftUI



// MARK: - View

/// Full-screen text-first input field for Describe identification.
///
/// The view is intentionally decoupled from `InferenceEngine` and `CameraViewModel` —
/// it only produces an `ObservationContext` value and delivers it via `onSubmit`.
/// All network orchestration and multi-modal routing lives in `CameraViewModel.submitDescribe`.
///
/// Layout contract with `CameraRootView`:
/// - Fills the full page frame (same size as the camera and audio pages).
/// - The fixed `MediaModeToggle` overlay sits above this view in the Z-stack and
///   always remains interactive; this view must NOT place anything above the
///   `safeAreaInsets.top + 64` band.
struct DescribeInputView: View {
    var captureMode: CaptureMode

    @Binding var context: ObservationContext
    @FocusState private var isTextFieldFocused: Bool
    @Environment(SpeechManager.self) private var speechManager

    var promptManager: DescribePromptManager

    // MARK: - Dictation state

    @State private var dictationTask: Task<Void, Never>?

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
                                ForEach(guidedQuestions.indices, id: \.self) { idx in
                                    Circle()
                                        .fill(idx == promptManager.activeQuestionIndex
                                              ? Color.primary
                                              : Color.primary.opacity(0.2))
                                        .frame(width: 6, height: 6)
                                        .animation(.easeInOut(duration: 0.3), value: promptManager.activeQuestionIndex)
                                }
                            }

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

                        // Heading text — full width, crossfades between questions.
                        // We use a single Text view with an .id modifier to force
                        // a transition when the active question changes, which is far
                        // more reliable than the prior ZStack opacity workaround.
                        Text(guidedQuestions[promptManager.activeQuestionIndex].prompt)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                            .id("prompt_\(promptManager.activeQuestionIndex)")
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.35), value: promptManager.activeQuestionIndex)
                            .frame(maxWidth: .infinity, minHeight: 35, alignment: .topLeading)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                    // MARK: Contextual Quick Tags
                    // Tags are scoped to the active question. Tapping inserts the optimized
                    // aiText fragment into freeText.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(guidedQuestions[promptManager.activeQuestionIndex].tags, id: \.self) { tag in
                                Button(action: {
                                    HapticManager.shared.triggerSelectionPulse()
                                    appendTag(tag)
                                    
                                    let currentIdx = promptManager.activeQuestionIndex
                                    if !promptManager.interactedQuestionIndices.contains(currentIdx) {
                                        promptManager.interactedQuestionIndices.insert(currentIdx)
                                        
                                        Task { @MainActor in
                                            // Slight delay so the user witnesses the text append and haptic feedback
                                            try? await Task.sleep(nanoseconds: 350_000_000)
                                            guard !Task.isCancelled else { return }
                                            
                                            // Only advance if they haven't manually navigated away
                                            if promptManager.activeQuestionIndex == currentIdx {
                                                advanceQuestion()
                                            }
                                        }
                                    }
                                }) {
                                    Text(tag.label)
                                        .foregroundStyle(.primary)
                                        .font(.subheadline)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(Color(UIColor.secondarySystemBackground))
                                        .clipShape(Capsule())
                                }
                                .transition(.opacity)
                            }
                        }
                        .padding(.horizontal, 20)
                        .animation(.easeInOut(duration: 0.3), value: promptManager.activeQuestionIndex)
                    }
                    .padding(.bottom, 16)

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
            .onChange(of: captureMode) { _, newMode in
                if newMode != .describe {
                    isTextFieldFocused = false
                    dictationTask?.cancel()
                    dictationTask = nil
                }
            }
        }
        }
    }

    // MARK: - Helpers

    private func advanceQuestion() {
        let next = (promptManager.activeQuestionIndex + 1) % guidedQuestions.count
        withAnimation(.easeInOut(duration: 0.4)) {
            promptManager.activeQuestionIndex = next
        }
    }

    private func previousQuestion() {
        let prev = (promptManager.activeQuestionIndex - 1 + guidedQuestions.count) % guidedQuestions.count
        withAnimation(.easeInOut(duration: 0.4)) {
            promptManager.activeQuestionIndex = prev
        }
    }

    /// Inserts the tag's optimized AI text fragment into freeText, maintaining
    /// natural sentence flow.
    private func appendTag(_ tag: GuidedQuestion.Tag) {
        let insertion = tag.aiText
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
}

