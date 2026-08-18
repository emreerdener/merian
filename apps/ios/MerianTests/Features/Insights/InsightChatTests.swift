import Foundation
import Testing

@testable import Merian

@MainActor
struct InsightChatTests {
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

    @Test func explorePostSuggestionChipsReturnThreeDistinctQuestions() {
        let viewModel = InsightChatViewModel(source: .explorePost)
        let chips = viewModel.publicPostSuggestionChips(displayName: "Monarch")

        #expect(chips.count == 3)
        #expect(Set(chips).count == 3)
        #expect(chips.allSatisfy { $0.contains("Monarch") })
    }

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
            confidenceScore: 0.62
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

    @Test func lowConfidenceSuggestionChipsReserveConfidenceCategory() {
        let species = SpeciesData(
            scanId: "chat_scan",
            commonName: "Monarch",
            scientificName: "Danaus plexippus",
            insightData: InsightData(aiReasoning: "Orange wings.", hazardType: "none"),
            confidenceScore: 0.62
        )
        let viewModel = InsightChatViewModel()
        viewModel.suggestedPrompts = [
            InsightChatPromptSuggestion(text: "Which milkweed clues matter?", category: "ecology"),
            InsightChatPromptSuggestion(text: "Which wing vein should I inspect?", category: "evidence"),
            InsightChatPromptSuggestion(text: "Is this habitat typical?", category: "habitat")
        ]

        #expect(viewModel.suggestionChips(for: species, timestamp: nil) == [
            "Which milkweed clues matter?",
            "Which wing vein should I inspect?",
            "What makes this ID uncertain?"
        ])
    }

    @Test func lowConfidenceSuggestionChipsKeepServerConfidencePrompt() {
        let species = SpeciesData(
            scanId: "chat_scan",
            commonName: "Monarch",
            scientificName: "Danaus plexippus",
            insightData: InsightData(aiReasoning: "Orange wings.", hazardType: "none"),
            confidenceScore: 0.62
        )
        let viewModel = InsightChatViewModel()
        viewModel.suggestedPrompts = [
            InsightChatPromptSuggestion(text: "Which milkweed clues matter?", category: "ecology"),
            InsightChatPromptSuggestion(text: "Why is this match uncertain?", category: "confidence"),
            InsightChatPromptSuggestion(text: "Is this habitat typical?", category: "habitat")
        ]

        #expect(viewModel.suggestionChips(for: species, timestamp: nil) == [
            "Which milkweed clues matter?",
            "Why is this match uncertain?",
            "Is this habitat typical?"
        ])
    }

    @Test func lowConfidenceSuggestionChipsDoNotCrowdOutLateServerConfidencePrompt() {
        let species = SpeciesData(
            scanId: "chat_scan",
            commonName: "Monarch",
            scientificName: "Danaus plexippus",
            insightData: InsightData(aiReasoning: "Orange wings.", hazardType: "none"),
            confidenceScore: 0.62
        )
        let viewModel = InsightChatViewModel()
        viewModel.suggestedPrompts = [
            InsightChatPromptSuggestion(text: "Which milkweed clues matter?", category: "ecology"),
            InsightChatPromptSuggestion(text: "Which wing vein should I inspect?", category: "evidence"),
            InsightChatPromptSuggestion(text: "Is this habitat typical?", category: "habitat"),
            InsightChatPromptSuggestion(text: "Why is this match uncertain?", category: "confidence")
        ]

        #expect(viewModel.suggestionChips(for: species, timestamp: nil) == [
            "Which milkweed clues matter?",
            "Which wing vein should I inspect?",
            "Why is this match uncertain?"
        ])
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

        let conversationId = "019facf5-71fc-70ca-83e4-698b55d1e260"
        let subjectId = "019facf5-74df-704b-878e-decb347ac1d0"
        let interruptedRequestId =
            "019FACF5-778F-7602-9B75-31101508B2B7"
        let interrupted = InsightChatMessage(
            id: "019facf5-7a48-7531-b258-2fa37f0d7aed",
            conversationId: conversationId,
            scanId: subjectId,
            role: .user,
            text: "Which traits support this ID?",
            clientMessageId: interruptedRequestId,
            model: nil,
            isRefusal: false,
            refusalReason: nil,
            createdAt: Date()
        )
        let recovered = InsightChatViewModel.reconcileThread([interrupted])
        #expect(recovered.messages.isEmpty)
        #expect(
            recovered.pendingMessage?.id ==
                interruptedRequestId.lowercased()
        )
        #expect(
            recovered.pendingMessage?.deliveryState ==
                .failed(InsightChatViewModel.interruptedSendMessage)
        )

        let assistant = InsightChatMessage(
            id: "019facf5-7d16-7f2e-bab0-7a31290e2a75",
            conversationId: conversationId,
            scanId: subjectId,
            role: .assistant,
            text: "The saved evidence supports two visible traits.",
            clientMessageId: interruptedRequestId.lowercased(),
            model: "gemini-2.5-flash",
            isRefusal: false,
            refusalReason: nil,
            createdAt: Date()
        )
        let duplicateAssistant = InsightChatMessage(
            id: "019facf5-7fbd-77f7-96a5-4613baf49695",
            conversationId: conversationId,
            scanId: subjectId,
            role: .assistant,
            text: "Duplicate answer",
            clientMessageId: interruptedRequestId,
            model: "gemini-2.5-flash",
            isRefusal: false,
            refusalReason: nil,
            createdAt: Date()
        )
        let orphanAssistant = InsightChatMessage(
            id: "019facf5-824a-7530-8a69-68f31ea9fd5d",
            conversationId: conversationId,
            scanId: subjectId,
            role: .assistant,
            text: "Orphan answer",
            clientMessageId:
                "019facf5-8484-7c80-a7fc-93a2932e0ad8",
            model: "gemini-2.5-flash",
            isRefusal: false,
            refusalReason: nil,
            createdAt: Date()
        )
        let recoveredPastOrphan = InsightChatViewModel.reconcileThread(
            [interrupted, orphanAssistant]
        )
        #expect(recoveredPastOrphan.messages.isEmpty)
        #expect(
            recoveredPastOrphan.pendingMessage?.id ==
                interruptedRequestId.lowercased()
        )
        let completed = InsightChatViewModel.reconcileThread(
            [
                interrupted,
                assistant,
                duplicateAssistant,
                orphanAssistant
            ]
        )
        #expect(
            completed.messages.map(\.id) == [
                interrupted.id,
                assistant.id
            ]
        )
        #expect(completed.pendingMessage == nil)

        viewModel.messages = (0 ..< 29).map { index in
            InsightChatMessage(
                id: "message-\(index)",
                conversationId: conversationId,
                scanId: subjectId,
                role: .assistant,
                text: "Saved answer \(index)",
                clientMessageId: nil,
                model: nil,
                isRefusal: false,
                refusalReason: nil,
                createdAt: Date()
            )
        }
        #expect(!viewModel.canSend)
        viewModel.messages.removeLast()
        viewModel.isOffline = false
        #expect(viewModel.canSend)
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

    @Test func testIdentificationConcernPromptDetection() {
        let concernPrompts = [
            "I think this identification is incorrect",
            "This ID is wrong.",
            "This is wrong",
            "That's not it",
            "It's not right",
            "This doesn't seem right",
            "This seems off",
            "I'm not convinced",
            "Are you sure this is the right species?",
            "I don't think this is a monarch.",
            "It doesn't look like this species.",
            "I think this is something else",
            "Could this be a different species?",
            "Could it be Alaus myops instead?",
            "This looks more like Alaus myops",
            "The markings don't match",
            "The color doesn't match",
            "The habitat doesn't fit",
            "The location seems unlikely for this species",
            "Can you check again?",
            "Analyze this again",
            "Can Merian take another look?",
            "Reanalyze this species"
        ]

        for prompt in concernPrompts {
            #expect(InsightChatViewModel.isIdentificationConcernPrompt(prompt))
        }

        let ordinaryPrompts = [
            "What traits support this identification?",
            "How do I tell it apart from Queen?",
            "Are you sure this is safe to touch?",
            "Could this be poisonous?",
            "What if something else changed?",
            "What should I check again next time?",
            "Should I use a different angle next time?",
            "What color should I look for?"
        ]

        for prompt in ordinaryPrompts {
            #expect(!InsightChatViewModel.isIdentificationConcernPrompt(prompt))
        }
    }

    @Test func testIdentificationReviewActionsAttachToAssistantReplyAfterConcern() {
        let viewModel = InsightChatViewModel()
        viewModel.messages = [
            InsightChatMessage(
                id: "user_1",
                conversationId: "conv1",
                scanId: "chat_scan",
                role: .user,
                text: "I think this identification is incorrect",
                clientMessageId: nil,
                model: nil,
                isRefusal: false,
                refusalReason: nil,
                createdAt: Date()
            ),
            InsightChatMessage(
                id: "assistant_1",
                conversationId: "conv1",
                scanId: "chat_scan",
                role: .assistant,
                text: "Here is what the saved evidence says.",
                clientMessageId: nil,
                model: "gemini-2.5-flash",
                isRefusal: false,
                refusalReason: nil,
                createdAt: Date()
            ),
            InsightChatMessage(
                id: "user_2",
                conversationId: "conv1",
                scanId: "chat_scan",
                role: .user,
                text: "What should I look for nearby?",
                clientMessageId: nil,
                model: nil,
                isRefusal: false,
                refusalReason: nil,
                createdAt: Date()
            ),
            InsightChatMessage(
                id: "assistant_2",
                conversationId: "conv1",
                scanId: "chat_scan",
                role: .assistant,
                text: "Check nearby host plants.",
                clientMessageId: nil,
                model: "gemini-2.5-flash",
                isRefusal: false,
                refusalReason: nil,
                createdAt: Date()
            )
        ]

        #expect(viewModel.shouldOfferIdentificationReviewActions(forAssistantMessageAt: 1))
        #expect(!viewModel.shouldOfferIdentificationReviewActions(forAssistantMessageAt: 3))
        #expect(!viewModel.shouldOfferIdentificationReviewActions(forAssistantMessageAt: 0))
    }

    @Test func testForbiddenChatErrorExplainsAccountOwnership() {
        let message = InsightChatViewModel.userFacingMessage(
            for: MerianError.httpError(statusCode: 403, message: #"{"error":"Forbidden"}"#)
        )

        #expect(message == "This scan belongs to another account.")
    }

    @Test func testOnlyTerminalScanErrorsHideChatEntry() {
        #expect(InsightChatViewModel.isDeterministicallyUnavailable(
            MerianError.httpError(statusCode: 403, message: #"{"error":"Forbidden"}"#)
        ))
        #expect(!InsightChatViewModel.isDeterministicallyUnavailable(
            MerianError.httpError(statusCode: 404, message: #"{"code":"scan_not_ready"}"#)
        ))
        #expect(InsightChatViewModel.isDeterministicallyUnavailable(
            MerianError.httpError(statusCode: 400, message: #"{"code":"unsupported_scan"}"#)
        ))
        #expect(!InsightChatViewModel.isDeterministicallyUnavailable(
            MerianError.httpError(statusCode: 404, message: #"{"code":"message_not_found"}"#)
        ))
        #expect(!InsightChatViewModel.isDeterministicallyUnavailable(
            MerianError.httpError(statusCode: 404, message: #"{"code":"conversation_not_found"}"#)
        ))
        #expect(!InsightChatViewModel.isDeterministicallyUnavailable(
            MerianError.httpError(statusCode: 429, message: #"{"code":"daily_limit_reached"}"#)
        ))
        #expect(!InsightChatViewModel.isDeterministicallyUnavailable(
            MerianError.edgeFunctionUnavailable
        ))
        #expect(InsightChatViewModel.isDeterministicallyUnavailable(
            MerianError.httpError(
                statusCode: 404,
                message: #"{"code":"post_not_available"}"#
            ),
            source: .explorePost
        ))
        #expect(!InsightChatViewModel.isDeterministicallyUnavailable(
            MerianError.httpError(
                statusCode: 404,
                message: #"{"code":"message_not_found"}"#
            ),
            source: .explorePost
        ))
        #expect(!InsightChatViewModel.isDeterministicallyUnavailable(
            MerianError.httpError(
                statusCode: 404,
                message: #"{"error":"route not found"}"#
            ),
            source: .explorePost
        ))
        #expect(
            InsightChatViewModel.userFacingMessage(for: MerianError.edgeFunctionUnavailable)
                == "Chat is unavailable right now."
        )
    }

    @Test func testTransientOwnedScanReadinessKeepsChatEntryRetryable() {
        let viewModel = InsightChatViewModel()

        let canPresent = viewModel.applyOwnedScanReadinessStatus(
            "not_found",
            scanId: "scan_1"
        )

        #expect(!canPresent)
        #expect(!viewModel.isUnavailable(for: "scan_1"))
        #expect(viewModel.errorMessage == InsightChatViewModel.stillSyncingMessage)
    }

    @Test func testMarkUnavailableStoresScanScopedChatUnavailableState() {
        let viewModel = InsightChatViewModel()

        viewModel.markUnavailable(scanId: "scan_1")

        #expect(viewModel.isUnavailable(for: "scan_1"))
        #expect(!viewModel.isUnavailable(for: "scan_2"))
        #expect(viewModel.errorMessage == "Field chat isn't available for this scan.")
    }

    @Test func testMarkAvailableClearsRecoveredScanUnavailableState() {
        let viewModel = InsightChatViewModel()
        viewModel.markUnavailable(scanId: "scan_1")

        viewModel.markAvailable(scanId: "scan_1")

        #expect(!viewModel.isUnavailable(for: "scan_1"))
        #expect(viewModel.errorMessage == nil)
    }

    @Test func testConcurrentPresentationRequestsSharePreparationResult() async {
        let viewModel = InsightChatViewModel(source: .explorePost)
        let (preparationGate, gateContinuation) = AsyncStream<Void>.makeStream()
        let (secondRequestStarted, secondRequestContinuation) = AsyncStream<Void>.makeStream()
        var preparationCount = 0
        let preparation: @MainActor () async -> Bool = {
            preparationCount += 1
            for await _ in preparationGate {
                break
            }
            return true
        }

        let firstRequest = Task { @MainActor in
            await viewModel.prepareForPresentation(
                scanId: "post_1",
                using: preparation
            )
        }
        while preparationCount == 0 {
            await Task.yield()
        }

        let secondRequest = Task { @MainActor in
            secondRequestContinuation.yield()
            return await viewModel.prepareForPresentation(
                scanId: "post_1",
                using: preparation
            )
        }
        for await _ in secondRequestStarted {
            break
        }
        secondRequestContinuation.finish()
        gateContinuation.yield()
        gateContinuation.finish()

        let firstResult = await firstRequest.value
        let secondResult = await secondRequest.value

        #expect(firstResult)
        #expect(secondResult)
        #expect(preparationCount == 1)
        #expect(!viewModel.isCheckingAvailability)
    }

    @Test func testPresentationPreparationPublishesLoadingStateBeforeNetworkCompletes() async {
        let viewModel = InsightChatViewModel()
        let (preparationGate, gateContinuation) = AsyncStream<Void>.makeStream()
        var preparationStarted = false

        let request = Task { @MainActor in
            await viewModel.prepareForPresentation(scanId: "scan_1") {
                preparationStarted = true
                for await _ in preparationGate {
                    break
                }
                return true
            }
        }
        while !preparationStarted {
            await Task.yield()
        }

        #expect(viewModel.isCheckingAvailability)

        gateContinuation.yield()
        gateContinuation.finish()
        #expect(await request.value)
        #expect(!viewModel.isCheckingAvailability)
    }

    @Test func testFieldChatRejectsStaleSubjectCompletion() {
        let viewModel = InsightChatViewModel()
        let firstScanId = "019fb00a-fb11-7765-93c8-35429f3750a1"
        let secondScanId = "019fb00a-fbd1-7b77-bf88-fd7110114081"
        let firstGeneration = viewModel.activateSubject(scanId: firstScanId)
        viewModel.setDraftText("Private note for the first scan", scanId: firstScanId)

        let secondGeneration = viewModel.activateSubject(scanId: secondScanId)
        let staleResponse = InsightChatResponse(
            subjectId: firstScanId,
            conversationId: nil,
            messages: [],
            limits: InsightChatLimits(
                maxUserMessageCharacters: 600,
                maxMessagesPerConversation: 30,
                dailySendLimit: 20,
                sendsRemainingToday: 19
            )
        )
        let currentResponse = InsightChatResponse(
            subjectId: secondScanId,
            conversationId: nil,
            messages: [],
            limits: InsightChatLimits(
                maxUserMessageCharacters: 600,
                maxMessagesPerConversation: 30,
                dailySendLimit: 20,
                sendsRemainingToday: 18
            )
        )

        #expect(!viewModel.applyIfCurrent(
            staleResponse,
            scanId: firstScanId,
            generation: firstGeneration
        ))
        #expect(viewModel.draftText.isEmpty)
        #expect(viewModel.limits.sendsRemainingToday == 20)
        #expect(viewModel.applyIfCurrent(
            currentResponse,
            scanId: secondScanId,
            generation: secondGeneration
        ))
        #expect(viewModel.limits.sendsRemainingToday == 18)
    }

    @Test func testFieldChatReplacesPreparationForChangedSubject() async {
        let viewModel = InsightChatViewModel(source: .explorePost)
        let (firstGate, firstGateContinuation) = AsyncStream<Void>.makeStream()
        var firstPreparationStarted = false
        let firstRequest = Task { @MainActor in
            await viewModel.prepareForPresentation(scanId: "post_1") {
                firstPreparationStarted = true
                for await _ in firstGate {
                    break
                }
                return true
            }
        }
        while !firstPreparationStarted {
            await Task.yield()
        }

        let secondResult = await viewModel.prepareForPresentation(scanId: "post_2") {
            true
        }
        firstGateContinuation.yield()
        firstGateContinuation.finish()
        let firstResult = await firstRequest.value

        #expect(!firstResult)
        #expect(secondResult)
        #expect(!viewModel.isCheckingAvailability)
    }
}
