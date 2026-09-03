import Foundation
import Testing

@testable import Merian

@Suite("Field Chat Action Endpoints")
@MainActor
struct FieldChatActionEndpointTests {
    @Test func testFieldChatFeedbackRequiresConfirmedMatchingResponse() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let scanID = "019fab51-2c31-7468-a020-541c8baa73f1"
        let postID = "019fab51-2f96-78c6-9646-d815258c5cd4"
        let messageID = "019fab51-325f-7f42-8124-7eb39b714413"
        let otherMessageID = "019fab51-34d9-7bd3-8b00-c3ff3487bf47"
        let responseURL = try #require(URL(string: "https://example.com"))
        let response = try #require(
            HTTPURLResponse(
                url: responseURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )

        func feedbackResponse(
            subjectID: String,
            ok: Bool,
            responseMessageID: String,
            rating: String
        ) -> Data {
            Data(
                """
                {
                  "data": {
                    "ok": \(ok ? "true" : "false"),
                    "subject_id": "\(subjectID)",
                    "message_id": "\(responseMessageID)",
                    "rating": "\(rating)"
                  }
                }
                """.utf8
            )
        }

        fixture.transport.register(path: "/insight-chat") { _ in
            (
                response,
                feedbackResponse(
                    subjectID: scanID,
                    ok: true,
                    responseMessageID: messageID,
                    rating: "wrong"
                )
            )
        }
        let validFeedback = try await fixture.client
            .submitInsightChatFeedback(
                scanId: scanID,
                messageId: messageID,
                rating: .wrong
            )
        #expect(validFeedback.ok)
        #expect(validFeedback.messageId == messageID)
        #expect(validFeedback.rating == .wrong)

        fixture.transport.register(path: "/explore-post-chat") { _ in
            (
                response,
                feedbackResponse(
                    subjectID: postID,
                    ok: true,
                    responseMessageID: messageID,
                    rating: "wrong"
                )
            )
        }
        let validExploreFeedback = try await fixture.client
            .submitExplorePostChatFeedback(
                postId: postID,
                messageId: messageID,
                rating: .wrong
            )
        #expect(validExploreFeedback.subjectId == postID)

