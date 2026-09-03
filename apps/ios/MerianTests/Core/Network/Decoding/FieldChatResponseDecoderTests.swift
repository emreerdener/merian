import Foundation
import Testing

@testable import Merian

@Suite("Field Chat Response Decoder")
struct FieldChatResponseDecoderTests {
    private typealias Fixtures = FieldChatNetworkFixtures
    private typealias Decoder = FieldChatResponseDecoder

    @Test(arguments: FieldChatDecodingCase.allCases, ["", "not-json", "null", "[]", "{}", #"{"data":null}"#])
    func malformedEnvelopesUseInvalidResponse(_ testCase: FieldChatDecodingCase, json: String) {
        #expect(throws: MerianError.invalidResponse) { try testCase.decode(Data(json.utf8)) }
    }

    @Test(arguments: FieldChatDecodingCase.allCases)
    func byteLimitIsInclusiveAndAppliedBeforeAcceptingSuccess(_ testCase: FieldChatDecodingCase) throws {
        var data = encoded(testCase.payload)
        data.append(Data(repeating: 0x20, count: 1_048_576 - data.count))
        #expect(data.count == 1_048_576)
        try testCase.decode(data)
        data.append(0x20)
        #expect(throws: MerianError.invalidResponse) { try testCase.decode(data) }
    }

    @Test(arguments: FieldChatDecodingCase.allCases, ["", "other-subject", "missing"])
    func everySuccessMustBindToItsExpectedSubject(_ testCase: FieldChatDecodingCase, subject: String) {
        var payload = testCase.payload
        payload["subject_id"] = subject == "missing" ? nil : subject
        #expect(throws: MerianError.invalidResponse) { try testCase.decode(encoded(payload)) }
    }

    @Test(arguments: FieldChatDecodingCase.allCases)
    func subjectComparisonKeepsItsExistingCaseAndWhitespacePolicy(_ testCase: FieldChatDecodingCase) throws {
        let data = encoded(testCase.payload)
        try testCase.decode(data, subjectID: Fixtures.subjectID.uppercased())
        let padded = " \n\(Fixtures.subjectID.uppercased()) \n "
        if testCase == .conversation {
            try testCase.decode(data, subjectID: padded)
        } else {
            #expect(throws: MerianError.invalidResponse) { try testCase.decode(data, subjectID: padded) }
        }
    }

    @Test func conversationPreservesServerOrderMetadataAndBothISODateFormats() throws {
        var payload = Fixtures.conversation()
        var messages = try #require(payload["messages"] as? [[String: Any]])
        payload["subject_id"] = Fixtures.subjectID.uppercased()
        payload["conversation_id"] = Fixtures.conversationID.uppercased()
        messages[0]["created_at"] = "2026-09-01T12:00:02.125Z"
        messages[1]["is_refusal"] = true
        messages[1]["refusal_reason"] = "test_policy"
        messages[1]["client_message_id"] = NSNull()
        payload["messages"] = messages

        let response = try conversation(payload)
        #expect(response.subjectId == Fixtures.subjectID.uppercased())
        #expect(response.conversationId == Fixtures.conversationID.uppercased())
        #expect(response.messages.map(\.id) == [Fixtures.userMessageID, Fixtures.assistantMessageID])
        #expect(response.messages.map(\.text) == [Fixtures.question, Fixtures.answer])
        #expect(response.messages.map(\.model) == [nil, "test-model"])
        #expect(response.messages[0].createdAt.timeIntervalSince(response.messages[1].createdAt) == 1.125)
        #expect(response.messages[1].isRefusal && response.messages[1].refusalReason == "test_policy")
        #expect(response.messages[1].clientMessageId == nil)
    }

    @Test(arguments: [0, 20])
    func remainingQuotaAcceptsBothBounds(_ remaining: Int) throws {
        var payload = Fixtures.emptyConversation()
        var limits = Fixtures.limits
        limits["sends_remaining_today"] = remaining
        payload["limits"] = limits
        let response = try conversation(payload)
        #expect(response.conversationId == nil && response.messages.isEmpty)
        #expect(response.limits.sendsRemainingToday == remaining)
    }

    @Test func quotaAndLimitChangesAreRejected() {
        for (key, value) in [
            ("max_user_message_chars", 599), ("max_user_message_chars", 601),
            ("max_messages_per_conversation", 29), ("max_messages_per_conversation", 31),
            ("daily_send_limit", 19), ("daily_send_limit", 21),
            ("sends_remaining_today", -1), ("sends_remaining_today", 21)
        ] {
            var payload = Fixtures.emptyConversation()
            var limits = Fixtures.limits
            limits[key] = value
            payload["limits"] = limits
            #expect(throws: MerianError.invalidResponse) { try conversation(payload) }
        }
    }

    @Test(arguments: [0, 30, 31])
    func messageCountUsesTheFixedConversationLimit(_ count: Int) throws {
        var payload = Fixtures.conversation()
        let messages = (0..<count).map { index in
            Fixtures.message(
                id: "10000000-0000-4000-8000-\(String(format: "%012d", index))", requestID: nil
            )
        }
        payload["messages"] = messages
        if count <= 30 {
            #expect(try conversation(payload).messages.count == count)
        } else {
            #expect(throws: MerianError.invalidResponse) { try conversation(payload) }
        }
    }

    @Test func nonemptyConversationRequiresAnUnpaddedUUID() {
        let invalidIDs: [Any] = [NSNull(), "", "invalid", " \(Fixtures.conversationID) "]
        for id in invalidIDs {
            var payload = Fixtures.conversation()
            payload["conversation_id"] = id
            #expect(throws: MerianError.invalidResponse) { try conversation(payload) }
        }
    }

    @Test func messageFieldsAndSemanticUUIDUniquenessAreValidated() throws {
        let invalidFields: [(String, Any)] = [
            ("id", "invalid"), ("id", Fixtures.userMessageID.uppercased()),
            ("scan_id", "other-subject"), ("conversation_id", Fixtures.subjectID),
            ("client_message_id", "invalid"), ("text", ""), ("text", " padded "),
            ("created_at", "not-a-date"), ("role", "system"), ("is_refusal", NSNull())
        ]
        for (key, value) in invalidFields {
            var payload = Fixtures.conversation()
            var messages = try #require(payload["messages"] as? [[String: Any]])
            messages[1][key] = value
            payload["messages"] = messages
            #expect(throws: MerianError.invalidResponse) { try conversation(payload) }
        }
    }

    @Test(arguments: [1, 4_000, 4_001])
    func messageLimitCountsCharactersNotUTF8Bytes(_ count: Int) throws {
        var payload = Fixtures.conversation()
        let text = String(repeating: "🐛", count: count)
        payload["messages"] = [Fixtures.message(text: text)]
        if count <= 4_000 {
            #expect(try conversation(payload).messages.first?.text == text)
        } else {
            #expect(throws: MerianError.invalidResponse) { try conversation(payload) }
        }
    }

    @Test(arguments: [1, 600, 601])
    func sendAcknowledgementUsesTrimmedRequestAndCharacterLimit(_ count: Int) throws {
        let question = String(repeating: "é", count: count)
        let data = encoded(Fixtures.conversation(question: question))
        let decode = {
            try Decoder.decodeConversation(
                data, expectedSubjectId: Fixtures.subjectID,
                expectedClientMessageId: " \(Fixtures.requestID.uppercased()) ",
                expectedUserMessageText: " \n\(question) \n "
            )
        }
        if count <= 600 {
            #expect(try decode().messages.first?.text == question)
        } else {
            #expect(throws: MerianError.invalidResponse) { try decode() }
        }
    }

    @Test func sendRequiresACompleteMatchingRequestPair() throws {
        let data = encoded(Fixtures.conversation())
        let expectations: [(String?, String?)] = [
            (nil, Fixtures.question), (Fixtures.requestID, nil),
            ("invalid", Fixtures.question), (Fixtures.subjectID, Fixtures.question),
            (Fixtures.requestID, ""), (Fixtures.requestID, "different question")
        ]
        for (requestID, text) in expectations {
            #expect(throws: MerianError.invalidResponse) {
                try Decoder.decodeConversation(
                    data, expectedSubjectId: Fixtures.subjectID,
                    expectedClientMessageId: requestID, expectedUserMessageText: text
                )
            }
        }
        for roles in [["user"], ["assistant"], ["user", "user"], ["assistant", "assistant"], ["user", "assistant", "assistant"]] {
            var payload = Fixtures.conversation()
            payload["messages"] = roles.enumerated().map { index, role in
                Fixtures.message(
                    id: "20000000-0000-4000-8000-\(String(format: "%012d", index))",
                    role: role, text: role == "user" ? Fixtures.question : Fixtures.answer
                )
            }
            #expect(throws: MerianError.invalidResponse) {
                try Decoder.decodeConversation(
                    encoded(payload), expectedSubjectId: Fixtures.subjectID,
                    expectedClientMessageId: Fixtures.requestID, expectedUserMessageText: Fixtures.question
                )
            }
        }
    }

