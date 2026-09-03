import Foundation
import Testing

@testable import Merian

@Suite("Field Chat Conversation Endpoints")
@MainActor
struct FieldChatConversationEndpointTests {
    @Test func testFieldChatRejectsMalformedOrCrossSubjectSuccessResponses() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let insightScanID = "019faaeb-4616-7a1c-b5d8-19d0b6214c83"
        let explorePostID = "019faaeb-4ab8-75ff-8254-26b6430e0d85"
        let otherSubjectID = "019faaeb-4d99-7a19-8471-89676790048b"
        let conversationID = "019faaeb-507d-7901-9be2-8cc9b908ce74"
        let requestID = "019faaeb-52e2-7a67-b085-b9972b0ef36c"
        let responseURL = try #require(URL(string: "https://example.com"))
        let response = try #require(
            HTTPURLResponse(
                url: responseURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )

        func chatResponse(
            subjectID: String,
            envelopeSubjectID: String? = nil,
            role: String = "assistant",
            envelopeConversationID: String? = nil,
            messageConversationID: String? = nil,
            messageID: String =
                "019faaeb-5400-70a5-a6db-5469275b29fa",
            messageText: String =
                "The saved evidence supports this identification.",
            clientMessageID: String? = nil,
            dailySendLimit: Int = 20,
            sendsRemainingToday: Int = 19
        ) -> Data {
            let clientMessageJSON = clientMessageID.map {
                "\"\($0)\""
            } ?? "null"
            return Data(
                """
                {
                  "data": {
                    "subject_id": "\(envelopeSubjectID ?? subjectID)",
                    "conversation_id": "\(envelopeConversationID ?? conversationID)",
                    "messages": [
                      {
                        "id": "\(messageID)",
                        "conversation_id": "\(messageConversationID ?? conversationID)",
                        "scan_id": "\(subjectID)",
                        "role": "\(role)",
                        "text": "\(messageText)",
                        "client_message_id": \(clientMessageJSON),
                        "model": "gemini-2.5-flash",
                        "is_refusal": false,
                        "refusal_reason": null,
                        "created_at": "2026-07-29T15:00:00.000Z"
                      }
                    ],
                    "limits": {
                      "max_user_message_chars": 600,
                      "max_messages_per_conversation": 30,
                      "daily_send_limit": \(dailySendLimit),
                      "sends_remaining_today": \(sendsRemainingToday)
                    }
                  }
                }
                """.utf8
            )
        }

        func completedSendResponse(
            subjectID: String,
            clientMessageID: String,
            userMessageText: String = "Which traits support this ID?"
        ) -> Data {
            Data(
                """
                {
                  "data": {
                    "subject_id": "\(subjectID)",
                    "conversation_id": "\(conversationID)",
                    "messages": [
                      {
                        "id": "019faaeb-5330-7e2d-b3b8-36232fde6397",
                        "conversation_id": "\(conversationID)",
                        "scan_id": "\(subjectID)",
                        "role": "user",
                        "text": "\(userMessageText)",
                        "client_message_id": "\(clientMessageID)",
                        "model": null,
                        "is_refusal": false,
                        "refusal_reason": null,
                        "created_at": "2026-07-29T15:00:00.000Z"
                      },
                      {
                        "id": "019faaeb-5400-70a5-a6db-5469275b29fa",
                        "conversation_id": "\(conversationID)",
                        "scan_id": "\(subjectID)",
                        "role": "assistant",
                        "text": "The saved evidence supports this identification.",
                        "client_message_id": "\(clientMessageID)",
                        "model": "gemini-2.5-flash",
                        "is_refusal": false,
                        "refusal_reason": null,
                        "created_at": "2026-07-29T15:00:01.000Z"
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
                """.utf8
            )
        }

        func emptyChatResponse(subjectID: String) -> Data {
            Data(
                """
                {
                  "data": {
                    "subject_id": "\(subjectID)",
                    "conversation_id": null,
                    "messages": [],
                    "limits": {
                      "max_user_message_chars": 600,
                      "max_messages_per_conversation": 30,
                      "daily_send_limit": 20,
                      "sends_remaining_today": 20
                    }
                  }
                }
                """.utf8
            )
        }

        let missingSubjectEmptyChatResponse = Data(
            """
            {
              "data": {
                "conversation_id": null,
                "messages": [],
                "limits": {
                  "max_user_message_chars": 600,
                  "max_messages_per_conversation": 30,
                  "daily_send_limit": 20,
                  "sends_remaining_today": 20
                }
              }
            }
            """.utf8
        )

