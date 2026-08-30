import Foundation
import Observation

/// State owner for the Describe identification interview.
@MainActor
@Observable
final class DescribePromptViewModel {
    var activeQuestionIndex = 0
    var interactedQuestionIndices: Set<Int> = []
    var activeSubjectId: String?
    var activeQuestions = guidedQuestions

    private var promptFlow: DescribePromptFlow = .standard
    private static let reanalysisQuestion = GuidedQuestion(
        prompt: DescribePromptCopy.reanalysisHeading,
        tags: []
    )

    var isFunnelActive: Bool { activeSubjectId != nil }
    var isReanalysisFlow: Bool { promptFlow.isReanalysis }

    var currentPrompt: String {
        displayPrompt(at: activeQuestionIndex)
    }

    var inputPlaceholder: String {
        promptFlow.inputPlaceholder
    }

    func displayPrompt(at index: Int) -> String {
        guard activeQuestions.indices.contains(index) else { return "" }
        if promptFlow.isReanalysis && index == 0 {
            return DescribePromptCopy.reanalysisHeading
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
        switch promptFlow {
        case .standard:
            let generalTelemetry = [
                guidedQuestions[1],
                guidedQuestions[2],
                guidedQuestions.last!
            ]
            activeQuestions = [guidedQuestions[0]] + funnel + generalTelemetry
            activeQuestionIndex = 1
        case .reanalysis:
            activeQuestions = [Self.reanalysisQuestion]
            activeQuestionIndex = 0
        }
        interactedQuestionIndices = []
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
        switch promptFlow {
        case .standard:
            activeQuestions = guidedQuestions
        case .reanalysis:
            activeQuestions = [Self.reanalysisQuestion]
        }
        interactedQuestionIndices = []
        activeQuestionIndex = 0
    }

    func resetFunnel() {
        switch promptFlow {
        case .standard:
            activeSubjectId = nil
            activeQuestions = guidedQuestions
        case .reanalysis(let subjectId):
            if let subjectId, subjectFunnels[subjectId] != nil {
                activeSubjectId = subjectId
            } else {
                activeSubjectId = nil
            }
            activeQuestions = [Self.reanalysisQuestion]
        }
        interactedQuestionIndices = []
        activeQuestionIndex = 0
    }

    func advanceQuestion() {
        guard !activeQuestions.isEmpty else { return }
        activeQuestionIndex = (activeQuestionIndex + 1) % activeQuestions.count
    }

    func moveToPreviousQuestion() {
        guard !activeQuestions.isEmpty else { return }
        activeQuestionIndex = (
            activeQuestionIndex - 1 + activeQuestions.count
        ) % activeQuestions.count
    }

    func applySubjectSelection(for tag: GuidedQuestion.Tag) {
        guard activeQuestionIndex == 0 else { return }
        if subjectFunnels[tag.tagId] != nil {
            resetFunnel()
            activateFunnel(for: tag.tagId)
        } else if isFunnelActive {
            resetFunnel()
        }
    }

    private var insightTelemetryQuestions: [GuidedQuestion] {
        [guidedQuestions[1], guidedQuestions[2], guidedQuestions.last!]
    }
}
