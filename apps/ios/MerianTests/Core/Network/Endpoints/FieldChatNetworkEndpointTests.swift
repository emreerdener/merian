import Foundation
import Testing

@testable import Merian

@Suite("Field Chat Network Endpoints")
@MainActor
struct FieldChatNetworkEndpointTests {
    private typealias RequestCase = FieldChatNetworkRequestCase

    @Test func requestInventoryKeepsSeventeenOperationsAcrossThreeRoutes() {
        #expect(RequestCase.operations.count == 17)
        #expect(RequestCase.all.count == 60)
        #expect(Set(RequestCase.operations.map(\.function)) == [
            "insight-chat", "explore-post-chat", "species-dictionary-chat"
        ])
        #expect(Set(RequestCase.operations.map { "\($0.function):\($0.action)" }).count == 17)
        #expect(RequestCase.replayableOperations.count == 5)
        #expect(RequestCase.nonReplayableOperations.count == 12)
        #expect(RequestCase.operations.filter { $0.function == "insight-chat" }.count == 7)
        #expect(RequestCase.operations.filter { $0.function == "explore-post-chat" }.count == 5)
        #expect(RequestCase.operations.filter { $0.function == "species-dictionary-chat" }.count == 5)
    }

    @Test(arguments: FieldChatNetworkRequestCase.all)
    func requestMappingRemainsStable(_ testCase: FieldChatNetworkRequestCase) async throws {
        try await testCase.withResponse { client in
            if testCase.expectsInvalidResponse {
                // The client forwards raw text; the unchanged success validator
                // rejects an acknowledgement of an empty or over-limit send.
                await #expect(throws: MerianError.invalidResponse) {
                    try await testCase.invoke(client)
                }
            } else {
                try await testCase.invoke(client)
            }
        }
    }

    @Test(arguments: FieldChatNetworkTestSource.allCases)
    func conversationWrappersKeepTheValidatedProjection(_ source: FieldChatNetworkTestSource) async throws {
        typealias Fixtures = FieldChatNetworkFixtures
        try await RequestCase.load(source).withResponse { client in
            let response = try await source.load(client, id: Fixtures.subjectID)
            #expect(response.subjectId == Fixtures.subjectID)
            #expect(response.conversationId == Fixtures.conversationID)
            #expect(response.messages.map(\.id) == [Fixtures.userMessageID, Fixtures.assistantMessageID])
            #expect(response.messages.map(\.text) == [Fixtures.question, Fixtures.answer])
            #expect(response.messages.map(\.model) == [nil, "test-model"])
            #expect(response.limits.sendsRemainingToday == 19)
        }
    }
}
