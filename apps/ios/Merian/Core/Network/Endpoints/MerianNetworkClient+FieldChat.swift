import Foundation

/// Field Chat request construction for Insight, Explore posts, and Species Dictionary.
/// The client retains private transport; feature Services retain presentation adapters.
extension MerianNetworkClient {
    // MARK: - Insight

    func loadInsightChat(scanId: String) async throws -> InsightChatResponse {
        try await insightChat(
            action: "load",
            scanId: scanId,
            messageText: nil,
            clientMessageId: nil
        )
    }

    func sendInsightChatMessage(
        scanId: String,
        messageText: String,
        clientMessageId: String
    ) async throws -> InsightChatResponse {
        try await insightChat(
            action: "send",
            scanId: scanId,
            messageText: messageText,
            clientMessageId: clientMessageId
        )
    }

    func deleteInsightChat(scanId: String) async throws -> InsightChatResponse {
        try await insightChat(
            action: "delete",
            scanId: scanId,
            messageText: nil,
            clientMessageId: nil
        )
    }

    private func insightChat(
        action: String,
        scanId: String,
        messageText: String?,
        clientMessageId: String?
    ) async throws -> InsightChatResponse {
        let body = InsightChatRequestBody(
            action: action,
            scanId: scanId,
            messageText: messageText,
            clientMessageId: clientMessageId,
            messageId: nil,
            feedbackRating: nil,
            feedbackNote: nil,
            featureFeedbackSentiment: nil
        )
        let data = try await performInsightChatRequest(
            body,
            timeoutInterval: 45.0,
            idempotencyKey: action == "send" ? clientMessageId : nil
        )
        return try FieldChatResponseDecoder.decodeConversation(
            data,
            expectedSubjectId: scanId,
            expectedClientMessageId:
                action == "send" ? clientMessageId : nil,
            expectedUserMessageText:
                action == "send" ? messageText : nil
        )
    }

    func submitInsightChatFeedback(
        scanId: String,
        messageId: String,
        rating: InsightChatFeedbackRating,
        note: String? = nil
    ) async throws -> InsightChatFeedbackResponse {
        let body = InsightChatRequestBody(
            action: "feedback",
            scanId: scanId,
            messageText: nil,
            clientMessageId: nil,
            messageId: messageId,
            feedbackRating: rating,
            feedbackNote: note,
            featureFeedbackSentiment: nil
        )
        let data = try await performInsightChatRequest(body)
        return try FieldChatResponseDecoder.decodeFeedback(
            data,
            expectedSubjectId: scanId,
            expectedMessageId: messageId,
            expectedRating: rating
        )
    }

    func submitInsightChatFeatureFeedback(
        scanId: String,
        sentiment: InsightChatFeatureFeedbackSentiment?,
        note: String?
    ) async throws -> InsightChatFeatureFeedbackResponse {
        let body = InsightChatRequestBody(
            action: "feature_feedback",
            scanId: scanId,
            messageText: nil,
            clientMessageId: nil,
            messageId: nil,
            feedbackRating: nil,
            feedbackNote: note,
            featureFeedbackSentiment: sentiment
        )
        let data = try await performInsightChatRequest(body)
        return try FieldChatResponseDecoder.decodeFeatureFeedback(
            data,
            expectedSubjectId: scanId,
            expectedSentiment: sentiment
        )
    }

    func summarizeInsightChatForFieldNotes(scanId: String) async throws -> InsightChatSummaryResponse {
        let body = InsightChatRequestBody(
            action: "summarize_notes",
            scanId: scanId,
            messageText: nil,
            clientMessageId: nil,
            messageId: nil,
            feedbackRating: nil,
            feedbackNote: nil,
            featureFeedbackSentiment: nil
        )
        let data = try await performInsightChatRequest(
            body,
            timeoutInterval: 45.0,
            idempotencyKey: UUID().uuidString.lowercased()
        )
        return try FieldChatResponseDecoder.decodeSummary(
            data,
            expectedSubjectId: scanId
        )
    }

