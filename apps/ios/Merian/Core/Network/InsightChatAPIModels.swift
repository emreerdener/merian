import Foundation

struct InsightChatEnvelope: Decodable {
    let data: InsightChatResponse
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

    private enum CodingKeys: String, CodingKey {
        case action
        case scanId = "scan_id"
        case messageText = "message_text"
        case clientMessageId = "client_message_id"
    }
}