        let invalidFeedbackResponses = [
            feedbackResponse(
                subjectID: scanID,
                ok: false,
                responseMessageID: messageID,
                rating: "wrong"
            ),
            feedbackResponse(
                subjectID: scanID,
                ok: true,
                responseMessageID: otherMessageID,
                rating: "wrong"
            ),
            feedbackResponse(
                subjectID: scanID,
                ok: true,
                responseMessageID: messageID,
                rating: "helpful"
            ),
            feedbackResponse(
                subjectID: scanID,
                ok: true,
                responseMessageID: messageID,
                rating: "future-rating"
            ),
            feedbackResponse(
                subjectID: postID,
                ok: true,
                responseMessageID: messageID,
                rating: "wrong"
            )
        ]
        for invalidResponse in invalidFeedbackResponses {
            fixture.transport.register(path: "/insight-chat") { _ in
                (response, invalidResponse)
            }
            await #expect(throws: MerianError.invalidResponse) {
                try await fixture.client
                    .submitInsightChatFeedback(
                        scanId: scanID,
                        messageId: messageID,
                        rating: .wrong
                    )
            }
        }

        fixture.transport.register(path: "/explore-post-chat") { _ in
            (
                response,
                feedbackResponse(
                    subjectID: postID,
                    ok: false,
                    responseMessageID: messageID,
                    rating: "wrong"
                )
            )
        }
        await #expect(throws: MerianError.invalidResponse) {
            try await fixture.client
                .submitExplorePostChatFeedback(
                    postId: postID,
                    messageId: messageID,
                    rating: .wrong
                )
        }
    }

    @Test func testFieldChatFeatureFeedbackAndSummaryRequireSafeSuccess() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let scanID = "019fab54-78c1-7b64-b982-e27c68caf098"
        let feedbackID = "019fab54-7bb3-7db5-8ac5-76e6ace87a93"
        let responseURL = try #require(URL(string: "https://example.com"))
        let response = try #require(
            HTTPURLResponse(
                url: responseURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )

        func featureFeedbackResponse(
            subjectID: String,
            ok: Bool,
            responseID: String,
            sentiment: String?
        ) -> Data {
            let sentimentJSON = sentiment.map { "\"\($0)\"" } ?? "null"
            return Data(
                """
                {
                  "data": {
                    "ok": \(ok ? "true" : "false"),
                    "subject_id": "\(subjectID)",
                    "id": "\(responseID)",
                    "sentiment": \(sentimentJSON)
                  }
                }
                """.utf8
            )
        }

        fixture.transport.register(path: "/insight-chat") { _ in
            (
                response,
                featureFeedbackResponse(
                    subjectID: scanID,
                    ok: true,
                    responseID: feedbackID,
                    sentiment: "positive"
                )
            )
        }
        let validFeatureFeedback = try await fixture.client
            .submitInsightChatFeatureFeedback(
                scanId: scanID,
                sentiment: .positive,
                note: "Useful context."
            )
        #expect(validFeatureFeedback.ok)
        #expect(validFeatureFeedback.id == feedbackID)
        #expect(validFeatureFeedback.sentiment == .positive)

        let invalidFeatureResponses = [
            featureFeedbackResponse(
                subjectID: scanID,
                ok: false,
                responseID: feedbackID,
                sentiment: "positive"
            ),
            featureFeedbackResponse(
                subjectID: scanID,
                ok: true,
                responseID: "not-a-uuid",
                sentiment: "positive"
            ),
            featureFeedbackResponse(
                subjectID: scanID,
                ok: true,
                responseID: feedbackID,
                sentiment: "negative"
            ),
            featureFeedbackResponse(
                subjectID: scanID,
                ok: true,
                responseID: feedbackID,
                sentiment: "future-sentiment"
            ),
            featureFeedbackResponse(
                subjectID: "019fab54-7e92-7a80-9f31-6d894c671042",
                ok: true,
                responseID: feedbackID,
                sentiment: "positive"
            )
        ]
        for invalidResponse in invalidFeatureResponses {
            fixture.transport.register(path: "/insight-chat") { _ in
                (response, invalidResponse)
            }
            await #expect(throws: MerianError.invalidResponse) {
                try await fixture.client
                    .submitInsightChatFeatureFeedback(
                        scanId: scanID,
                        sentiment: .positive,
                        note: "Useful context."
                    )
            }
        }

        let validSummary = Data(
            """
            {
              "data": {
                "subject_id": "\(scanID)",
                "summary_text": "The discussion compared two wing traits."
              }
            }
            """.utf8
        )
        fixture.transport.register(path: "/insight-chat") { _ in
            (response, validSummary)
        }
        let summary = try await fixture.client
            .summarizeInsightChatForFieldNotes(scanId: scanID)
        #expect(summary.summaryText == "The discussion compared two wing traits.")

        let invalidSummaries = [
            Data(
                #"{"data":{"subject_id":"\#(scanID)","summary_text":"   "}}"#
                    .utf8
            ),
            Data(
                """
                {
                  "data": {
                    "subject_id": "\(scanID)",
                    "summary_text": "Observation 46b35079-75a1-4e47-bfd3-0414c2fdda00 leaked an internal identifier."
                  }
                }
                """.utf8
            ),
            Data(
                """
                {
                  "data": {
                    "subject_id": "\(scanID)",
                    "summary_text": "Observation 019fab61-1e83-7e64-90e7-ef275922fa7e leaked a current UUIDv7 identifier."
                  }
                }
                """.utf8
            ),
            Data(#"{"data":{}}"#.utf8),
            Data(
                """
                {
                  "data": {
                    "subject_id": "019fab54-7e92-7a80-9f31-6d894c671042",
                    "summary_text": "This belongs to another observation."
                  }
                }
                """.utf8
            )
        ]
        for invalidResponse in invalidSummaries {
            fixture.transport.register(path: "/insight-chat") { _ in
                (response, invalidResponse)
            }
            await #expect(throws: MerianError.invalidResponse) {
                try await fixture.client
                    .summarizeInsightChatForFieldNotes(scanId: scanID)
            }
        }
    }

    @Test func testFieldChatPromptSuggestionsRequireBoundedSafePayloads() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let scanID = "019fab58-f128-71bd-a96d-62795221be8a"
        let postID = "019fab58-f454-7382-884b-a35052099f74"
        let conversationID = "019fab58-f797-725f-8271-de87d99f7380"
        let responseURL = try #require(URL(string: "https://example.com"))
        let response = try #require(
            HTTPURLResponse(
                url: responseURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )

        func promptResponse(
            subjectID: String,
            conversationID: String?,
            prompts: [[String: String]]
        ) throws -> Data {
            let conversationValue: Any =
                conversationID.map { $0 as Any } ?? NSNull()
            return try JSONSerialization.data(
                withJSONObject: [
                    "data": [
                        "subject_id": subjectID,
                        "conversation_id": conversationValue,
                        "prompts": prompts
                    ]
                ]
            )
        }

        let validPrompts = try promptResponse(
            subjectID: scanID,
            conversationID: conversationID,
            prompts: [
                [
                    "text": "How does this animal forage?",
                    "category": "ecology"
                ],
                [
                    "text": "Which traits distinguish tea plants?",
                    "category": "evidence"
                ],
                [
                    "text": "What habitat does poison ivy prefer?",
                    "category": "habitat"
                ]
            ]
        )
        fixture.transport.register(path: "/insight-chat") { _ in
            (response, validPrompts)
        }
        let suggestions = try await fixture.client
            .suggestInsightChatPrompts(scanId: scanID)
        #expect(suggestions.prompts.count == 3)

        let validTaxonomyLanguage = try promptResponse(
            subjectID: scanID,
            conversationID: conversationID,
            prompts: [
                [
                    "text": "Can I treat this as a subspecies?",
                    "category": "evidence"
                ]
            ]
        )
        fixture.transport.register(path: "/insight-chat") { _ in
            (response, validTaxonomyLanguage)
        }
        let taxonomySuggestions = try await fixture.client
            .suggestInsightChatPrompts(scanId: scanID)
        #expect(taxonomySuggestions.prompts.count == 1)

        let validExplorePrompts = try promptResponse(
            subjectID: postID,
            conversationID: nil,
            prompts: [
                [
                    "text": "Which public trait matters most?",
                    "category": "evidence"
                ]
            ]
        )
        fixture.transport.register(path: "/explore-post-chat") { _ in
            (response, validExplorePrompts)
        }
        let exploreSuggestions = try await fixture.client
            .suggestExplorePostChatPrompts(postId: postID)
        #expect(exploreSuggestions.subjectId == postID)

        let invalidPromptResponses = [
            try promptResponse(
                subjectID: scanID,
                conversationID: "not-a-uuid",
                prompts: []
            ),
            try promptResponse(
                subjectID: scanID,
                conversationID: conversationID,
                prompts: [
                    ["text": "One?", "category": "generic"],
                    ["text": "Two?", "category": "generic"],
                    ["text": "Three?", "category": "generic"],
                    ["text": "Four?", "category": "generic"]
                ]
            ),
            try promptResponse(
                subjectID: scanID,
                conversationID: conversationID,
                prompts: [
                    ["text": "Which trait matters?", "category": "evidence"],
                    ["text": "Which trait matters?", "category": "evidence"]
                ]
            ),
            try promptResponse(
                subjectID: scanID,
                conversationID: conversationID,
                prompts: [
                    [
                        "text": "Can I eat this observation?",
                        "category": "generic"
                    ]
                ]
            ),
            try promptResponse(
                subjectID: scanID,
                conversationID: conversationID,
                prompts: [
                    [
                        "text": "What is the best way to kill it?",
                        "category": "generic"
                    ]
                ]
            ),
            try promptResponse(
                subjectID: scanID,
                conversationID: conversationID,
                prompts: [
                    [
                        "text": "Can I treat this rash?",
                        "category": "generic"
                    ]
                ]
            ),
            try promptResponse(
                subjectID: scanID,
                conversationID: conversationID,
                prompts: [
                    [
                        "text": "How should I harvest this observation?",
                        "category": "generic"
                    ]
                ]
            ),
            try promptResponse(
                subjectID: scanID,
                conversationID: conversationID,
                prompts: [
                    [
                        "text": "Tell me how to remove this nest.",
                        "category": "generic"
                    ]
                ]
            ),
            try promptResponse(
                subjectID: scanID,
                conversationID: conversationID,
                prompts: [
                    [
                        "text": "Which trait matters?",
                        "category": "future-category"
                    ]
                ]
            ),
            try promptResponse(
                subjectID: scanID,
                conversationID: conversationID,
                prompts: [
                    [
                        "text": String(repeating: "x", count: 121),
                        "category": "generic"
                    ]
                ]
            ),
            try promptResponse(
                subjectID: postID,
                conversationID: conversationID,
                prompts: []
            )
        ]
        for invalidResponse in invalidPromptResponses {
            fixture.transport.register(path: "/insight-chat") { _ in
                (response, invalidResponse)
            }
            await #expect(throws: MerianError.invalidResponse) {
                try await fixture.client
                    .suggestInsightChatPrompts(scanId: scanID)
            }
        }

        let unsafeExplorePrompts = try promptResponse(
            subjectID: postID,
            conversationID: nil,
            prompts: [
                [
                    "text": "Can I handle this observation?",
                    "category": "generic"
                ]
            ]
        )
        fixture.transport.register(path: "/explore-post-chat") { _ in
            (response, unsafeExplorePrompts)
        }
        await #expect(throws: MerianError.invalidResponse) {
            try await fixture.client
                .suggestExplorePostChatPrompts(postId: postID)
        }
    }
}
