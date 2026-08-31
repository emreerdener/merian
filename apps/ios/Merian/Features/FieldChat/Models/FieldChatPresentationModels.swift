enum InsightChatFieldNotesAppendKind {
    case summary
}

enum InsightChatReplyAction: String, CaseIterable {
    case copyAnswer = "copy_answer"

    func perform(
        messageText: String,
        writeToPasteboard: (String) -> Void
    ) {
        switch self {
        case .copyAnswer:
            // InsightChatAnswerControls owns the visible in-sheet acknowledgement.
            writeToPasteboard(messageText)
        }
    }
}

enum FieldChatFeedbackEffect: Equatable {
    case selection
    case medium
    case success
    case error
}

struct FieldChatActionTelemetry {
    let action: String
    let subjectId: String
    let messageId: String
    let isRefusal: Bool
    let hasLookalikes: Bool
    let promptCategory: String?

    init(
        action: String,
        subjectId: String,
        messageId: String = "",
        isRefusal: Bool = false,
        hasLookalikes: Bool,
        promptCategory: String? = nil
    ) {
        self.action = action
        self.subjectId = subjectId
        self.messageId = messageId
        self.isRefusal = isRefusal
        self.hasLookalikes = hasLookalikes
        self.promptCategory = promptCategory
    }
}
