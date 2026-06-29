import Foundation

struct InsightChatEnvelope: Decodable {
    let data: InsightChatResponse
}

struct InsightChatFeedbackEnvelope: Decodable {
    let data: InsightChatFeedbackResponse
}

struct InsightChatSummaryEnvelope: Decodable {
    let data: InsightChatSummaryResponse
}

struct InsightChatPromptSuggestionsEnvelope: Decodable {
    let data: InsightChatPromptSuggestionsResponse
}

struct InsightChatResponse: Decodable, Equatable {
    let conversationId: String?
    let messages: [InsightChatMessage]
    let limits: InsightChatLimits

    private enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case messages
        case limits
    }
}

struct InsightChatLimits: Decodable, Equatable {
    let maxUserMessageCharacters: Int
    let maxMessagesPerConversation: Int
    let dailySendLimit: Int
    let sendsRemainingToday: Int

    private enum CodingKeys: String, CodingKey {
        case maxUserMessageCharacters = "max_user_message_chars"
        case maxMessagesPerConversation = "max_messages_per_conversation"
        case dailySendLimit = "daily_send_limit"
        case sendsRemainingToday = "sends_remaining_today"
    }
}

struct InsightChatFeedbackResponse: Decodable, Equatable {
    let ok: Bool
    let rating: InsightChatFeedbackRating
    let messageId: String

    private enum CodingKeys: String, CodingKey {
        case ok
        case rating
        case messageId = "message_id"
    }
}

struct InsightChatSummaryResponse: Decodable, Equatable {
    let summaryText: String

    private enum CodingKeys: String, CodingKey {
        case summaryText = "summary_text"
    }
}

struct InsightChatPromptSuggestionsResponse: Decodable, Equatable {
    let conversationId: String?
    let prompts: [InsightChatPromptSuggestion]

    private enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case prompts
    }
}

struct InsightChatPromptSuggestion: Decodable, Equatable {
    let text: String
    let category: String
}

enum InsightChatFeedbackRating: String, Codable, CaseIterable {
    case helpful
    case notHelpful = "not_helpful"
    case wrong
    case unsafe
    case other
}

struct InsightChatMessage: Identifiable, Decodable, Equatable {
    enum Role: String, Decodable {
        case user
        case assistant
    }

    let id: String
    let conversationId: String
    let scanId: String
    let role: Role
    let text: String
    let clientMessageId: String?
    let model: String?
    let isRefusal: Bool
    let refusalReason: String?
    let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case scanId = "scan_id"
        case role
        case text
        case clientMessageId = "client_message_id"
        case model
        case isRefusal = "is_refusal"
        case refusalReason = "refusal_reason"
        case createdAt = "created_at"
    }
}

struct InsightChatRequestBody: Encodable {
    let action: String
    let scanId: String
    let messageText: String?
    let clientMessageId: String?
    let messageId: String?
    let feedbackRating: InsightChatFeedbackRating?
    let feedbackNote: String?

    private enum CodingKeys: String, CodingKey {
        case action
        case scanId = "scan_id"
        case messageText = "message_text"
        case clientMessageId = "client_message_id"
        case messageId = "message_id"
        case feedbackRating = "feedback_rating"
        case feedbackNote = "feedback_note"
    }
}
