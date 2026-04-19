import Observation

/// A highly scoped state container responsible for tracking the currently
/// active guided question across the Describe interface.
///
/// Extracted as an `@Observable` class so the `DescribeInputView` and
/// the `DescribeQuestionsSheet` can easily synchronize their states
/// without complex, deeply-nested bindings.
@Observable
final class DescribePromptManager {
    /// The index of the currently active guided question being displayed.
    var activeQuestionIndex: Int = 0
    
    /// Tracks which questions the user has already engaged with via Quick Tags.
    /// Used locally to orchestrate one-time auto-progression to the next prompt.
    var interactedQuestionIndices: Set<Int> = []
    
    // MARK: - Funnel State
    
    var activeSubjectId: String?
    var activeQuestions: [GuidedQuestion] = guidedQuestions
    
    var isFunnelActive: Bool { 
        activeSubjectId != nil 
    }
    
    func activateFunnel(for subjectId: String) {
        guard let funnel = subjectFunnels[subjectId] else { return }
        activeSubjectId = subjectId
        // Append general weather/location telemetry and the final open-ended prompt
        let generalTelemetry = [guidedQuestions[1], guidedQuestions[2], guidedQuestions.last!]
        activeQuestions = [guidedQuestions[0]] + funnel + generalTelemetry
        interactedQuestionIndices = []
        activeQuestionIndex = 1                            // advance past the subject question
    }
    
    func resetFunnel() {
        activeSubjectId = nil
        activeQuestions = guidedQuestions
        interactedQuestionIndices = []
        activeQuestionIndex = 0
    }
}