    @Test(arguments: InsightChatFeedbackRating.allCases)
    func feedbackKeepsItsConfirmedRatingAndCaseInsensitiveMessageBinding(_ rating: InsightChatFeedbackRating) throws {
        let response = try Decoder.decodeFeedback(
            encoded(Fixtures.feedback(rating: rating.rawValue)), expectedSubjectId: Fixtures.subjectID,
            expectedMessageId: Fixtures.assistantMessageID.uppercased(), expectedRating: rating
        )
        #expect(response.ok && response.rating == rating && response.messageId == Fixtures.assistantMessageID)
    }

    @Test func feedbackRequiresConfirmationMatchingUUIDAndExpectedRating() {
        let invalidFields: [(String, Any)] = [
            ("ok", false), ("message_id", "invalid"), ("message_id", Fixtures.userMessageID),
            ("rating", "wrong"), ("rating", "unknown")
        ]
        for (key, value) in invalidFields {
            var payload = Fixtures.feedback()
            payload[key] = value
            #expect(throws: MerianError.invalidResponse) { try FieldChatDecodingCase.feedback.decode(encoded(payload)) }
        }
        #expect(throws: MerianError.invalidResponse) {
            try Decoder.decodeFeedback(
                encoded(Fixtures.feedback(messageID: "invalid")), expectedSubjectId: Fixtures.subjectID,
                expectedMessageId: "invalid", expectedRating: .helpful
            )
        }
    }

    @Test func featureFeedbackPreservesOptionalSentimentButRequiresConfirmation() throws {
        let sentiments: [InsightChatFeatureFeedbackSentiment?] = [nil, .positive, .negative]
        for sentiment in sentiments {
            let payload = Fixtures.featureFeedback(sentiment: sentiment?.rawValue)
            let response = try Decoder.decodeFeatureFeedback(
                encoded(payload), expectedSubjectId: Fixtures.subjectID, expectedSentiment: sentiment
            )
            #expect(response.ok && response.id == Fixtures.feedbackID && response.sentiment == sentiment)
        }
        let invalidFields: [(String, Any)] = [("ok", false), ("id", "invalid"), ("sentiment", "negative"), ("sentiment", NSNull())]
        for (key, value) in invalidFields {
            var payload = Fixtures.featureFeedback()
            payload[key] = value
            #expect(throws: MerianError.invalidResponse) { try FieldChatDecodingCase.featureFeedback.decode(encoded(payload)) }
        }
    }

    @Test(arguments: [1, 4_000, 4_001])
    func summaryIsTrimmedAndCharacterBounded(_ count: Int) throws {
        let text = String(repeating: "é", count: count)
        let data = encoded(["subject_id": Fixtures.subjectID.uppercased(), "summary_text": " \n\(text) \n "])
        if count <= 4_000 {
            let response = try Decoder.decodeSummary(data, expectedSubjectId: Fixtures.subjectID)
            #expect(response.summaryText == text && response.subjectId == Fixtures.subjectID.uppercased())
        } else {
            #expect(throws: MerianError.invalidResponse) { try Decoder.decodeSummary(data, expectedSubjectId: Fixtures.subjectID) }
        }
    }

    @Test(arguments: ["", " \n ", FieldChatNetworkFixtures.subjectID, FieldChatNetworkFixtures.subjectID.uppercased()])
    func summaryRejectsEmptyTextAndInternalIdentifiers(_ text: String) {
        let payload: [String: Any] = ["subject_id": Fixtures.subjectID, "summary_text": text]
        #expect(throws: MerianError.invalidResponse) { try FieldChatDecodingCase.summary.decode(encoded(payload)) }
    }

    @Test(arguments: ["confidence", "ecology", "evidence", "field_notes", "generic", "habitat", "hazard", "invasive", "lookalike_compare", "season"])
    func promptCategoriesKeepTheExistingAllowlist(_ category: String) throws {
        let response = try prompts([["text": "What traits distinguish this species?", "category": category]])
        #expect(response.prompts.first?.category == category)
    }

    @Test(arguments: [0, 1, 3, 4])
    func promptCountIsBoundedWithoutInventingSuggestions(_ count: Int) throws {
        let rows = (0..<count).map { ["text": "What distinguishes feature \($0)?", "category": "evidence"] }
        if count <= 3 {
            #expect(try prompts(rows).prompts.map(\.text) == rows.compactMap { $0["text"] })
        } else {
            #expect(throws: MerianError.invalidResponse) { try prompts(rows) }
        }
    }

    @Test func promptsRejectUnsafeWhitespaceDuplicatesCategoriesAndLength() {
        let invalidRows = [
            [["text": "", "category": "generic"]],
            [["text": " padded ", "category": "generic"]],
            [["text": "Valid text", "category": " evidence "]],
            [["text": "Valid text", "category": "EVIDENCE"]],
            [["text": "Valid text", "category": "unknown"]],
            [["text": String(repeating: "é", count: 121), "category": "generic"]],
            [["text": "Same prompt", "category": "evidence"], ["text": "SAME PROMPT", "category": "habitat"]]
        ]
        for rows in invalidRows {
            #expect(throws: MerianError.invalidResponse) { try prompts(rows) }
        }
    }

    @Test func promptTextLimitCountsCharactersAndConversationPaddingIsPreserved() throws {
        let text = String(repeating: "é", count: 120)
        var payload = Fixtures.prompts
        payload["conversation_id"] = " \(Fixtures.conversationID.uppercased()) "
        payload["prompts"] = [["text": text, "category": "generic"]]
        let response = try Decoder.decodePromptSuggestions(encoded(payload), expectedSubjectId: Fixtures.subjectID)
        #expect(response.conversationId == " \(Fixtures.conversationID.uppercased()) ")
        #expect(response.prompts.first?.text == text)
        payload["conversation_id"] = NSNull()
        #expect(try Decoder.decodePromptSuggestions(encoded(payload), expectedSubjectId: Fixtures.subjectID).conversationId == nil)
        for invalid in ["", "  ", "invalid"] {
            payload["conversation_id"] = invalid
            #expect(throws: MerianError.invalidResponse) { try FieldChatDecodingCase.prompts.decode(encoded(payload)) }
        }
    }

    @Test(arguments: [
        "Can I eat this species?", "How to pick up this animal?", "Is this edible?",
        "Could my dog consume this?", "Show me how to relocate it.",
        "What should I do after being stung?", "Is there an antidote?",
        "Am I allowed to collect this?", "Where exactly was it seen?", "Can you identify this person?"
    ])
    func unsafePromptPatternsRemainCaseInsensitive(_ text: String) {
        for variant in [text, text.uppercased()] {
            #expect(throws: MerianError.invalidResponse) { try prompts([["text": variant, "category": "generic"]]) }
        }
    }

    private func encoded(_ payload: [String: Any]) -> Data { Data(Fixtures.envelope(payload).utf8) }

    private func conversation(_ payload: [String: Any]) throws -> InsightChatResponse {
        try Decoder.decodeConversation(encoded(payload), expectedSubjectId: Fixtures.subjectID)
    }

    private func prompts(_ rows: [[String: String]]) throws -> InsightChatPromptSuggestionsResponse {
        var payload = Fixtures.prompts
        payload["prompts"] = rows
        return try Decoder.decodePromptSuggestions(encoded(payload), expectedSubjectId: Fixtures.subjectID)
    }
}

