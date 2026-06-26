import Foundation
import Testing

@testable import Merian

@MainActor
struct InsightChatTests {
    @Test func testSuggestionChipsPreferCandidateThenMonthAndHazard() {
        let species = SpeciesData(
            scanId: "chat_scan",
            commonName: "Monarch",
            scientificName: "Danaus plexippus",
            insightData: InsightData(aiReasoning: "Orange wings.", hazardType: "irritant"),
            confidenceScore: 0.72,
            candidates: [
                IdentificationCandidate(
                    scientificName: "Danaus gilippus",
                    commonName: "Queen",
                    confidenceScore: 0.61
                )
            ]
        )
        let date = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 6, day: 26).date
        let chips = InsightChatViewModel.suggestionChips(for: species, timestamp: date)

        #expect(chips.count == 3)
        #expect(chips[0] == "How do I tell it apart from Queen?")
        #expect(chips[1] == "Is it typical to see this in June?")
        #expect(chips[2] == "What should I know about the hazard?")
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
        """.data(using: .utf8)!

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

        let response = try decoder.decode(InsightChatEnvelope.self, from: json).data

        #expect(response.conversationId == "conversation_1")
        #expect(response.messages.first?.role == .assistant)
        #expect(response.messages.first?.text == "Compare the wing veins.")
        #expect(response.limits.sendsRemainingToday == 19)
    }

    @Test func testDraftTextIsCappedForDuplicateSafeSendPayloads() {
        let viewModel = InsightChatViewModel()
        viewModel.setDraftText(String(repeating: "x", count: 700))

        #expect(viewModel.draftText.count == 600)
        #expect(viewModel.trimmedDraft.count == 600)
    }
}
