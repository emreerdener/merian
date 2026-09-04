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