    func suggestInsightChatPrompts(scanId: String) async throws -> InsightChatPromptSuggestionsResponse {
        let body = InsightChatRequestBody(
            action: "suggest_prompts",
            scanId: scanId,
            messageText: nil,
            clientMessageId: nil,
            messageId: nil,
            feedbackRating: nil,
            feedbackNote: nil,
            featureFeedbackSentiment: nil
        )
        let data = try await performInsightChatRequest(
            body,
            timeoutInterval: 30.0,
            idempotencyKey: UUID().uuidString.lowercased()
        )
        return try FieldChatResponseDecoder.decodePromptSuggestions(
            data,
            expectedSubjectId: scanId
        )
    }

    private func performInsightChatRequest(
        _ body: InsightChatRequestBody,
        timeoutInterval: TimeInterval = 20.0,
        idempotencyKey: String? = nil
    ) async throws -> Data {
        try await performAuthenticatedEncodedJSONPost(
            function: "insight-chat",
            body: body,
            timeoutInterval: timeoutInterval,
            idempotencyKey: idempotencyKey
        )
    }

    // MARK: - Explore Post

    func loadExplorePostChat(postId: String) async throws -> InsightChatResponse {
        try await performExplorePostChat(
            action: "load",
            postId: postId
        )
    }

    func sendExplorePostChatMessage(
        postId: String,
        messageText: String,
        clientMessageId: String
    ) async throws -> InsightChatResponse {
        try await performExplorePostChat(
            action: "send",
            postId: postId,
            messageText: messageText,
            clientMessageId: clientMessageId
        )
    }

    func deleteExplorePostChat(postId: String) async throws -> InsightChatResponse {
        try await performExplorePostChat(action: "delete", postId: postId)
    }

    func submitExplorePostChatFeedback(
        postId: String,
        messageId: String,
        rating: InsightChatFeedbackRating,
        note: String? = nil
    ) async throws -> InsightChatFeedbackResponse {
        let body = ExplorePostChatRequestBody(
            action: "feedback",
            postId: postId,
            messageText: nil,
            clientMessageId: nil,
            messageId: messageId,
            feedbackRating: rating,
            feedbackNote: note
        )
        let data = try await performExplorePostChatRequest(body)
        return try FieldChatResponseDecoder.decodeFeedback(
            data,
            expectedSubjectId: postId,
            expectedMessageId: messageId,
            expectedRating: rating
        )
    }

    func suggestExplorePostChatPrompts(postId: String) async throws -> InsightChatPromptSuggestionsResponse {
        let body = ExplorePostChatRequestBody(
            action: "suggest_prompts",
            postId: postId,
            messageText: nil,
            clientMessageId: nil,
            messageId: nil,
            feedbackRating: nil,
            feedbackNote: nil
        )
        let data = try await performExplorePostChatRequest(body, timeoutInterval: 30.0)
        return try FieldChatResponseDecoder.decodePromptSuggestions(
            data,
            expectedSubjectId: postId
        )
    }

    private func performExplorePostChat(
        action: String,
        postId: String,
        messageText: String? = nil,
        clientMessageId: String? = nil
    ) async throws -> InsightChatResponse {
        let body = ExplorePostChatRequestBody(
            action: action,
            postId: postId,
            messageText: messageText,
            clientMessageId: clientMessageId,
            messageId: nil,
            feedbackRating: nil,
            feedbackNote: nil
        )
        let data = try await performExplorePostChatRequest(
            body,
            idempotencyKey: action == "send" ? clientMessageId : nil
        )
        return try FieldChatResponseDecoder.decodeConversation(
            data,
            expectedSubjectId: postId,
            expectedClientMessageId:
                action == "send" ? clientMessageId : nil,
            expectedUserMessageText:
                action == "send" ? messageText : nil
        )
    }