enum FieldChatDecodingCase: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case conversation, feedback, featureFeedback, summary, prompts
    var testDescription: String { rawValue }

    var payload: [String: Any] {
        switch self {
        case .conversation: FieldChatNetworkFixtures.conversation()
        case .feedback: FieldChatNetworkFixtures.feedback()
        case .featureFeedback: FieldChatNetworkFixtures.featureFeedback()
        case .summary: FieldChatNetworkFixtures.summary
        case .prompts: FieldChatNetworkFixtures.prompts
        }
    }

    func decode(_ data: Data, subjectID: String = FieldChatNetworkFixtures.subjectID) throws {
        switch self {
        case .conversation:
            _ = try FieldChatResponseDecoder.decodeConversation(data, expectedSubjectId: subjectID)
        case .feedback:
            _ = try FieldChatResponseDecoder.decodeFeedback(
                data, expectedSubjectId: subjectID, expectedMessageId: FieldChatNetworkFixtures.assistantMessageID, expectedRating: .helpful
            )
        case .featureFeedback:
            _ = try FieldChatResponseDecoder.decodeFeatureFeedback(data, expectedSubjectId: subjectID, expectedSentiment: .positive)
        case .summary:
            _ = try FieldChatResponseDecoder.decodeSummary(data, expectedSubjectId: subjectID)
        case .prompts:
            _ = try FieldChatResponseDecoder.decodePromptSuggestions(data, expectedSubjectId: subjectID)
        }
    }
}
