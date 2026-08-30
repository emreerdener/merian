import SwiftUI

/// Full-screen text-first input field for Describe identification.
///
/// The view only produces an `ObservationContext` value. Submission and
/// multi-modal routing remain owned by `CaptureWorkspaceViewModel`.
struct DescribeInputView: View {
    let promptFlow: DescribePromptFlow
    @Binding var context: ObservationContext
    let promptViewModel: DescribePromptViewModel

    @FocusState private var isTextFieldFocused: Bool
    private let dependencies: DescribePresentationDependencies

    @MainActor
    init(
        promptFlow: DescribePromptFlow,
        context: Binding<ObservationContext>,
        promptViewModel: DescribePromptViewModel
    ) {
        self.init(
            promptFlow: promptFlow,
            context: context,
            promptViewModel: promptViewModel,
            dependencies: .live
        )
    }

    @MainActor
    init(
        promptFlow: DescribePromptFlow,
        context: Binding<ObservationContext>,
        promptViewModel: DescribePromptViewModel,
        dependencies: DescribePresentationDependencies
    ) {
        self.promptFlow = promptFlow
        _context = context
        self.promptViewModel = promptViewModel
        self.dependencies = dependencies
    }

    private var isReanalysisMode: Bool {
        promptFlow.isReanalysis || promptViewModel.isReanalysisFlow
    }

    private var textFieldPlaceholder: String {
        isReanalysisMode
            ? DescribePromptCopy.reanalysisInputPlaceholder
            : DescribePromptCopy.standardInputPlaceholder
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(UIColor.systemBackground)

            DescribeVerticalScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // The hosted page already begins in safe-area coordinates.
                    Spacer().frame(
                        height: CaptureModeSelectorStyle.describeContentClearance
                    )

                    VStack(alignment: .leading, spacing: 0) {
                        if isReanalysisMode {
                            DescribeReanalysisHeaderView()
                        } else {
                            DescribeQuestionNavigationView(
                                questionCount: promptViewModel.activeQuestions.count,
                                activeQuestionIndex:
                                    promptViewModel.activeQuestionIndex,
                                onPrevious: previousQuestion,
                                onNext: advanceQuestion
                            )

                            DescribePromptTagsView(
                                promptViewModel: promptViewModel,
                                tagFrequency: dependencies.tagFrequency,
                                selectionFeedback: dependencies.selectionFeedback,
                                onSelectTag: selectTag,
                                onAdvanceQuestion: advanceQuestion
                            )
                        }
                    }

                    DescribeTextEditorView(
                        placeholder: textFieldPlaceholder,
                        text: $context.freeText,
                        focus: $isTextFieldFocused
                    )

                    // Reserve the fixed capture row and global tab-bar clearance.
                    Spacer().frame(
                        height: CaptureControlBarLayout.describeContentBottomClearance
                    )
                }
            }
        }
    }

    private func advanceQuestion() {
        withAnimation(.easeInOut(duration: 0.4)) {
            promptViewModel.advanceQuestion()
        }
    }

    private func previousQuestion() {
        withAnimation(.easeInOut(duration: 0.4)) {
            promptViewModel.moveToPreviousQuestion()
        }
    }

    private func selectTag(_ tag: GuidedQuestion.Tag) {
        dependencies.recordTagUsage(tag.tagId)
        isTextFieldFocused = false
        dependencies.dismissKeyboard()

        let isRemovingSubject = promptViewModel.activeQuestionIndex == 0
            && promptViewModel.activeSubjectId == tag.tagId
        context.freeText = DescribeTextComposer.applying(
            tag,
            to: context.freeText,
            isRemoving: isRemovingSubject
        )

        if isRemovingSubject {
            promptViewModel.clearSubjectSelection()
        } else {
            promptViewModel.applySubjectSelection(for: tag)
        }
    }
}
