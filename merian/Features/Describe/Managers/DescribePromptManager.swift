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
}
