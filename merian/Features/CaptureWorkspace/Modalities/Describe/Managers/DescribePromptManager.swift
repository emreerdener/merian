import Foundation
import Observation

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

    var isFunnelActive: Bool { activeSubjectId != nil }

    func activateFunnel(for subjectId: String) {
        guard let funnel = subjectFunnels[subjectId] else { return }
        activeSubjectId = subjectId
        let generalTelemetry = [guidedQuestions[1], guidedQuestions[2], guidedQuestions.last!]
        activeQuestions = [guidedQuestions[0]] + funnel + generalTelemetry
        interactedQuestionIndices = []
        activeQuestionIndex = 1
    }

    func resetFunnel() {
        activeSubjectId = nil
        activeQuestions = guidedQuestions
        interactedQuestionIndices = []
        activeQuestionIndex = 0
    }
}