    private func performExplorePostChatRequest(
        _ body: ExplorePostChatRequestBody,
        timeoutInterval: TimeInterval = 20.0,
        idempotencyKey: String? = nil
    ) async throws -> Data {
        try await performAuthenticatedEncodedJSONPost(
            function: "explore-post-chat",
            body: body,
            timeoutInterval: timeoutInterval,
            idempotencyKey: idempotencyKey
        )
    }

    // MARK: - Species Dictionary

    func loadSpeciesDictionaryChat(speciesId: String) async throws -> InsightChatResponse {
        try await performSpeciesDictionaryChat(
            action: "load",
            speciesId: speciesId
        )
    }

    func sendSpeciesDictionaryChatMessage(
        speciesId: String,
        messageText: String,
        clientMessageId: String
    ) async throws -> InsightChatResponse {
        try await performSpeciesDictionaryChat(
            action: "send",
            speciesId: speciesId,
            messageText: messageText,
            clientMessageId: clientMessageId
        )
    }

    func deleteSpeciesDictionaryChat(speciesId: String) async throws -> InsightChatResponse {
        try await performSpeciesDictionaryChat(
            action: "delete",
            speciesId: speciesId
        )
    }

    func submitSpeciesDictionaryChatFeedback(
        speciesId: String,
        messageId: String,
        rating: InsightChatFeedbackRating,
        note: String? = nil
    ) async throws -> InsightChatFeedbackResponse {
        let body = SpeciesDictionaryChatRequestBody(
            action: "feedback",
            speciesId: speciesId,
            messageText: nil,
            clientMessageId: nil,
            messageId: messageId,
            feedbackRating: rating,
            feedbackNote: note
        )
        let data = try await performSpeciesDictionaryChatRequest(body)
        return try FieldChatResponseDecoder.decodeFeedback(
            data,
            expectedSubjectId: speciesId,
            expectedMessageId: messageId,
            expectedRating: rating
        )
    }

    func suggestSpeciesDictionaryChatPrompts(
        speciesId: String
    ) async throws -> InsightChatPromptSuggestionsResponse {
        let body = SpeciesDictionaryChatRequestBody(
            action: "suggest_prompts",
            speciesId: speciesId,
            messageText: nil,
            clientMessageId: nil,
            messageId: nil,
            feedbackRating: nil,
            feedbackNote: nil
        )
        let data = try await performSpeciesDictionaryChatRequest(
            body,
            timeoutInterval: 30.0
        )
        return try FieldChatResponseDecoder.decodePromptSuggestions(
            data,
            expectedSubjectId: speciesId
        )
    }

    private func performSpeciesDictionaryChat(
        action: String,
        speciesId: String,
        messageText: String? = nil,
        clientMessageId: String? = nil
    ) async throws -> InsightChatResponse {
        let body = SpeciesDictionaryChatRequestBody(
            action: action,
            speciesId: speciesId,
            messageText: messageText,
            clientMessageId: clientMessageId,
            messageId: nil,
            feedbackRating: nil,
            feedbackNote: nil
        )
        let data = try await performSpeciesDictionaryChatRequest(
            body,
            timeoutInterval: action == "send" ? 45.0 : 20.0,
            idempotencyKey: action == "send" ? clientMessageId : nil
        )
        return try FieldChatResponseDecoder.decodeConversation(
            data,
            expectedSubjectId: speciesId,
            expectedClientMessageId:
                action == "send" ? clientMessageId : nil,
            expectedUserMessageText:
                action == "send" ? messageText : nil
        )
    }

    private func performSpeciesDictionaryChatRequest(
        _ body: SpeciesDictionaryChatRequestBody,
        timeoutInterval: TimeInterval = 20.0,
        idempotencyKey: String? = nil
    ) async throws -> Data {
        try await performAuthenticatedEncodedJSONPost(
            function: "species-dictionary-chat",
            body: body,
            timeoutInterval: timeoutInterval,
            idempotencyKey: idempotencyKey
        )
    }
}
