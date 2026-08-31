import Foundation

struct FieldChatEndpoint {
    typealias Load = @MainActor (String) async throws -> InsightChatResponse
    typealias Send = @MainActor (String, String, String) async throws -> InsightChatResponse
    typealias Delete = @MainActor (String) async throws -> InsightChatResponse
    typealias SubmitFeedback = @MainActor (
        String,
        String,
        InsightChatFeedbackRating,
        String?
    ) async throws -> InsightChatFeedbackResponse
    typealias SubmitFeatureFeedback = @MainActor (
        String,
        InsightChatFeatureFeedbackSentiment?,
        String?
    ) async throws -> InsightChatFeatureFeedbackResponse
    typealias SummarizeNotes = @MainActor (String) async throws -> InsightChatSummaryResponse
    typealias SuggestPrompts = @MainActor (String) async throws -> InsightChatPromptSuggestionsResponse

    let source: FieldChatSource
    let load: Load
    let send: Send
    let delete: Delete
    let submitFeedback: SubmitFeedback
    let submitFeatureFeedback: SubmitFeatureFeedback?
    let summarizeNotes: SummarizeNotes?
    let suggestPrompts: SuggestPrompts
}

extension FieldChatEndpoint {
    @MainActor
    static func live(
        source: FieldChatSource,
        client: MerianNetworkClient = .shared
    ) -> Self {
        switch source {
        case .insightScan:
            FieldChatEndpoint(
                source: source,
                load: { try await client.loadInsightChat(scanId: $0) },
                send: {
                    try await client.sendInsightChatMessage(
                        scanId: $0,
                        messageText: $1,
                        clientMessageId: $2
                    )
                },
                delete: { try await client.deleteInsightChat(scanId: $0) },
                submitFeedback: {
                    try await client.submitInsightChatFeedback(
                        scanId: $0,
                        messageId: $1,
                        rating: $2,
                        note: $3
                    )
                },
                submitFeatureFeedback: {
                    try await client.submitInsightChatFeatureFeedback(
                        scanId: $0,
                        sentiment: $1,
                        note: $2
                    )
                },
                summarizeNotes: {
                    try await client.summarizeInsightChatForFieldNotes(scanId: $0)
                },
                suggestPrompts: {
                    try await client.suggestInsightChatPrompts(scanId: $0)
                }
            )
        case .explorePost:
            FieldChatEndpoint(
                source: source,
                load: { try await client.loadExplorePostChat(postId: $0) },
                send: {
                    try await client.sendExplorePostChatMessage(
                        postId: $0,
                        messageText: $1,
                        clientMessageId: $2
                    )
                },
                delete: { try await client.deleteExplorePostChat(postId: $0) },
                submitFeedback: {
                    try await client.submitExplorePostChatFeedback(
                        postId: $0,
                        messageId: $1,
                        rating: $2,
                        note: $3
                    )
                },
                submitFeatureFeedback: nil,
                summarizeNotes: nil,
                suggestPrompts: {
                    try await client.suggestExplorePostChatPrompts(postId: $0)
                }
            )
        case .speciesDictionary:
            FieldChatEndpoint(
                source: source,
                load: { try await client.loadSpeciesDictionaryChat(speciesId: $0) },
                send: {
                    try await client.sendSpeciesDictionaryChatMessage(
                        speciesId: $0,
                        messageText: $1,
                        clientMessageId: $2
                    )
                },
                delete: {
                    try await client.deleteSpeciesDictionaryChat(speciesId: $0)
                },
                submitFeedback: {
                    try await client.submitSpeciesDictionaryChatFeedback(
                        speciesId: $0,
                        messageId: $1,
                        rating: $2,
                        note: $3
                    )
                },
                submitFeatureFeedback: nil,
                summarizeNotes: nil,
                suggestPrompts: {
                    try await client.suggestSpeciesDictionaryChatPrompts(speciesId: $0)
                }
            )
        }
    }
}