        fixture.transport.register(path: "/insight-chat") { _ in
            (response, chatResponse(subjectID: insightScanID))
        }
        let validInsight = try await fixture.client
            .loadInsightChat(scanId: insightScanID)
        #expect(validInsight.messages.first?.scanId == insightScanID)

        fixture.transport.register(path: "/insight-chat") { _ in
            (
                response,
                completedSendResponse(
                    subjectID: insightScanID,
                    clientMessageID: requestID
                )
            )
        }
        let completedSend = try await fixture.client
            .sendInsightChatMessage(
                scanId: insightScanID,
                messageText: "Which traits support this ID?",
                clientMessageId: requestID
            )
        #expect(
            completedSend.messages.filter {
                $0.clientMessageId == requestID
            }.count == 2
        )

        fixture.transport.register(path: "/insight-chat") { _ in
            (
                response,
                completedSendResponse(
                    subjectID: insightScanID,
                    clientMessageID: requestID,
                    userMessageText: "A different question"
                )
            )
        }
        await #expect(throws: MerianError.invalidResponse) {
            try await fixture.client.sendInsightChatMessage(
                scanId: insightScanID,
                messageText: "Which traits support this ID?",
                clientMessageId: requestID
            )
        }

        let invalidInsightResponses = [
            chatResponse(subjectID: otherSubjectID),
            emptyChatResponse(subjectID: otherSubjectID),
            missingSubjectEmptyChatResponse,
            chatResponse(
                subjectID: insightScanID,
                envelopeSubjectID: otherSubjectID
            ),
            chatResponse(subjectID: insightScanID, role: "future-role"),
            chatResponse(
                subjectID: insightScanID,
                messageConversationID:
                    "019faaeb-5923-71a8-a959-e2d8d864f9b7"
            ),
            chatResponse(subjectID: insightScanID, messageID: "not-a-uuid"),
            chatResponse(
                subjectID: insightScanID,
                envelopeConversationID: " \(conversationID) "
            ),
            chatResponse(subjectID: insightScanID, messageText: ""),
            chatResponse(
                subjectID: insightScanID,
                messageText: " padded answer "
            ),
            chatResponse(
                subjectID: insightScanID,
                messageText: String(repeating: "x", count: 4_001)
            ),
            chatResponse(
                subjectID: insightScanID,
                clientMessageID: "not-a-uuid"
            ),
            chatResponse(
                subjectID: insightScanID,
                dailySendLimit: 20,
                sendsRemainingToday: 21
            ),
            chatResponse(
                subjectID: insightScanID,
                dailySendLimit: 21,
                sendsRemainingToday: 19
            )
        ]
        for invalidResponse in invalidInsightResponses {
            fixture.transport.register(path: "/insight-chat") { _ in
                (response, invalidResponse)
            }
            await #expect(throws: MerianError.invalidResponse) {
                try await fixture.client
                    .loadInsightChat(scanId: insightScanID)
            }
        }

        fixture.transport.register(path: "/insight-chat") { _ in
            (
                response,
                chatResponse(
                    subjectID: insightScanID,
                    clientMessageID: requestID
                )
            )
        }
        await #expect(throws: MerianError.invalidResponse) {
            try await fixture.client.sendInsightChatMessage(
                scanId: insightScanID,
                messageText: "Which traits support this ID?",
                clientMessageId: requestID
            )
        }

        var oversizedResponse = completedSendResponse(
            subjectID: insightScanID,
            clientMessageID: requestID
        )
        oversizedResponse.append(
            Data(
                repeating: 0x20,
                count: 1_048_577 - oversizedResponse.count
            )
        )
        fixture.transport.register(path: "/insight-chat") { _ in
            (response, oversizedResponse)
        }
        await #expect(throws: MerianError.invalidResponse) {
            try await fixture.client.sendInsightChatMessage(
                scanId: insightScanID,
                messageText: "Which traits support this ID?",
                clientMessageId: requestID
            )
        }

        fixture.transport.register(path: "/explore-post-chat") { _ in
            (response, chatResponse(subjectID: otherSubjectID))
        }
        await #expect(throws: MerianError.invalidResponse) {
            try await fixture.client
                .loadExplorePostChat(postId: explorePostID)
        }

        fixture.transport.register(path: "/species-dictionary-chat") { _ in
            (response, chatResponse(subjectID: otherSubjectID))
        }
        await #expect(throws: MerianError.invalidResponse) {
            try await fixture.client
                .loadSpeciesDictionaryChat(speciesId: insightScanID)
        }
    }
}
