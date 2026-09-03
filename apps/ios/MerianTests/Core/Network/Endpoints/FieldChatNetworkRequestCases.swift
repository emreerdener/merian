import Foundation
import Testing

@testable import Merian

enum FieldChatNetworkTestSource: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case insight
    case explorePost
    case speciesDictionary

    var testDescription: String { rawValue }
    var function: String {
        switch self {
        case .insight: "insight-chat"
        case .explorePost: "explore-post-chat"
        case .speciesDictionary: "species-dictionary-chat"
        }
    }
    var subjectKey: String {
        switch self {
        case .insight: "scan_id"
        case .explorePost: "post_id"
        case .speciesDictionary: "species_id"
        }
    }

    @MainActor
    func load(_ client: MerianNetworkClient, id: String) async throws -> InsightChatResponse {
        switch self {
        case .insight: try await client.loadInsightChat(scanId: id)
        case .explorePost: try await client.loadExplorePostChat(postId: id)
        case .speciesDictionary: try await client.loadSpeciesDictionaryChat(speciesId: id)
        }
    }

    @MainActor
    func send(_ client: MerianNetworkClient, id: String, text: String, key: String) async throws -> InsightChatResponse {
        switch self {
        case .insight: try await client.sendInsightChatMessage(scanId: id, messageText: text, clientMessageId: key)
        case .explorePost: try await client.sendExplorePostChatMessage(postId: id, messageText: text, clientMessageId: key)
        case .speciesDictionary: try await client.sendSpeciesDictionaryChatMessage(speciesId: id, messageText: text, clientMessageId: key)
        }
    }

    @MainActor
    func delete(_ client: MerianNetworkClient, id: String) async throws -> InsightChatResponse {
        switch self {
        case .insight: try await client.deleteInsightChat(scanId: id)
        case .explorePost: try await client.deleteExplorePostChat(postId: id)
        case .speciesDictionary: try await client.deleteSpeciesDictionaryChat(speciesId: id)
        }
    }

    @MainActor
    func feedback(
        _ client: MerianNetworkClient, id: String, messageID: String, rating: InsightChatFeedbackRating, note: String?
    ) async throws -> InsightChatFeedbackResponse {
        switch self {
        case .insight: try await client.submitInsightChatFeedback(scanId: id, messageId: messageID, rating: rating, note: note)
        case .explorePost: try await client.submitExplorePostChatFeedback(postId: id, messageId: messageID, rating: rating, note: note)
        case .speciesDictionary: try await client.submitSpeciesDictionaryChatFeedback(speciesId: id, messageId: messageID, rating: rating, note: note)
        }
    }

    @MainActor
    func prompts(_ client: MerianNetworkClient, id: String) async throws -> InsightChatPromptSuggestionsResponse {
        switch self {
        case .insight: try await client.suggestInsightChatPrompts(scanId: id)
        case .explorePost: try await client.suggestExplorePostChatPrompts(postId: id)
        case .speciesDictionary: try await client.suggestSpeciesDictionaryChatPrompts(speciesId: id)
        }
    }
}

struct FieldChatNetworkRequestCase: Sendable, CustomTestStringConvertible {
    enum Key: Sendable {
        case none
        case supplied(String)
        case generated
    }

    private typealias Fixtures = FieldChatNetworkFixtures
    let name: String
    let function: String
    let action: String
    let expectedJSON: String
    let responseJSON: String
    let timeout: TimeInterval
    let key: Key
    var expectsInvalidResponse = false
    let invoke: @MainActor @Sendable (MerianNetworkClient) async throws -> Void

    var testDescription: String { name }
    var path: String { "/\(function)" }
    var allowsAmbiguousReplay: Bool {
        if case .none = key { return false }
        return true
    }

    static var operations: [Self] {
        FieldChatNetworkTestSource.allCases.flatMap { source in
            [load(source), send(source), delete(source), feedback(source), prompts(source)]
        } + [featureFeedback(), summary]
    }
    static var replayableOperations: [Self] { operations.filter(\.allowsAmbiguousReplay) }
    static var nonReplayableOperations: [Self] { operations.filter { !$0.allowsAmbiguousReplay } }
    static var all: [Self] {
        operations + FieldChatNetworkTestSource.allCases.flatMap { source in
            InsightChatFeedbackRating.allCases.filter { $0 != .helpful }.map { feedback(source, rating: $0) } + [
                feedback(source, note: ""), feedback(source, note: "  Private test note \n "),
                send(source, text: " \n\(Fixtures.question) \n "),
                send(source, key: Fixtures.requestID.uppercased()),
                send(source, text: String(repeating: "q", count: 600)),
                send(source, text: String(repeating: "q", count: 601), expectsInvalidResponse: true),
                send(source, text: "", expectsInvalidResponse: true),
                load(source, id: " \n\(Fixtures.subjectID.uppercased()) \n "),
                delete(source, id: Fixtures.subjectID.uppercased())
            ]
        } + [
            featureFeedback(sentiment: nil, note: nil),
            featureFeedback(sentiment: nil, note: "  Private test note \n "),
            featureFeedback(sentiment: .negative, note: ""),
            featureFeedback(sentiment: .positive, note: String(repeating: "n", count: 501))
        ]
    }

