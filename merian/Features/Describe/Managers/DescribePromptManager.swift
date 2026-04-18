import Observation

/// A highly scoped state container responsible for tracking the currently
/// active guided question across the Describe interface.
///
/// Extracted as an `@Observable` class so the `DescribeInputView` and
/// the `DescribeQuestionsSheet` can easily synchronize their states
/// without complex, deeply-nested bindings.
@Observable
final class DescribePromptManager {
    var activeQuestionIndex: Int = 0
    var interactedQuestionIndices: Set<Int> = []
}
