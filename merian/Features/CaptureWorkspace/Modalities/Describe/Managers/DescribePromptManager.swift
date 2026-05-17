import Foundation
import Observation

enum DescribePromptFlow: Equatable {
    case standard
    case reanalysis(subjectId: String?)

    var isReanalysis: Bool {
        if case .reanalysis = self { return true }
        return false
    }
}

enum DescribePromptMediaContext: Equatable {
    case none
    case photo
    case audio
    case description
    case mixed
}

/// State container for the Describe identification interview.
///
/// Stored as @Observable so that DescribeInputView re-renders directly when any
/// property changes — no parent re-render chain, no @Binding intermediary.
/// CaptureWorkspaceView owns the single instance via @State and passes it by
/// reference; mutations propagate instantly to every observing view.
@Observable final class DescribePromptManager {
    var activeQuestionIndex: Int = 0
    var interactedQuestionIndices: Set<Int> = []
    var activeSubjectId: String?
    var activeQuestions: [GuidedQuestion] = guidedQuestions

    private var promptFlow: DescribePromptFlow = .standard

    var isFunnelActive: Bool { activeSubjectId != nil }
    var isReanalysisFlow: Bool { promptFlow.isReanalysis }

    var currentPrompt: String {
        displayPrompt(at: activeQuestionIndex)
    }

    func displayPrompt(at index: Int) -> String {
        guard activeQuestions.indices.contains(index) else { return "" }
        if promptFlow.isReanalysis && index == 0 {
            return "What would you like to reanalyze?"
        }
        return activeQuestions[index].prompt
    }

    func configure(for flow: DescribePromptFlow) {
        promptFlow = flow
        resetFunnel()
    }

    func configureReanalysisFlow(subjectId: String?) {
        configure(for: .reanalysis(subjectId: subjectId))
    }

    func activateFunnel(for subjectId: String) {
        guard let funnel = subjectFunnels[subjectId] else { return }
        activeSubjectId = subjectId
        let generalTelemetry = [guidedQuestions[1], guidedQuestions[2], guidedQuestions.last!]
        activeQuestions = [guidedQuestions[0]] + funnel + generalTelemetry
        interactedQuestionIndices = []
        activeQuestionIndex = 1
    }

    func configureInsightFlow(for subjectId: String?) {
        if let subjectId, let funnel = subjectFunnels[subjectId] {
            activeSubjectId = subjectId
            activeQuestions = funnel + insightTelemetryQuestions
        } else {
            activeSubjectId = nil
            activeQuestions = Array(guidedQuestions.dropFirst())
        }
        interactedQuestionIndices = []
        activeQuestionIndex = 0
    }

    func clearSubjectSelection() {
        activeSubjectId = nil
        activeQuestions = guidedQuestions
        interactedQuestionIndices = []
        activeQuestionIndex = 0
    }

    func resetFunnel() {
        switch promptFlow {
        case .standard:
            activeSubjectId = nil
            activeQuestions = guidedQuestions
        case .reanalysis(let subjectId):
            if let subjectId, let funnel = subjectFunnels[subjectId] {
                activeSubjectId = subjectId
                activeQuestions = [guidedQuestions[0]] + funnel + insightTelemetryQuestions
            } else {
                activeSubjectId = nil
                activeQuestions = guidedQuestions
            }
        }
        interactedQuestionIndices = []
        activeQuestionIndex = 0
    }

    private var insightTelemetryQuestions: [GuidedQuestion] {
        [guidedQuestions[1], guidedQuestions[2], guidedQuestions.last!]
    }
}
