import Foundation

/// Synthetic wire fixtures, independent of the production Codable encoders.
enum FieldChatNetworkFixtures {
    static let subjectID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    static let requestID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    static let conversationID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    static let userMessageID = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
    static let assistantMessageID = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
    static let feedbackID = "ffffffff-ffff-4fff-8fff-ffffffffffff"
    static let question = "What distinguishes this species?"
    static let answer = "Compare the saved structural details."

    static var limits: [String: Any] {
        ["max_user_message_chars": 600, "max_messages_per_conversation": 30,
         "daily_send_limit": 20, "sends_remaining_today": 19]
    }

    static func conversation(
        subjectID: String = subjectID,
        question: String = question,
        requestID: String = requestID
    ) -> [String: Any] {
        ["subject_id": subjectID, "conversation_id": conversationID,
         "messages": [
            message(id: userMessageID, subjectID: subjectID, role: "user", text: question, requestID: requestID),
            message(id: assistantMessageID, subjectID: subjectID, role: "assistant", text: answer, requestID: requestID)
         ], "limits": limits]
    }

    static func message(
        id: String = assistantMessageID,
        subjectID: String = subjectID,
        role: String = "assistant",
        text: String = answer,
        requestID: String? = requestID
    ) -> [String: Any] {
        ["id": id, "conversation_id": conversationID, "scan_id": subjectID,
         "role": role, "text": text, "client_message_id": requestID ?? NSNull(),
         "model": role == "assistant" ? "test-model" : NSNull(),
         "is_refusal": false, "refusal_reason": NSNull(),
         "created_at": role == "assistant" ? "2026-09-01T12:00:01Z" : "2026-09-01T12:00:00.000Z"]
    }

    static func emptyConversation(subjectID: String = subjectID) -> [String: Any] {
        ["subject_id": subjectID, "conversation_id": NSNull(), "messages": [], "limits": limits]
    }

    static func feedback(
        subjectID: String = subjectID,
        messageID: String = assistantMessageID,
        rating: String = "helpful"
    ) -> [String: Any] {
        ["ok": true, "subject_id": subjectID, "message_id": messageID, "rating": rating]
    }

    static func featureFeedback(sentiment: String? = "positive") -> [String: Any] {
        ["ok": true, "subject_id": subjectID, "id": feedbackID, "sentiment": sentiment ?? NSNull()]
    }

    static var summary: [String: Any] {
        ["subject_id": subjectID, "summary_text": "  Compared the saved structural details.  "]
    }

    static var prompts: [String: Any] {
        ["subject_id": subjectID, "conversation_id": conversationID, "prompts": [
            ["text": "What traits distinguish this species?", "category": "evidence"],
            ["text": "What habitat does this species prefer?", "category": "habitat"]
        ]]
    }

    static func envelope(_ data: [String: Any]) -> String { json(["data": data]) }

    static func json(_ object: [String: Any]) -> String {
        do {
            return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        } catch {
            preconditionFailure("Invalid synthetic Field Chat JSON fixture")
        }
    }
}
