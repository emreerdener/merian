import Foundation
import Testing

@testable import Merian

@Suite("Authenticated Transport Dispatcher")
struct AuthenticatedTransportDispatcherTests {
    @Test(arguments: ["upload-observation-evidence", "upload-observation-audio", "upload-observation-video"])
    func liveAuthHeaderMergePreservesBinaryEndpoints(route: String) throws {
        let url = try #require(URL(string: "https://example.supabase.co/functions/v1/\(route)"))
        var request = URLRequest(url: url, timeoutInterval: 130)
        request.httpMethod = "POST"
        request.httpBody = Data([0, 0, 0, 2, 123, 125, 255, 216, 255])
        request.setValue("application/octet-stream", forHTTPHeaderField: "content-type")
        request.setValue("Bearer stale-test-session", forHTTPHeaderField: "Authorization")
        request.setValue("stale-test-key", forHTTPHeaderField: "apikey")
        request.setValue("stable-test-identity", forHTTPHeaderField: "Idempotency-Key")
        let merged = AuthenticatedTransportDispatcher.applyingValidatedAuthHeaders([
            "CONTENT-TYPE": "application/json", "Authorization": "Bearer fresh-test-session", "apikey": "fresh-test-key"
        ], to: request)
        #expect(merged.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
        #expect(merged.value(forHTTPHeaderField: "Authorization") == "Bearer fresh-test-session")
        #expect(merged.value(forHTTPHeaderField: "apikey") == "fresh-test-key")
        #expect(merged.value(forHTTPHeaderField: "Idempotency-Key") == "stable-test-identity")
        #expect(merged.httpBody == request.httpBody)
        #expect(merged.httpMethod == request.httpMethod)
        #expect(merged.url == request.url)
        #expect(merged.timeoutInterval == request.timeoutInterval)
    }

    @Test(arguments: [nil, "application/json", "application/json; charset=utf-8"] as [String?])
    func liveAuthHeaderMergeKeepsJSONCompatibility(contentType: String?) throws {
        let url = try #require(URL(string: "https://example.supabase.co/rest/v1/rpc/test"))
        var request = URLRequest(url: url)
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let merged = AuthenticatedTransportDispatcher.applyingValidatedAuthHeaders([
            "Content-Type": "application/json", "Authorization": "Bearer test-session"
        ], to: request)
        #expect(merged.value(forHTTPHeaderField: "Content-Type") == (contentType ?? "application/json"))
        #expect(merged.value(forHTTPHeaderField: "Authorization") == "Bearer test-session")
    }

    @Test func injectedIdentityBuildsExactAuthenticatedPayloadBoundary()
        async throws {
        let userID = UUID()
        let body = Data(#"{"scan_id":"scan-1"}"#.utf8)
        let (dispatcher, session) = makeDispatcher(userID: userID)
        defer { session.invalidateAndCancel() }
        let url = try #require(
            URL(string: "https://example.supabase.co/functions/v1/enrich-scan")
        )

        #expect(try await dispatcher.requestPayloadAuthUserID() == userID)
        let request = try await dispatcher.makeAuthenticatedJSONRequest(
            url: url,
            bodyData: body,
            timeoutInterval: 37,
            idempotencyKey: "stable-key",
            expectedAuthUserID: userID
        )

        #expect(request.url == url)
        #expect(request.httpMethod == "POST")
        #expect(request.httpBody == body)
        #expect(request.timeoutInterval == 37)
        #expect(
            request.value(forHTTPHeaderField: "Content-Type")
                == "application/json"
        )
        #expect(
            request.value(forHTTPHeaderField: "X-Merian-Entitlement-Protocol")
                == "3"
        )
        #expect(
            request.value(forHTTPHeaderField: "Idempotency-Key")
                == "stable-key"
        )
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: IdentificationRecipientExpectation.header) == nil)
    }

    @MainActor
    @Test func withdrawalBetweenPreparationAndDispatchNeverSendsBody() async throws {
        let allowed = MainActorTestValue(true)
        let userID = UUID()
        let transport = ScopedMockTransport()
        let session = transport.makeSession()
        defer { session.invalidateAndCancel() }
        transport.register(path: "/identify") { _ in
            Issue.record("Withdrawn permission reached network dispatch")
            throw URLError(.badServerResponse)
        }
        let pinned = PinnedNetworkTransport()
        pinned.overridingSession = session
        let dispatcher = AuthenticatedTransportDispatcher(sessionTransport: pinned)
        dispatcher.overridingAuthUserID = userID

        let authorization = IdentificationDispatchAuthorization(recipient: .openAI) {
            if !allowed.value { throw MerianError.openAIConsentRequired }
        }
        let body = Data("{}".utf8)
        let request = try await dispatcher.makeAuthenticatedJSONRequest(
            url: #require(URL(string: "https://example.supabase.co/functions/v1/identify")),
            bodyData: body, expectedAuthUserID: userID,
            identificationAuthorization: authorization)
        #expect(request.value(forHTTPHeaderField: IdentificationRecipientExpectation.header) == "openai")
        #expect(request.value(forHTTPHeaderField: IdentificationDispatchAuthorization.protocolHeader) == "6")
        #expect(request.value(forHTTPHeaderField: "X-Merian-Entitlement-Protocol") == "3")
        allowed.value = false
        await #expect(throws: MerianError.openAIConsentRequired) {
            try await dispatcher.perform(.init(
                request: request, body: body, onRequestBodySent: nil,
                authTransitionOwner: nil, expectedAuthUserID: userID,
                identificationAuthorization: authorization))
        }
    }

    private func makeDispatcher(userID: UUID)
        -> (AuthenticatedTransportDispatcher, URLSession) {
        let configuration = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: configuration)
        let transport = PinnedNetworkTransport()
        transport.overridingSession = session
        let dispatcher = AuthenticatedTransportDispatcher(
            sessionTransport: transport
        )
        dispatcher.overridingAuthUserID = userID
        return (dispatcher, session)
    }
}
