import Foundation
import os
import Testing

@testable import Merian

@Suite("Species Dictionary Chat Endpoints")
@MainActor
struct SpeciesDictionaryChatEndpointTests {
    @Test func testSpeciesDictionaryFieldChatUsesStrictSpeciesContract() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let speciesID = "019fb71d-0666-7afe-b6a2-2ece4a0fcc05"
        let conversationID = "019fb71d-0c6e-745e-9c2a-ac395aab0731"
        let requestID = "019fb71d-10ee-7114-be47-b551d9adee55"
        let messageID = "019fb71d-14be-7399-b29c-c28a613936c0"
        let sendProbe = OSAllocatedUnfairLock(initialState: [String?]())
        let responseURL = try #require(URL(string: "https://example.com"))
        let response = try #require(
            HTTPURLResponse(
                url: responseURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )

        fixture.transport.register(path: "/species-dictionary-chat") { request in
            #expect(request.httpMethod == "POST")
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            let action = try #require(payload["action"] as? String)
            #expect(payload["species_id"] as? String == speciesID)
            #expect(payload["scan_id"] == nil)
            #expect(payload["post_id"] == nil)
            #expect(
                request.value(forHTTPHeaderField: "Idempotency-Key") ==
                    (action == "send" ? requestID : nil)
            )

            let data: Data
            switch action {
            case "send":
                let attempt = sendProbe.withLock { keys in
                    keys.append(request.value(forHTTPHeaderField: "Idempotency-Key"))
                    return keys.count
                }
                if attempt == 1 {
                    let transientResponse = try #require(
                        HTTPURLResponse(
                            url: responseURL,
                            statusCode: 503,
                            httpVersion: nil,
                            headerFields: ["X-Merian-Handler": "1"]
                        )
                    )
                    return (
                        transientResponse,
                        Data(#"{"code":"service_unavailable"}"#.utf8)
                    )
                }
                #expect(payload["client_message_id"] as? String == requestID)
                #expect(
                    payload["message_text"] as? String ==
                        "Which habitat details matter most?"
                )
                data = Data(
                    """
                    {
                      "data": {
                        "subject_id": "\(speciesID)",
                        "conversation_id": "\(conversationID)",
                        "messages": [
                          {
                            "id": "019fb71d-18c5-74de-bd02-bac82916e93d",
                            "conversation_id": "\(conversationID)",
                            "scan_id": "\(speciesID)",
                            "role": "user",
                            "text": "Which habitat details matter most?",
                            "client_message_id": "\(requestID)",
                            "model": null,
                            "is_refusal": false,
                            "refusal_reason": null,
                            "created_at": "2026-08-20T20:00:00.000Z"
                          },
                          {
                            "id": "019fb71d-1c80-7f2b-9f36-2aa6f91a6933",
                            "conversation_id": "\(conversationID)",
                            "scan_id": "\(speciesID)",
                            "role": "assistant",
                            "text": "It is associated with shallow freshwater wetlands.",
                            "client_message_id": "\(requestID)",
                            "model": "gemini-2.5-flash",
                            "is_refusal": false,
                            "refusal_reason": null,
                            "created_at": "2026-08-20T20:00:01.000Z"
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
            case "feedback":
                #expect(payload["message_id"] as? String == messageID)
                #expect(payload["feedback_rating"] as? String == "helpful")
                data = Data(
                    """
                    {
                      "data": {
                        "ok": true,
                        "subject_id": "\(speciesID)",
                        "message_id": "\(messageID)",
                        "rating": "helpful"
                      }
                    }
                    """.utf8
                )
            case "suggest_prompts":
                data = Data(
                    """
                    {
                      "data": {
                        "subject_id": "\(speciesID)",
                        "conversation_id": "\(conversationID)",
                        "prompts": [
                          {
                            "text": "What habitat does this species prefer?",
                            "category": "habitat"
                          }
                        ]
                      }
                    }
                    """.utf8
                )
            case "load", "delete":
                data = Data(
                    """
                    {
                      "data": {
                        "subject_id": "\(speciesID)",
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
            default:
                throw MerianError.invalidResponse
            }
            return (response, data)
        }

        let loaded = try await fixture.client
            .loadSpeciesDictionaryChat(speciesId: speciesID)
        #expect(loaded.subjectId == speciesID)

        let sent = try await fixture.client
            .sendSpeciesDictionaryChatMessage(
                speciesId: speciesID,
                messageText: "Which habitat details matter most?",
                clientMessageId: requestID
            )
        #expect(sent.messages.count == 2)
        #expect(sent.messages.allSatisfy { $0.scanId == speciesID })
        #expect(sendProbe.withLock { $0.count } == 2)
        #expect(sendProbe.withLock { $0 } == [requestID, requestID])

        let feedback = try await fixture.client
            .submitSpeciesDictionaryChatFeedback(
                speciesId: speciesID,
                messageId: messageID,
                rating: .helpful
            )
        #expect(feedback.subjectId == speciesID)

        let prompts = try await fixture.client
            .suggestSpeciesDictionaryChatPrompts(speciesId: speciesID)
        #expect(prompts.prompts.map(\.category) == ["habitat"])

        let deleted = try await fixture.client
            .deleteSpeciesDictionaryChat(speciesId: speciesID)
        #expect(deleted.messages.isEmpty)
    }
}
