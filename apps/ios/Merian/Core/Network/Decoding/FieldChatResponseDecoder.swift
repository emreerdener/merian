import Foundation

/// Stateless wire decoding and candidate-success validation for all Field Chat sources.
/// Networking, feature state, and recovery remain with their existing owners.
enum FieldChatResponseDecoder {
    private static let promptCategoryAllowlist: Set<String> = [
        "confidence",
        "ecology",
        "evidence",
        "field_notes",
        "generic",
        "habitat",
        "hazard",
        "invasive",
        "lookalike_compare",
        "season"
    ]
    private static let unsafePromptPatterns = [
        #"\b(?:can|could|should|may|would)\s+(?:i|we|you)\s+(?:safely\s+)?(?:eat|consume|taste|cook|bake|brew|forage|feed|kill|exterminate|trap|capture|handle|pick\s+up|relocate|collect|harvest|remove\s+(?:it|this|that|a\s+nest)|take\s+(?:it|this|that)\s+home)\b"#,
        #"\bhow\s+(?:(?:do|can|could|should|would|may)\s+(?:i|we|you)\s+|to\s+)(?:eat|consume|taste|cook|bake|brew|forage|feed|kill|exterminate|trap|capture|handle|pick\s+up|relocate|collect|harvest|remove\s+(?:it|this|that|a\s+nest)|take\s+(?:it|this|that)\s+home)\b"#,
        #"\b(?:edible|safe\s+to\s+(?:eat|consume|taste|cook|brew|feed|handle|pick\s+up|capture|relocate)|(?:can|could|should|may|would)\s+(?:this|that|it|these|those)\s+be\s+(?:eaten|consumed|tasted|cooked|brewed|fed|killed|trapped|captured|handled|relocated|collected|harvested|removed|taken\s+home))\b"#,
        #"\b(?:(?:can|could|should|may|would)\s+(?:my|our)\s+(?:dog|cat|pet|livestock)\s+(?:eat|consume|taste)|(?:what\s+happens\s+if|after)\s+(?:i|we|you|someone|a\s+person|a\s+child|my\s+(?:dog|cat|pet))\s+(?:eat|ate|consume|consumed|taste|tasted|ingest|ingested))\b"#,
        #"\b(?:(?:best|safest|proper|recommended)\s+(?:ways?|methods?)\s+to|(?:instructions?|steps?|tips?|advice|guide)\s+(?:for|on|to)|(?:tell|show)\s+me\s+how\s+to)\s+(?:eat(?:ing)?|consum(?:e|ing)|tast(?:e|ing)|cook(?:ing)?|bak(?:e|ing)|brew(?:ing)?|forag(?:e|ing)|feed(?:ing)?|treat(?:ing)?|medicat(?:e|ing)|kill(?:ing)?|exterminat(?:e|ing)|trap(?:ping)?|captur(?:e|ing)|handl(?:e|ing)|pick(?:ing)?\s+up|relocat(?:e|ing)|collect(?:ing)?|harvest(?:ing)?|remov(?:e|ing)\s+(?:it|this|that|a\s+nest)|tak(?:e|ing)\s+(?:it|this|that)\s+home)\b"#,
        #"\b(?:(?:can|could|should|may|would)\s+(?:i|we|you)\s+(?:treat|medicate|manage)\b.{0,40}\b(?:rash|bite|sting|venom|allergic\s+reaction|poisoning|exposure)|what\s+should\s+(?:i|we|you|someone|a\s+person|a\s+child)\s+do\b.{0,30}\b(?:if|after)\b.{0,30}\b(?:bitten|stung|ate|ingested|rash|allergic\s+reaction|poisoning|exposure))\b"#,
        #"\b(?:dosage|antidote|treatment\s+(?:advice|instructions?|plan)|medical\s+treatment|veterinary\s+treatment|medicine\s+for|pesticide\s+(?:instructions?|application|use)|apply\s+(?:a\s+)?pesticide|(?:use|apply)\s+poison|poison\s+(?:it|this|that|them)|extermination\s+instructions?)\b"#,
        #"\b(?:legal|allowed|permit(?:ted)?|permission)\b.{0,30}\b(?:collect|harvest|capture|take|remove|relocate)\b"#,
        #"\b(?:gps|coordinates?|latitude|longitude|exact\s+location|where\s+exactly)\b"#,
        #"\b(?:identify|recognize|name|who\s+is)\b.{0,30}\b(?:person|human|face)\b"#
    ]
    private static let internalUUIDPattern =
        #"\b[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\b"#
    private static let maxResponseBytes = 1_048_576
    private static let maxMessageCharacters = 4_000

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date =
                DateUtilities.iso8601FractionalFormatter.date(from: value) ??
                DateUtilities.iso8601Formatter.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO 8601 date: \(value)"
            )
        }
        return decoder
    }

    /// Treats a chat HTTP 200 as candidate evidence until every message is
    /// bound to the requested scan, post, or species and to the envelope's conversation.
    static func decodeConversation(
        _ data: Data,
        expectedSubjectId: String,
        expectedClientMessageId: String? = nil,
        expectedUserMessageText: String? = nil
    ) throws -> InsightChatResponse {
        try validateResponseSize(data)
        let response: InsightChatResponse
        do {
            response = try makeDecoder()
                .decode(InsightChatEnvelope.self, from: data)
                .data
        } catch {
            throw MerianError.invalidResponse
        }

        let expectedSubjectId = expectedSubjectId
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let conversationId = response.conversationId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let messageIds = response.messages.compactMap {
            UUID(uuidString: $0.id)
        }
        let expectedClientMessageId = expectedClientMessageId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedUserMessageText = expectedUserMessageText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let requestMessages = expectedClientMessageId.map { requestId in
            response.messages.filter { message in
                message.clientMessageId?.caseInsensitiveCompare(requestId) ==
                    .orderedSame
            }
        } ?? []
        let requestIsValid: Bool
        switch (expectedClientMessageId, expectedUserMessageText) {
        case (nil, nil):
            requestIsValid = true
        case let (requestId?, userMessageText?):
            requestIsValid =
                UUID(uuidString: requestId) != nil &&
                !userMessageText.isEmpty &&
                userMessageText.count <= 600 &&
                requestMessages.count == 2 &&
                requestMessages.filter {
                    $0.role == .user
                }.count == 1 &&
                requestMessages.filter {
                    $0.role == .assistant
                }.count == 1 &&
                requestMessages.first {
                    $0.role == .user
                }?.text == userMessageText
        default:
            requestIsValid = false
        }
        guard !expectedSubjectId.isEmpty,
              response.subjectId?.caseInsensitiveCompare(
                  expectedSubjectId
              ) == .orderedSame,
              response.limits.maxUserMessageCharacters == 600,
              response.limits.maxMessagesPerConversation == 30,
              response.limits.dailySendLimit == 20,
              response.limits.sendsRemainingToday >= 0,
              response.limits.sendsRemainingToday <=
                response.limits.dailySendLimit,
              response.messages.count <=
                response.limits.maxMessagesPerConversation,
              response.conversationId == nil ||
                (
                    response.conversationId == conversationId &&
                    conversationId?.isEmpty == false &&
                    conversationId.flatMap {
                        UUID(uuidString: $0)
                    } != nil
                ),
              response.messages.isEmpty || conversationId != nil,
              messageIds.count == response.messages.count,
              Set(messageIds).count == messageIds.count,
              response.messages.allSatisfy({ message in
                  let text = message.text
                      .trimmingCharacters(in: .whitespacesAndNewlines)
                  return message.scanId.caseInsensitiveCompare(
                      expectedSubjectId
                  ) == .orderedSame &&
                    message.conversationId.caseInsensitiveCompare(
                        conversationId ?? ""
                    ) == .orderedSame &&
                    text == message.text &&
                    !text.isEmpty &&
                    text.count <= Self.maxMessageCharacters &&
                    (
                        message.clientMessageId == nil ||
                        message.clientMessageId.flatMap {
                            UUID(uuidString: $0)
                        } != nil
                    )
              }),
              requestIsValid else {
            throw MerianError.invalidResponse
        }
        return response
    }

    private static func validateResponseSize(_ data: Data) throws {
        guard data.count <= Self.maxResponseBytes else {
            throw MerianError.invalidResponse
        }
    }

    static func decodeFeedback(
        _ data: Data,
        expectedSubjectId: String,
        expectedMessageId: String,
        expectedRating: InsightChatFeedbackRating
    ) throws -> InsightChatFeedbackResponse {
        try validateResponseSize(data)
        let response: InsightChatFeedbackResponse
        do {
            response = try JSONDecoder()
                .decode(InsightChatFeedbackEnvelope.self, from: data)
                .data
        } catch {
            throw MerianError.invalidResponse
        }
        guard response.ok,
              response.subjectId?.caseInsensitiveCompare(
                  expectedSubjectId
              ) == .orderedSame,
              UUID(uuidString: expectedMessageId) != nil,
              UUID(uuidString: response.messageId) != nil,
              response.messageId.caseInsensitiveCompare(expectedMessageId) ==
                .orderedSame,
              response.rating == expectedRating else {
            throw MerianError.invalidResponse
        }
        return response
    }

    static func decodeFeatureFeedback(
        _ data: Data,
        expectedSubjectId: String,
        expectedSentiment: InsightChatFeatureFeedbackSentiment?
    ) throws -> InsightChatFeatureFeedbackResponse {
        try validateResponseSize(data)
        let response: InsightChatFeatureFeedbackResponse
        do {
            response = try JSONDecoder()
                .decode(InsightChatFeatureFeedbackEnvelope.self, from: data)
                .data
        } catch {
            throw MerianError.invalidResponse
        }
        guard response.ok,
              response.subjectId?.caseInsensitiveCompare(
                  expectedSubjectId
              ) == .orderedSame,
              UUID(uuidString: response.id) != nil,
              response.sentiment == expectedSentiment else {
            throw MerianError.invalidResponse
        }
        return response
    }

    static func decodeSummary(
        _ data: Data,
        expectedSubjectId: String
    ) throws -> InsightChatSummaryResponse {
        try validateResponseSize(data)
        let response: InsightChatSummaryResponse
        do {
            response = try JSONDecoder()
                .decode(InsightChatSummaryEnvelope.self, from: data)
                .data
        } catch {
            throw MerianError.invalidResponse
        }
        let summaryText = response.summaryText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard response.subjectId?.caseInsensitiveCompare(
                  expectedSubjectId
              ) == .orderedSame,
              !summaryText.isEmpty,
              summaryText.count <= 4_000,
              summaryText.range(
                  of: Self.internalUUIDPattern,
                  options: [.regularExpression, .caseInsensitive]
              ) == nil else {
            throw MerianError.invalidResponse
        }
        return InsightChatSummaryResponse(
            subjectId: response.subjectId,
            summaryText: summaryText
        )
    }

    static func decodePromptSuggestions(
        _ data: Data,
        expectedSubjectId: String
    ) throws -> InsightChatPromptSuggestionsResponse {
        try validateResponseSize(data)
        let response: InsightChatPromptSuggestionsResponse
        do {
            response = try JSONDecoder()
                .decode(InsightChatPromptSuggestionsEnvelope.self, from: data)
                .data
        } catch {
            throw MerianError.invalidResponse
        }
        let conversationId = response.conversationId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var normalizedPrompts = Set<String>()
        guard response.subjectId?.caseInsensitiveCompare(
                  expectedSubjectId
              ) == .orderedSame,
              response.conversationId == nil ||
                (
                    conversationId?.isEmpty == false &&
                    conversationId.flatMap {
                        UUID(uuidString: $0)
                    } != nil
                ),
              response.prompts.count <= 3,
              response.prompts.allSatisfy({ prompt in
                  let text = prompt.text
                      .trimmingCharacters(in: .whitespacesAndNewlines)
                  let category = prompt.category
                      .trimmingCharacters(in: .whitespacesAndNewlines)
                  return text == prompt.text &&
                    !text.isEmpty &&
                    text.count <= 120 &&
                    category == prompt.category &&
                    Self.promptCategoryAllowlist.contains(
                        category
                    ) &&
                    Self.unsafePromptPatterns.allSatisfy {
                        text.range(
                            of: $0,
                            options: [
                                .regularExpression,
                                .caseInsensitive
                            ]
                        ) == nil
                    } &&
                    normalizedPrompts.insert(text.lowercased()).inserted
              }) else {
            throw MerianError.invalidResponse
        }
        return response
    }
}
