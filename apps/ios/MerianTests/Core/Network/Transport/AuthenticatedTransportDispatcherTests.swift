import Foundation
import Testing

@testable import Merian

@Suite("Authenticated Transport Dispatcher")
struct AuthenticatedTransportDispatcherTests {
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
        var allowed = true
        let authorization = IdentificationDispatchAuthorization(recipient: .openAI) {
            if !allowed { throw MerianError.openAIConsentRequired }
        }
        let body = Data("{}".utf8)
        let request = try await dispatcher.makeAuthenticatedJSONRequest(
            url: #require(URL(string: "https://example.supabase.co/functions/v1/identify")),
            bodyData: body, expectedAuthUserID: userID,
            identificationAuthorization: authorization)
        #expect(request.value(forHTTPHeaderField: IdentificationRecipientExpectation.header) == "openai")
        #expect(request.value(forHTTPHeaderField: IdentificationDispatchAuthorization.protocolHeader) == "6")
        #expect(request.value(forHTTPHeaderField: "X-Merian-Entitlement-Protocol") == "3")
        allowed = false
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
