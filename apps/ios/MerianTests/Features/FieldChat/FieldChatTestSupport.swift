import Foundation

@testable import Merian

@MainActor
enum FieldChatTestSupport {
    static let defaultLimits = InsightChatLimits(
        maxUserMessageCharacters: 600,
        maxMessagesPerConversation: 30,
        dailySendLimit: 20,
        sendsRemainingToday: 20
    )

    static func response(
        subjectId: String,
        messages: [InsightChatMessage] = [],
        sendsRemainingToday: Int = 20
    ) -> InsightChatResponse {
        InsightChatResponse(
            subjectId: subjectId,
            conversationId: messages.isEmpty ? nil : "conversation",
            messages: messages,
            limits: InsightChatLimits(
                maxUserMessageCharacters: 600,
                maxMessagesPerConversation: 30,
                dailySendLimit: 20,
                sendsRemainingToday: sendsRemainingToday
            )
        )
    }

    static func endpoint(
        source: FieldChatSource = .insightScan,
        load: FieldChatEndpoint.Load? = nil,
        send: FieldChatEndpoint.Send? = nil,
        delete: FieldChatEndpoint.Delete? = nil,
        submitFeedback: FieldChatEndpoint.SubmitFeedback? = nil,
        submitFeatureFeedback: FieldChatEndpoint.SubmitFeatureFeedback? = nil,
        summarizeNotes: FieldChatEndpoint.SummarizeNotes? = nil,
        suggestPrompts: FieldChatEndpoint.SuggestPrompts? = nil
    ) -> FieldChatEndpoint {
        let resolvedLoad: FieldChatEndpoint.Load
        if let load {
            resolvedLoad = load
        } else {
            resolvedLoad = { subjectId in
                response(subjectId: subjectId)
            }
        }

        let resolvedSend: FieldChatEndpoint.Send
        if let send {
            resolvedSend = send
        } else {
            resolvedSend = { subjectId, _, _ in
                response(subjectId: subjectId)
            }
        }

        let resolvedDelete: FieldChatEndpoint.Delete
        if let delete {
            resolvedDelete = delete
        } else {
            resolvedDelete = { subjectId in
                response(subjectId: subjectId)
            }
        }

        let resolvedFeedback: FieldChatEndpoint.SubmitFeedback
        if let submitFeedback {
            resolvedFeedback = submitFeedback
        } else {
            resolvedFeedback = { subjectId, messageId, rating, _ in
                InsightChatFeedbackResponse(
                    ok: true,
                    subjectId: subjectId,
                    rating: rating,
                    messageId: messageId
                )
            }
        }

        let resolvedFeatureFeedback: FieldChatEndpoint.SubmitFeatureFeedback?
        if let submitFeatureFeedback {
            resolvedFeatureFeedback = submitFeatureFeedback
        } else if source == .insightScan {
            resolvedFeatureFeedback = { subjectId, sentiment, _ in
                InsightChatFeatureFeedbackResponse(
                    ok: true,
                    subjectId: subjectId,
                    id: "feature-feedback",
                    sentiment: sentiment
                )
            }
        } else {
            resolvedFeatureFeedback = nil
        }

        let resolvedSummary: FieldChatEndpoint.SummarizeNotes?
        if let summarizeNotes {
            resolvedSummary = summarizeNotes
        } else if source == .insightScan {
            resolvedSummary = {
                InsightChatSummaryResponse(
                    subjectId: $0,
                    summaryText: "Summary"
                )
            }
        } else {
            resolvedSummary = nil
        }

        let resolvedPrompts: FieldChatEndpoint.SuggestPrompts
        if let suggestPrompts {
            resolvedPrompts = suggestPrompts
        } else {
            resolvedPrompts = { subjectId in
                InsightChatPromptSuggestionsResponse(
                    subjectId: subjectId,
                    conversationId: nil,
                    prompts: []
                )
            }
        }

        return FieldChatEndpoint(
            source: source,
            load: resolvedLoad,
            send: resolvedSend,
            delete: resolvedDelete,
            submitFeedback: resolvedFeedback,
            submitFeatureFeedback: resolvedFeatureFeedback,
            summarizeNotes: resolvedSummary,
            suggestPrompts: resolvedPrompts
        )
    }

    static func dependencies(
        endpoint: FieldChatEndpoint,
        checkOwnedScanStatus: @escaping FieldChatDependencies.CheckOwnedScanStatus = { _ in
            "found"
        },
        feedback: @escaping FieldChatDependencies.Feedback = { _ in },
        trackAction: @escaping FieldChatDependencies.TrackAction = { _, _ in },
        copyText: @escaping FieldChatDependencies.CopyText = { _ in },
        now: @escaping FieldChatDependencies.Now = {
            Date(timeIntervalSince1970: 1_700_000_000)
        },
        makeRequestId: @escaping FieldChatDependencies.MakeRequestId = {
            "019facf5-778f-7602-9b75-31101508b2b7"
        }
    ) -> FieldChatDependencies {
        FieldChatDependencies(
            endpoint: endpoint,
            checkOwnedScanStatus: checkOwnedScanStatus,
            feedback: feedback,
            trackAction: trackAction,
            copyText: copyText,
            now: now,
            makeRequestId: makeRequestId
        )
    }
}
