import Foundation
import Observation

enum DescribePromptFlow: Equatable {
    case standard
    case reanalysis(subjectId: String?)

    var isReanalysis: Bool {
        if case .reanalysis = self { return true }
        return false
    }

    var inputPlaceholder: String {
        switch self {
        case .standard:
            return DescribePromptCopy.standardInputPlaceholder
        case .reanalysis:
            return DescribePromptCopy.reanalysisInputPlaceholder
        }
    }
}

enum DescribePromptMediaContext: Equatable {
    case none
    case photo
    case audio
    case description
    case mixed
}

enum DescribePromptCopy {
    static let standardInputPlaceholder = "e.g., A bright green beetle with gold stripes resting on an oak leaf..."
    static let reanalysisHeading = "What would you like to reanalyze?"
    static let reanalysisSubheading = "Tell the AI what to reconsider: the likely species, visible traits, behavior, habitat, or anything the first result missed."
    static let reanalysisInputPlaceholder = "e.g., Recheck this as a houseplant. Focus on leaf shape, growth habit, variegation, and the potting environment."
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
            let generalTelemetry = [guidedQuestions[1], guidedQuestions[2], guidedQuestions.last!]
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
                activeQuestions = [Self.reanalysisQuestion]
            } else {
                activeSubjectId = nil
                activeQuestions = [Self.reanalysisQuestion]
            }
        }
        interactedQuestionIndices = []
        activeQuestionIndex = 0
    }

    private var insightTelemetryQuestions: [GuidedQuestion] {
        [guidedQuestions[1], guidedQuestions[2], guidedQuestions.last!]
    }
}