    @discardableResult
    func expectRequest(_ request: URLRequest) throws -> NetworkEndpointRequestSnapshot {
        let actualKey = request.value(forHTTPHeaderField: "Idempotency-Key")
        switch key {
        case .none: #expect(actualKey == nil)
        case .supplied(let expected): #expect(actualKey == expected)
        case .generated:
            let value = try #require(actualKey)
            #expect(UUID(uuidString: value) != nil && value == value.lowercased())
        }
        return try NetworkEndpointTestSupport.expectPOST(
            request, function: function, json: expectedJSON, timeout: timeout, idempotencyKey: actualKey
        )
    }

    @MainActor
    func withResponse(
        _ json: String? = nil, body: (MerianNetworkClient) async throws -> Void
    ) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        try await confirmation("Exactly one Field Chat POST") { sent in
            fixture.transport.register(path: path) { request in
                sent()
                try expectRequest(request)
                return try NetworkEndpointTestSupport.response(to: request, json: json ?? responseJSON)
            }
            try await body(fixture.client)
        }
    }

    static func load(_ source: FieldChatNetworkTestSource, id: String = Fixtures.subjectID) -> Self {
        Self(name: "\(source.rawValue) load: \(id)", function: source.function, action: "load",
             expectedJSON: Fixtures.json(["action": "load", source.subjectKey: id]),
             responseJSON: Fixtures.envelope(Fixtures.conversation()), timeout: source == .insight ? 45 : 20, key: .none) { client in
            _ = try await source.load(client, id: id)
        }
    }

    static func send(
        _ source: FieldChatNetworkTestSource, text: String = Fixtures.question, key: String = Fixtures.requestID,
        expectsInvalidResponse: Bool = false
    ) -> Self {
        Self(name: "\(source.rawValue) send: \(text.count) characters, \(key)", function: source.function, action: "send",
             expectedJSON: Fixtures.json(["action": "send", source.subjectKey: Fixtures.subjectID,
                                          "message_text": text, "client_message_id": key]),
             responseJSON: Fixtures.envelope(Fixtures.conversation(question: text.trimmingCharacters(in: .whitespacesAndNewlines))),
             timeout: source == .explorePost ? 20 : 45, key: .supplied(key), expectsInvalidResponse: expectsInvalidResponse) { client in
            _ = try await source.send(client, id: Fixtures.subjectID, text: text, key: key)
        }
    }

    static func delete(_ source: FieldChatNetworkTestSource, id: String = Fixtures.subjectID) -> Self {
        Self(name: "\(source.rawValue) delete: \(id)", function: source.function, action: "delete",
             expectedJSON: Fixtures.json(["action": "delete", source.subjectKey: id]),
             responseJSON: Fixtures.envelope(Fixtures.emptyConversation()), timeout: source == .insight ? 45 : 20, key: .none) { client in
            _ = try await source.delete(client, id: id)
        }
    }

    static func feedback(
        _ source: FieldChatNetworkTestSource, rating: InsightChatFeedbackRating = .helpful, note: String? = nil
    ) -> Self {
        var expected: [String: Any] = ["action": "feedback", source.subjectKey: Fixtures.subjectID,
                                       "message_id": Fixtures.assistantMessageID, "feedback_rating": rating.rawValue]
        if let note { expected["feedback_note"] = note }
        return Self(name: "\(source.rawValue) feedback: \(rating.rawValue), \(note ?? "nil")", function: source.function,
                    action: "feedback", expectedJSON: Fixtures.json(expected),
                    responseJSON: Fixtures.envelope(Fixtures.feedback(rating: rating.rawValue)), timeout: 20, key: .none) { client in
            _ = try await source.feedback(client, id: Fixtures.subjectID, messageID: Fixtures.assistantMessageID, rating: rating, note: note)
        }
    }

    static func prompts(_ source: FieldChatNetworkTestSource) -> Self {
        Self(name: "\(source.rawValue) prompts", function: source.function, action: "suggest_prompts",
             expectedJSON: Fixtures.json(["action": "suggest_prompts", source.subjectKey: Fixtures.subjectID]),
             responseJSON: Fixtures.envelope(Fixtures.prompts), timeout: 30, key: source == .insight ? .generated : .none) { client in
            _ = try await source.prompts(client, id: Fixtures.subjectID)
        }
    }

    static func featureFeedback(
        sentiment: InsightChatFeatureFeedbackSentiment? = .positive, note: String? = nil
    ) -> Self {
        var expected: [String: Any] = ["action": "feature_feedback", "scan_id": Fixtures.subjectID]
        if let sentiment { expected["feature_feedback_sentiment"] = sentiment.rawValue }
        if let note { expected["feedback_note"] = note }
        return Self(name: "Insight feature feedback: \(sentiment?.rawValue ?? "nil"), \(note ?? "nil")", function: "insight-chat",
                    action: "feature_feedback", expectedJSON: Fixtures.json(expected),
                    responseJSON: Fixtures.envelope(Fixtures.featureFeedback(sentiment: sentiment?.rawValue)), timeout: 20, key: .none) { client in
            _ = try await client.submitInsightChatFeatureFeedback(scanId: Fixtures.subjectID, sentiment: sentiment, note: note)
        }
    }

    static var summary: Self {
        Self(name: "Insight note summary", function: "insight-chat", action: "summarize_notes",
             expectedJSON: #"{"action":"summarize_notes","scan_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}"#,
             responseJSON: Fixtures.envelope(Fixtures.summary), timeout: 45, key: .generated) { client in
            _ = try await client.summarizeInsightChatForFieldNotes(scanId: Fixtures.subjectID)
        }
    }
}
