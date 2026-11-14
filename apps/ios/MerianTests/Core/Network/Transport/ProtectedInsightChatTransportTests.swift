import Foundation
@testable import Merian
import os
import Testing

@MainActor
@Suite("Protected Insight Chat Transport")
struct ProtectedInsightChatTransportTests {
    func request() throws -> ProtectedInsightChatRequest {
        try .init(observationID: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
            conversationID: UUID(uuidString: "00000000-0000-4000-8000-000000000004")!,
            clientMessageID: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!, messageText: "Synthetic question",
            selection: .init(analysisID: UUID(), stateRevision: 10, reviewRevision: 2))
    }
    func receipt(_ request: ProtectedInsightChatRequest) throws -> Data {
        try ProtectedInsightChatClaimsTests().receipt(.init(request: request, ownerID: UUID()))
    }

    @Test func exactRequestUsesScopedBudgetAndValidatedReceiptWithoutReplayHeaders() async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let request = try request(), data = try receipt(request), body = try request.encoded()
        let count = OSAllocatedUnfairLock(initialState: 0)
        fixture.transport.register(path: "/insight-chat") { wire in
            count.withLock { $0 += 1 }
            #expect(MockURLProtocol.bodyData(for: wire) == body)
            #expect(wire.timeoutInterval == 145)
            #expect(wire.cachePolicy == .reloadIgnoringLocalCacheData)
            #expect(wire.value(forHTTPHeaderField: "Idempotency-Key") == nil)
            return (HTTPURLResponse(url: wire.url!, statusCode: 200, httpVersion: nil,
                                    headerFields: ["Content-Type": "application/json"])!, data)
        }
        var attempts = 0, responses = 0
        let reply = try await fixture.client.sendProtectedInsightChat(request, ownerID: fixture.client.overridingAuthUserID!,
            claimExpiresAt: Date().addingTimeInterval(180), validateAttempt: { attempts += 1 }, validateResponse: { responses += 1 })
        guard case .assistantCompletion(let receipt) = reply.outcome else { Issue.record("Expected assistant receipt"); return }
        #expect(receipt.message.text == "Synthetic answer")
        #expect(reply.data == data)
        #expect(try ProtectedInsightChatIntent(request: request, ownerID: fixture.client.overridingAuthUserID!)
            .accepting(reply.data, at: Date()).isComplete)
        #expect(attempts == 1 && responses == 1 && count.withLock { $0 } == 1)
        #expect(PinnedNetworkTransport.makeConfiguration().timeoutIntervalForResource == 90)
    }

    @Test(arguments: [401, 404, 429, 500, 503])
    func failuresNeverRefreshOrRetry(status: Int) async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let count = OSAllocatedUnfairLock(initialState: 0)
        fixture.client.overridingAuthSessionRefresh = { Issue.record("Must not refresh"); return true }
        fixture.transport.register(path: "/insight-chat") { wire in
            count.withLock { $0 += 1 }
            return (HTTPURLResponse(url: wire.url!, statusCode: status, httpVersion: nil, headerFields: [:])!, Data("{}".utf8))
        }
        await #expect(throws: (any Error).self) {
            try await fixture.client.sendProtectedInsightChat(request(), ownerID: fixture.client.overridingAuthUserID!,
                claimExpiresAt: Date().addingTimeInterval(180), validateAttempt: {}, validateResponse: {})
        }
        #expect(count.withLock { $0 } == 1)
    }

    @Test(arguments: ["claim", "owner", "budget", "post-auth-budget"])
    func invalidAdmissionNeverSends(reason: String) async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        fixture.transport.register(path: "/insight-chat") { _ in Issue.record("Denied send"); throw URLError(.badServerResponse) }
        let expiry = Date().addingTimeInterval(reason == "budget" ? 160 : (reason == "post-auth-budget" ? 162.02 : 180))
        await #expect(throws: (any Error).self) {
            try await fixture.client.sendProtectedInsightChat(request(), ownerID: reason == "owner" ? UUID() : fixture.client.overridingAuthUserID!,
                claimExpiresAt: expiry, validateAttempt: {
                    if reason == "claim" { throw MerianError.invalidResponse }
                    if reason == "post-auth-budget" { Thread.sleep(forTimeInterval: 0.03) }
                }, validateResponse: {})
        }
    }

    @Test func staleResponseNeverReturnsReceipt() async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let request = try request(), data = try receipt(request)
        fixture.transport.register(path: "/insight-chat") { wire in
            (HTTPURLResponse(url: wire.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, data)
        }
        await #expect(throws: MerianError.invalidResponse) {
            try await fixture.client.sendProtectedInsightChat(request, ownerID: fixture.client.overridingAuthUserID!,
                claimExpiresAt: Date().addingTimeInterval(180), validateAttempt: {}, validateResponse: { throw MerianError.invalidResponse })
        }
    }

    @Test(arguments: [false, true])
    func oversizedActualBodyOrDeclaredLengthFails(claimedLength: Bool) async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        fixture.transport.register(path: "/insight-chat") { wire in
            (HTTPURLResponse(url: wire.url!, statusCode: 200, httpVersion: nil,
                             headerFields: claimedLength ? ["Content-Length": "32769", "Content-Type": "application/json"] : ["Content-Type": "application/json"])!,
             Data(repeating: 32, count: claimedLength ? 1 : 32_769))
        }
        await #expect(throws: (any Error).self) {
            try await fixture.client.sendProtectedInsightChat(request(), ownerID: fixture.client.overridingAuthUserID!,
                claimExpiresAt: Date().addingTimeInterval(180), validateAttempt: {}, validateResponse: {})
        }
    }

    @Test(arguments: ["text/html", ""])
    func successRequiresJSONBeforeAcceptingBody(mime: String) async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let request = try request(), data = try receipt(request)
        fixture.transport.register(path: "/insight-chat") { wire in
            (HTTPURLResponse(url: wire.url!, statusCode: 200, httpVersion: nil,
                             headerFields: mime.isEmpty ? [:] : ["Content-Type": mime])!, data)
        }
        await #expect(throws: MerianError.invalidResponse) {
            try await fixture.client.sendProtectedInsightChat(request, ownerID: fixture.client.overridingAuthUserID!,
                claimExpiresAt: Date().addingTimeInterval(180), validateAttempt: {},
                validateResponse: { Issue.record("Invalid MIME crossed raw transport") })
        }
    }

    @Test func transportErrorsNeverRetry() async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let count = OSAllocatedUnfairLock(initialState: 0)
        fixture.transport.register(path: "/insight-chat") { _ in
            count.withLock { $0 += 1 }; throw URLError(.networkConnectionLost)
        }
        await #expect(throws: (any Error).self) {
            try await fixture.client.sendProtectedInsightChat(request(), ownerID: fixture.client.overridingAuthUserID!,
                claimExpiresAt: Date().addingTimeInterval(180), validateAttempt: {}, validateResponse: {})
        }
        #expect(count.withLock { $0 } == 1)
    }

    @Test func incrementalUnknownLengthCannotExceedBound() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProtectedChatChunksProtocol.self]
        let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
        let request = URLRequest(url: URL(string: "https://example.supabase.co/chunks")!)
        await #expect(throws: MerianError.invalidResponse) {
            try await ProtectedInsightChatDataTask().response(using: session, request: request, timeout: 1)
        }
    }

    @Test func collectorRejectsExpiredStartAndRedirect() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProtectedChatHangingProtocol.self]
        let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
        let request = URLRequest(url: URL(string: "https://example.supabase.co/hang")!)
        await #expect(throws: (any Error).self) {
            try await ProtectedInsightChatDataTask().response(using: session, request: request,
                timeout: 1, claimExpiresAt: Date().addingTimeInterval(160))
        }
        let collector = PinnedBoundedJSONDataTask(maximumBytes: 32_768), task = session.dataTask(with: request)
        let denied = OSAllocatedUnfairLock(initialState: false)
        collector.urlSession(session, task: task,
            willPerformHTTPRedirection: HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil, headerFields: [:])!,
            newRequest: URLRequest(url: URL(string: "https://other.example/target")!)) { next in
            #expect(next == nil); denied.withLock { $0 = true }
        }
        #expect(denied.withLock { $0 })
        task.cancel()
    }

    @Test func accountSwitchAfterResponseWithholdsReceipt() async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let request = try request(), data = try receipt(request), owner = fixture.client.overridingAuthUserID!
        fixture.transport.register(path: "/insight-chat") { wire in
            fixture.client.overridingAuthUserID = UUID()
            return (HTTPURLResponse(url: wire.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!, data)
        }
        await #expect(throws: (any Error).self) {
            try await fixture.client.sendProtectedInsightChat(request, ownerID: owner,
                claimExpiresAt: Date().addingTimeInterval(180), validateAttempt: {}, validateResponse: {})
        }
    }

    @Test func streamingCollectorHonorsDeadlineAndCancellation() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProtectedChatHangingProtocol.self]
        let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
        let request = URLRequest(url: URL(string: "https://example.supabase.co/hang")!)
        let start = Date()
        await #expect(throws: (any Error).self) {
            try await ProtectedInsightChatDataTask().response(using: session, request: request, timeout: 0.03)
        }
        let task = Task { try await ProtectedInsightChatDataTask().response(using: session, request: request) }
        task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(Date().timeIntervalSince(start) < 2)
    }
}

private class ProtectedChatHangingProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
}

private class ProtectedChatChunksProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(repeating: 32, count: 16_384))
        client?.urlProtocol(self, didLoad: Data(repeating: 32, count: 16_384))
        client?.urlProtocol(self, didLoad: Data([32]))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
