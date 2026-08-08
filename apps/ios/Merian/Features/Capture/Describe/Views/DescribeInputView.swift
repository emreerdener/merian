import SwiftUI
import UIKit

// MARK: - View

private struct DescribeVerticalScrollView<Content: View>: UIViewControllerRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIViewController(context: Context) -> DescribeScrollHostingController<Content> {
        DescribeScrollHostingController(rootView: content)
    }

    func updateUIViewController(
        _ controller: DescribeScrollHostingController<Content>,
        context: Context
    ) {
        controller.hostingController.rootView = content
        controller.hostingController.view.invalidateIntrinsicContentSize()
    }
}

private final class DescribeScrollHostingController<Content: View>: UIViewController {
    let hostingController: UIHostingController<Content>

    init(rootView: Content) {
        hostingController = UIHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = UIView()
        rootView.backgroundColor = .clear

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.keyboardDismissMode = .onDrag
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear

        let hostedView = hostingController.view!
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        hostedView.backgroundColor = .clear

        rootView.addSubview(scrollView)
        addChild(hostingController)
        scrollView.addSubview(hostedView)
        hostingController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: rootView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            hostedView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hostedView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            hostedView.heightAnchor.constraint(
                greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor
            )
        ])

        view = rootView
    }
}

struct DescribeInputLifecycleObserver: View {
    let captureMode: CaptureMode
    let promptFlow: DescribePromptFlow
    @Binding var context: ObservationContext
    let promptManager: DescribePromptManager
    @Binding var isQuestionsSheetPresented: Bool
    let coordinator: CaptureActionCoordinator

    @Environment(SpeechManager.self) private var speechManager
    @State private var dictationTask: Task<Void, Never>?

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task(id: promptFlow) {
                promptManager.configure(for: promptFlow)
                if promptFlow.isReanalysis {
                    isQuestionsSheetPresented = false
                }
            }
            .task(id: context.freeText) {
                let newText = context.freeText
                guard !promptFlow.isReanalysis else { return }
                if newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    promptManager.resetFunnel()
                    return
                }
                guard !promptManager.isFunnelActive else { return }

                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled, !promptManager.isFunnelActive else { return }
                if let subjectId = SubjectKeywordMatcher.infer(from: newText) {
                    promptManager.activateFunnel(for: subjectId)
                }
            }
            .task(id: captureMode) {
                if captureMode != .describe {
                    stopDictation()
                }
            }
            .task(id: coordinator.isDictationRequested) {
                if coordinator.isDictationRequested {
                    startDictation()
                } else {
                    stopDictation()
                }
            }
            .task(id: speechManager.isRecording) {
                if !speechManager.isRecording && coordinator.isDictationRequested {
                    coordinator.isDictationRequested = false
                }
            }
            .task(id: coordinator.tocRequestID) {
                if coordinator.tocRequestID != nil && !promptFlow.isReanalysis {
                    isQuestionsSheetPresented = true
                }
            }
            .onDisappear {
                stopDictation()
            }
    }

    private func startDictation() {
        guard dictationTask == nil else { return }
        let base = context.freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        dictationTask = Task {
            defer { dictationTask = nil }
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
        guard dictationTask != nil
                || coordinator.isDictationRequested
                || speechManager.isRecording
                || speechManager.isStarting else { return }
        speechManager.stopDictation()
        dictationTask?.cancel()
        dictationTask = nil
        coordinator.isDictationRequested = false
    }
}

/// Full-screen text-first input field for Describe identification.
///
/// The view only produces an `ObservationContext` value; all network orchestration
/// and multi-modal routing lives in `CaptureWorkspaceViewModel.submitDescribe`.
///
/// Layout contract with `CaptureWorkspaceView`:
/// - Fills the full page frame (same size as the camera and audio pages).
/// - The fixed `MediaModeToggle` overlay sits above this view in the Z-stack and
///   always remains interactive; this view must NOT place anything above the
///   `safeAreaInsets.top + 64` band.
struct DescribeInputView: View {
    let promptFlow: DescribePromptFlow

    @Binding var context: ObservationContext
    @FocusState private var isTextFieldFocused: Bool

    let promptManager: DescribePromptManager

    init(
        promptFlow: DescribePromptFlow,
        context: Binding<ObservationContext>,
        promptManager: DescribePromptManager
    ) {
        self.promptFlow = promptFlow
        self._context = context
        self.promptManager = promptManager
    }

    // MARK: - Derived

    private var textFieldPlaceholder: String {
        isReanalysisMode
            ? DescribePromptCopy.reanalysisInputPlaceholder
            : DescribePromptCopy.standardInputPlaceholder
    }

    private var isReanalysisMode: Bool {
        promptFlow.isReanalysis || promptManager.isReanalysisFlow
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(UIColor.systemBackground)

            DescribeVerticalScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // The hosted page already begins in safe-area coordinates.
                    // Reserve only the fixed mode-toggle band and visual gap.
                    Spacer().frame(height: 60)

                    // MARK: Question Header
                    VStack(alignment: .leading, spacing: 0) {
                        if isReanalysisMode {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(DescribePromptCopy.reanalysisHeading)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.primary)

                                Text(DescribePromptCopy.reanalysisSubheading)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, minHeight: 35, alignment: .topLeading)
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .padding(.bottom, 16)
                        } else {
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
                            .padding(.horizontal, 20)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("DescribeQuestionNavigation")

                            DescribePromptHeader(
                                promptManager: promptManager,
                                appendTag: appendTag,
                                advanceQuestion: advanceQuestion
                            )
                        }
                    } // Closes VStack(alignment: .leading)

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

                        VStack(spacing: 0) {
                            TextField(
                                textFieldPlaceholder,
                                text: $context.freeText,
                                axis: .vertical
                            )
                            .id(textFieldPlaceholder)
                            .accessibilityLabel(textFieldPlaceholder)
                            .lineLimit(5...10)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .focused($isTextFieldFocused)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 48)
                            .frame(maxWidth: .infinity, alignment: .topLeading)

                            // Absorb the page's remaining height inside the
                            // rounded editor instead of below it.
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(minHeight: 160, maxHeight: .infinity)
                    .layoutPriority(1)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("DescribeTextArea")
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)

                    // Keep the editor clear of the fixed capture row and the
                    // global tab bar while this page scrolls independently.
                    Spacer().frame(height: CaptureControlBarLayout.describeContentBottomClearance)
                }
            }
        }
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
        isTextFieldFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        // Handle toggling off an active funnel
        if promptManager.activeQuestionIndex == 0 && promptManager.activeSubjectId == tag.tagId {
            promptManager.clearSubjectSelection()
            
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
    @State private var pendingAutoAdvance: PendingAutoAdvance?

    private struct PendingAutoAdvance: Equatable {
        let id = UUID()
        let questionIndex: Int
    }
    
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
            Text(promptManager.currentPrompt)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 35, alignment: .topLeading)
                .padding(.horizontal, 20)
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
                            pendingAutoAdvance = PendingAutoAdvance(
                                questionIndex: indexBeforeAppend
                            )
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
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .padding(.bottom, 16)
        .task(id: pendingAutoAdvance?.id) {
            guard let request = pendingAutoAdvance else { return }
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  pendingAutoAdvance?.id == request.id,
                  promptManager.activeQuestionIndex == request.questionIndex else {
                return
            }
            pendingAutoAdvance = nil
            advanceQuestion()
        }
    }
}
