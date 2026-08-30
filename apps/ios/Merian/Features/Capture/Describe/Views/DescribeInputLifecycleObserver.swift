import SwiftUI

/// Workspace-scoped lifecycle owner kept outside the horizontal capture pager.
struct DescribeInputLifecycleObserver: View {
    let captureMode: CaptureMode
    let promptFlow: DescribePromptFlow
    @Binding var context: ObservationContext
    let promptViewModel: DescribePromptViewModel
    @Binding var isQuestionsSheetPresented: Bool
    let coordinator: CaptureActionCoordinator
    let speechManager: SpeechManager

    @State private var viewModel: DescribeInputViewModel

    @MainActor
    init(
        captureMode: CaptureMode,
        promptFlow: DescribePromptFlow,
        context: Binding<ObservationContext>,
        promptViewModel: DescribePromptViewModel,
        isQuestionsSheetPresented: Binding<Bool>,
        coordinator: CaptureActionCoordinator,
        speechManager: SpeechManager
    ) {
        self.captureMode = captureMode
        self.promptFlow = promptFlow
        _context = context
        self.promptViewModel = promptViewModel
        _isQuestionsSheetPresented = isQuestionsSheetPresented
        self.coordinator = coordinator
        self.speechManager = speechManager
        _viewModel = State(initialValue: DescribeInputViewModel(
            dependencies: .live(speechManager: speechManager)
        ))
    }

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task(id: promptFlow) {
                viewModel.promptFlowDidChange()
                promptViewModel.configure(for: promptFlow)
                if promptFlow.isReanalysis {
                    isQuestionsSheetPresented = false
                }
            }
            .task(id: context.freeText) {
                viewModel.descriptionDidChange(
                    text: context.freeText,
                    isReanalysis: promptFlow.isReanalysis,
                    isFunnelActive: promptViewModel.isFunnelActive,
                    shouldApplySubject: {
                        !promptViewModel.isFunnelActive
                    },
                    onDescriptionEmptied: {
                        promptViewModel.resetFunnel()
                    },
                    onSubjectInferred: { subjectId in
                        promptViewModel.activateFunnel(for: subjectId)
                    }
                )
            }
            .task(id: captureMode) {
                guard captureMode != .describe else { return }
                stopDictation()
            }
            .task(id: coordinator.isDictationRequested) {
                viewModel.dictationRequestDidChange(
                    isRequested: coordinator.isDictationRequested,
                    baseText: context.freeText,
                    onTranscript: { composedText in
                        context.freeText = composedText
                    },
                    onRequestEnded: {
                        coordinator.isDictationRequested = false
                    }
                )
            }
            .task(id: speechManager.isRecording) {
                viewModel.speechRecordingDidChange(
                    isRecording: speechManager.isRecording,
                    isRequested: coordinator.isDictationRequested,
                    onRequestEnded: {
                        coordinator.isDictationRequested = false
                    }
                )
            }
            .task(id: coordinator.tocRequestID) {
                if coordinator.tocRequestID != nil && !promptFlow.isReanalysis {
                    isQuestionsSheetPresented = true
                }
            }
            .onDisappear {
                stopAll()
            }
    }

    private func stopAll() {
        viewModel.stopAll(
            isRequested: coordinator.isDictationRequested,
            isRecording: speechManager.isRecording,
            isStarting: speechManager.isStarting,
            onRequestEnded: {
                coordinator.isDictationRequested = false
            }
        )
    }

    private func stopDictation() {
        viewModel.stopDictation(
            isRequested: coordinator.isDictationRequested,
            isRecording: speechManager.isRecording,
            isStarting: speechManager.isStarting,
            onRequestEnded: {
                coordinator.isDictationRequested = false
            }
        )
    }
}
