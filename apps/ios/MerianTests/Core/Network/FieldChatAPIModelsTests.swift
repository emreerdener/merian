import Foundation
import Testing

@testable import Merian

@MainActor
struct FieldChatAPIModelsTests {
    @Test func explorePostRequestUsesPostIdentifierContract() throws {
        let body = ExplorePostChatRequestBody(
            action: "send",
            postId: "post-123",
            messageText: "What habitat does it prefer?",
            clientMessageId: "message-123",
            messageId: nil,
            feedbackRating: nil,
            feedbackNote: nil
        )
        let data = try JSONEncoder().encode(body)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["post_id"] as? String == "post-123")
        #expect(json["scan_id"] == nil)
    }

    @Test func speciesDictionaryRequestUsesSpeciesIdentifierContract() throws {
        let body = SpeciesDictionaryChatRequestBody(
            action: "send",
            speciesId: "019fb718-6c44-77ee-985a-4883bfd3d2df",
            messageText: "How does this species differ from its lookalikes?",
            clientMessageId: "019fb718-7220-78f5-afbd-0732585afab3",
            messageId: nil,
            feedbackRating: nil,
            feedbackNote: nil
        )
        let data = try JSONEncoder().encode(body)
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(
            json["species_id"] as? String ==
                "019fb718-6c44-77ee-985a-4883bfd3d2df"
        )
        #expect(json["post_id"] == nil)
        #expect(json["scan_id"] == nil)
    }

    @Test func testInsightChatDecodesSnakeCasePayloadAndDates() throws {
        let json = """
        {
          "data": {
            "conversation_id": "conversation_1",
            "messages": [
              {
                "id": "message_1",
                "conversation_id": "conversation_1",
                "scan_id": "scan_1",
                "role": "assistant",
                "text": "Compare the wing veins.",
                "client_message_id": null,
                "model": "gemini-2.5-flash",
                "is_refusal": false,
                "refusal_reason": null,
                "created_at": "2026-06-26T12:34:56.123Z"
              }
            ],
            "limits": {
              "max_user_message_chars": 600,
              "max_messages_per_conversation": 30,
              "daily_send_limit": 20,
              "sends_remaining_today": 19
            }
          }
        }
        """
        let data = Data(json.utf8)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = DateUtilities.iso8601FractionalFormatter.date(from: value)
                ?? DateUtilities.iso8601Formatter.date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date")
            }
            return date
        }

        let response = try decoder.decode(InsightChatEnvelope.self, from: data).data

        #expect(response.conversationId == "conversation_1")
        #expect(response.messages.first?.role == .assistant)
        #expect(response.messages.first?.text == "Compare the wing veins.")
        #expect(response.limits.sendsRemainingToday == 19)
    }

    @Test func testFeedbackAndSummaryResponsesDecode() throws {
        let feedbackJson = """
        {
          "data": {
            "ok": true,
            "message_id": "message_1",
            "rating": "wrong"
          }
        }
        """
        let feedback = try JSONDecoder().decode(
            InsightChatFeedbackEnvelope.self,
            from: Data(feedbackJson.utf8)
        ).data
        #expect(feedback.ok)
        #expect(feedback.messageId == "message_1")
        #expect(feedback.rating == .wrong)

        let featureFeedbackJson = """
        {
          "data": {
            "ok": true,
            "id": "feature_feedback_1",
            "sentiment": "positive"
          }
        }
        """
        let featureFeedback = try JSONDecoder().decode(
            InsightChatFeatureFeedbackEnvelope.self,
            from: Data(featureFeedbackJson.utf8)
        ).data
        #expect(featureFeedback.ok)
        #expect(featureFeedback.id == "feature_feedback_1")
        #expect(featureFeedback.sentiment == .positive)

        let summaryJson = """
        {
          "data": {
            "summary_text": "Observed near a wet meadow."
          }
        }
        """
        let summary = try JSONDecoder().decode(
            InsightChatSummaryEnvelope.self,
            from: Data(summaryJson.utf8)
        ).data
        #expect(summary.summaryText == "Observed near a wet meadow.")
    }

    @Test func testPromptSuggestionResponseDecodes() throws {
        let json = """
        {
          "data": {
            "conversation_id": "conversation_1",
            "prompts": [
              {
                "text": "Which leaf trait should I check?",
                "category": "evidence"
              },
              {
                "text": "Does this habitat fit?",
                "category": "habitat"
              },
              {
                "text": "What lookalike is closest?",
                "category": "lookalike_compare"
              }
            ]
          }
        }
        """

        let response = try JSONDecoder().decode(
            InsightChatPromptSuggestionsEnvelope.self,
            from: Data(json.utf8)
        ).data

        #expect(response.conversationId == "conversation_1")
        #expect(response.prompts.count == 3)
        #expect(response.prompts[0].text == "Which leaf trait should I check?")
        #expect(response.prompts[0].category == "evidence")
    }

}
