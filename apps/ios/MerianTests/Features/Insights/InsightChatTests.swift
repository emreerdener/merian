import Foundation
import Testing

@testable import Merian

@MainActor
struct InsightChatTests {
    @Test func testSuggestionChipsRankCandidateHazardAndEvidencePrompts() {
        let species = SpeciesData(
            scanId: "chat_scan",
            commonName: "Monarch",
            scientificName: "Danaus plexippus",
            insightData: InsightData(aiReasoning: "Orange wings with dark vein patterns.", hazardType: "irritant"),
            confidenceScore: 0.72,
            aiReasoning: "Orange wings with dark vein patterns.",
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
        #expect(chips[1] == "What should I know about its irritant risk?")
        #expect(chips[2] == "Which wing and pattern traits support this ID?")
    }

    @Test func testSuggestionChipsUseLookalikeWhenCandidateIsUnavailable() {
        let species = SpeciesData(
            scanId: "chat_scan",
            commonName: "Trailing Ice Plant",
            scientificName: "Lampranthus spectabilis",
            insightData: InsightData(aiReasoning: "Dense succulent leaves and pink flowers.", hazardType: "none"),
            confidenceScore: 0.82,
            similarSpecies: SimilarSpecies(entries: [
                SimilarSpeciesEntry(
                    scientificName: "Carpobrotus edulis",
                    commonName: "Hottentot Fig",
                    referenceImageUrl: nil,
                    iucnRedListStatus: nil
                )
            ]),
            aiReasoning: "Dense succulent leaves and pink flowers."
        )
        let chips = InsightChatViewModel.suggestionChips(for: species, timestamp: nil)

        #expect(chips.first == "How do I tell it apart from Hottentot Fig?")
    }

    @Test func testSuggestionChipsPreferInvasiveAndTraitPrompts() {
        let species = SpeciesData(
            scanId: "chat_scan",
            commonName: "Hottentot Fig",
            scientificName: "Carpobrotus edulis",
            insightData: InsightData(
                aiReasoning: "Fleshy leaves and pale yellow flowers support the identification.",
                hazardType: "none"
            ),
            confidenceScore: 0.91,
            isInvasive: true,
            aiReasoning: "Fleshy leaves and pale yellow flowers support the identification.",
            habitatDescription: "Coastal dunes and sandy disturbed sites."
        )
        let date = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 6, day: 26).date
        let chips = InsightChatViewModel.suggestionChips(for: species, timestamp: date)

        #expect(chips == [
            "Why is Hottentot Fig invasive here?",
            "Which leaf and flower traits support this ID?",
            "Does this habitat fit Hottentot Fig?"
        ])
    }

    @Test func testSuggestionChipsIncludeSpeciesNameInSeasonPrompt() {
        let species = SpeciesData(
            scanId: "chat_scan",
            commonName: "Monarch",
            scientificName: "Danaus plexippus",
            insightData: InsightData(aiReasoning: "The subject is visible.", hazardType: "none"),
            confidenceScore: 0.72
        )
        let date = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 6, day: 26).date
        let chips = InsightChatViewModel.suggestionChips(for: species, timestamp: date)

        #expect(chips.first == "Is Monarch typical in June?")
        #expect(chips.count == 3)
    }

    @Test func testSuggestionChipsFallbackReturnsThreePrompts() {
        let species = SpeciesData(
            scanId: "chat_scan",
            commonName: "",
            scientificName: "Danaus plexippus",
            insightData: InsightData(aiReasoning: "", hazardType: "none"),
            confidenceScore: 0.62
        )
        let chips = InsightChatViewModel.suggestionChips(for: species, timestamp: nil)

        #expect(chips.count == 3)
        #expect(chips[0].contains("Danaus plexippus"))
        #expect(chips.contains("What makes this ID uncertain?"))
    }

    @Test func testSuggestionChipsExcludesSentAndPendingMessages() {
        let species = SpeciesData(
            scanId: "chat_scan",
            commonName: "Monarch",
            scientificName: "Danaus plexippus",
            insightData: InsightData(aiReasoning: "Orange wings with dark vein patterns.", hazardType: "irritant"),
            confidenceScore: 0.72,
            aiReasoning: "Orange wings with dark vein patterns.",
            candidates: [
                IdentificationCandidate(
                    scientificName: "Danaus gilippus",
                    commonName: "Queen",
                    confidenceScore: 0.61
                )
            ]
        )
        let date = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 6, day: 26).date
        
        let viewModel = InsightChatViewModel()
        
        // 1. Initially all 3 chips should be present
        var chips = viewModel.suggestionChips(for: species, timestamp: date)
        #expect(chips.count == 3)
        #expect(chips.contains("How do I tell it apart from Queen?"))
        #expect(chips.contains("What should I know about its irritant risk?"))
        #expect(chips.contains("Which wing and pattern traits support this ID?"))
        
        // 2. Add one of the chips to messages as a user message
        viewModel.messages = [
            InsightChatMessage(
                id: "msg1",
                conversationId: "conv1",
                scanId: "chat_scan",
                role: .user,
                text: "How do I tell it apart from Queen?",
                clientMessageId: nil,
                model: nil,
                isRefusal: false,
                refusalReason: nil,
                createdAt: Date()
            )
        ]
        
        chips = viewModel.suggestionChips(for: species, timestamp: date)
        #expect(chips.count == 2)
        #expect(!chips.contains("How do I tell it apart from Queen?"))
        #expect(chips.contains("What should I know about its irritant risk?"))
        #expect(chips.contains("Which wing and pattern traits support this ID?"))
        
        // 3. Set a pending user message matching another chip
        viewModel.pendingUserMessage = PendingInsightChatMessage(
            id: "pending1",
            text: "What should I know about its irritant risk?  ",
            createdAt: Date()
        )
        
        chips = viewModel.suggestionChips(for: species, timestamp: date)
        #expect(chips.count == 1)
        #expect(!chips.contains("How do I tell it apart from Queen?"))
        #expect(!chips.contains("What should I know about its irritant risk?"))
        #expect(chips.contains("Which wing and pattern traits support this ID?"))
    }

    @Test func testAISuggestionChipsReplaceFallbackAndUseCategories() {
        let species = SpeciesData(
            scanId: "chat_scan",
            commonName: "Monarch",
            scientificName: "Danaus plexippus",
            insightData: InsightData(aiReasoning: "Orange wings with dark vein patterns.", hazardType: "none"),
            confidenceScore: 0.72
        )
        let viewModel = InsightChatViewModel()
        viewModel.suggestedPrompts = [
            InsightChatPromptSuggestion(text: "Which milkweed clues matter here?", category: "ecology"),
            InsightChatPromptSuggestion(text: "What wing detail should I check next?", category: "evidence"),
            InsightChatPromptSuggestion(text: "Could this be Queen instead?", category: "lookalike_compare")
        ]

        let chips = viewModel.suggestionChips(for: species, timestamp: nil)

        #expect(chips == [
            "Which milkweed clues matter here?",
            "What wing detail should I check next?",
            "Could this be Queen instead?"
        ])
        #expect(viewModel.category(forPrompt: "What wing detail should I check next?") == "evidence")
    }

    @Test func testAISuggestionChipsFilterSentPromptsAndFillFromFallback() {
        let species = SpeciesData(
            scanId: "chat_scan",
            commonName: "Monarch",
            scientificName: "Danaus plexippus",
            insightData: InsightData(aiReasoning: "Orange wings with dark vein patterns.", hazardType: "none"),
            confidenceScore: 0.72
        )
        let viewModel = InsightChatViewModel()
        viewModel.suggestedPrompts = [
            InsightChatPromptSuggestion(text: "Which milkweed clues matter here?", category: "ecology"),
            InsightChatPromptSuggestion(text: "What wing detail should I check next?", category: "evidence")
        ]
        viewModel.messages = [
            InsightChatMessage(
                id: "msg1",
                conversationId: "conv1",
                scanId: "chat_scan",
                role: .user,
                text: "Which milkweed clues matter here?",
                clientMessageId: nil,
                model: nil,
                isRefusal: false,
                refusalReason: nil,
                createdAt: Date()
            )
        ]

        let chips = viewModel.suggestionChips(for: species, timestamp: nil)

        #expect(chips.count == 3)
        #expect(!chips.contains("Which milkweed clues matter here?"))
        #expect(chips.first == "What wing detail should I check next?")
        #expect(chips.contains("What makes this ID uncertain?"))
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

    @Test func testDraftTextIsCappedForDuplicateSafeSendPayloads() {
        let viewModel = InsightChatViewModel()
        viewModel.setDraftText(String(repeating: "x", count: 700))

        #expect(viewModel.draftText.count == 600)
        #expect(viewModel.trimmedDraft.count == 600)
    }

    @Test func testFailedPendingMessageBlocksNewSendsUntilRecovered() {
        let viewModel = InsightChatViewModel()
        viewModel.setDraftText("Can I ask another?")
        viewModel.pendingUserMessage = PendingInsightChatMessage(
            id: "pending1",
            text: "Original failed question",
            createdAt: Date(),
            deliveryState: .failed("Chat is unavailable right now.")
        )

        #expect(!viewModel.canSend)

        viewModel.editFailedMessage()

        #expect(viewModel.pendingUserMessage == nil)
        #expect(viewModel.draftText == "Original failed question")
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

    @Test func testForbiddenChatErrorExplainsAccountOwnership() {
        let message = InsightChatViewModel.userFacingMessage(
            for: MerianError.httpError(statusCode: 403, message: #"{"error":"Forbidden"}"#)
        )

        #expect(message == "This scan belongs to another account.")
    }

    @Test func testDeterministicUnavailableErrorsHideChatEntry() {
        #expect(InsightChatViewModel.isDeterministicallyUnavailable(
            MerianError.httpError(statusCode: 403, message: #"{"error":"Forbidden"}"#)
        ))
        #expect(InsightChatViewModel.isDeterministicallyUnavailable(
            MerianError.httpError(statusCode: 404, message: #"{"code":"scan_not_ready"}"#)
        ))
        #expect(InsightChatViewModel.isDeterministicallyUnavailable(
            MerianError.httpError(statusCode: 400, message: #"{"code":"unsupported_scan"}"#)
        ))
        #expect(!InsightChatViewModel.isDeterministicallyUnavailable(
            MerianError.httpError(statusCode: 429, message: #"{"code":"daily_limit_reached"}"#)
        ))
    }

    @Test func testMarkUnavailableStoresScanScopedChatUnavailableState() {
        let viewModel = InsightChatViewModel()

        viewModel.markUnavailable(scanId: "scan_1")

        #expect(viewModel.isUnavailable(for: "scan_1"))
        #expect(!viewModel.isUnavailable(for: "scan_2"))
        #expect(viewModel.errorMessage == "Field chat isn't available for this scan.")
    }
}
