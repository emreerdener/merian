import Foundation
@testable import Merian
import os
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct CaptureStageTransportTests {
    private func wire() throws -> CaptureStageWireRequest {
        let source = try DatabaseActorTestSupport.loadRepositorySource(at: "services/supabase/functions/_shared/analysisHistory/fixtures/capture-plans-v1.json")
        let fixtures = try #require(JSONSerialization.jsonObject(with: Data(source.utf8)) as? [[String: Any]])
        let fixture = try #require(fixtures.first { $0["name"] as? String == "two_audio" })
        var plan = try #require(fixture["plan"] as? [String: Any])
        var items = try #require(plan["items"] as? [[String: Any]])
        var artifact = try #require(items[0]["source"] as? [String: Any])
        let bytes = Data(repeating: 42, count: 46)
        artifact["sha256"] = SharedMediaAcquisitionEncoding.digest(bytes); artifact["byte_count"] = bytes.count
        items[0]["source"] = artifact; plan["items"] = items
        let value = try CaptureInitialEvidencePlan(ownerID: ObservationHistoryPage.uuid(fixture["owner_id"]), data: JSONSerialization.data(withJSONObject: plan))
        return try .init(plan: value, mediaID: ObservationHistoryPage.uuid(artifact["media_id"]), bytes: bytes)
    }
    private func row(_ wire: CaptureStageWireRequest) -> [String: Any] {
        ["schema_version": 1, "scan_id": wire.plan.scanID.uuidString.lowercased(),
         "generation": wire.plan.generation.uuidString.lowercased(), "media_id": wire.mediaID.uuidString.lowercased(),
         "request_sha256": String(repeating: "a", count: 64), "ready": true]
    }

    @Test func exactWireAndSettlementWithoutProviderAuthority() async throws {
        let f = try ObservationSourceTransportTests.Fixture(); defer { f.close() }
        let wire = try wire(); f.dispatcher.overridingAuthUserID = wire.plan.ownerID
        let reply = try JSONSerialization.data(withJSONObject: row(wire))
        let calls = OSAllocatedUnfairLock(initialState: 0)
        f.mock.register(path: "/upload-capture-stage") { request in
            calls.withLock { $0 += 1 }
            #expect(MockURLProtocol.bodyData(for: request) == wire.body)
            #expect(request.timeoutInterval == 130 && request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
            #expect(request.value(forHTTPHeaderField: IdentificationRecipientExpectation.header) == nil)
            #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == nil)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, reply)
        }
        let length = wire.body.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        let metadata = try #require(JSONSerialization.jsonObject(with: wire.body.subdata(in: 4..<(4 + length))) as? [String: Any])
        #expect(Set(metadata.keys) == ["schema_version", "plan", "media_id"])
        #expect(wire.body.suffix(46) == Data(repeating: 42, count: 46))
        var attempts = 0, settlements = 0
        let transport = CaptureStageTransport(baseURL: "https://example.supabase.co", dispatcher: f.dispatcher)
        let receipt = try await transport.upload(wire, validateAttempt: { attempts += 1 }, validateResponse: { settlements += 1 })
        try receipt.requirePlan(wire.plan)
        #expect(calls.withLock { $0 } == 1 && attempts == 1 && settlements == 1)
        #expect(PinnedNetworkTransport.makeConfiguration().timeoutIntervalForResource == 90)
    }

    @Test(arguments: ["lost", "401", "404", "409", "503", "mime", "oversize", "unready", "numeric_ready", "media", "generation", "hash", "extra", "settlement"])
    func invalidOrUnknownReplyDoesNotRetry(kind: String) async throws {
        let f = try ObservationSourceTransportTests.Fixture(); defer { f.close() }
        let wire = try wire(); f.dispatcher.overridingAuthUserID = wire.plan.ownerID
        f.dispatcher.overridingAuthSessionRefresh = { Issue.record("Unexpected Auth retry"); return true }
        var reply = row(wire)
        switch kind {
        case "unready": reply["ready"] = false
        case "numeric_ready": reply["ready"] = 1
        case "media": reply["media_id"] = UUID().uuidString.lowercased()
        case "generation": reply["generation"] = UUID().uuidString.lowercased()
        case "hash": reply["request_sha256"] = "invalid"
        case "extra": reply["authority"] = "release"
        default: break
        }
        let bytes = kind == "oversize" ? Data(repeating: 32, count: 1025) : try JSONSerialization.data(withJSONObject: reply)
        let calls = OSAllocatedUnfairLock(initialState: 0)
        f.mock.register(path: "/upload-capture-stage") { request in
            calls.withLock { $0 += 1 }
            if kind == "lost" { throw URLError(.networkConnectionLost) }
            return (HTTPURLResponse(url: request.url!, statusCode: Int(kind) ?? 200, httpVersion: nil,
                headerFields: ["Content-Type": kind == "mime" ? "text/plain" : "application/json"])!, bytes)
        }
        let transport = CaptureStageTransport(baseURL: "https://example.supabase.co", dispatcher: f.dispatcher)
        await #expect(throws: (any Error).self) {
            try await transport.upload(wire, validateAttempt: {}, validateResponse: { if kind == "settlement" { throw MerianError.invalidResponse } })
        }
        #expect(calls.withLock { $0 } == 1)
    }

    @Test(arguments: ["account", "attempt", "prior"])
    func staleOwnershipNeverSends(kind: String) async throws {
        let f = try ObservationSourceTransportTests.Fixture(); defer { f.close() }
        let wire = try wire(); f.dispatcher.overridingAuthUserID = kind == "account" ? UUID() : wire.plan.ownerID
        f.mock.register(path: "/upload-capture-stage") { _ in Issue.record("Unexpected stale upload"); throw MerianError.invalidResponse }
        let priorWire = try self.wire()
        var previous: CaptureStageReceipt?
        if kind == "prior" {
            let other = try CaptureInitialEvidencePlan(ownerID: UUID(), scanID: priorWire.plan.scanID, generation: priorWire.plan.generation, items: priorWire.plan.items)
            let otherWire = try CaptureStageWireRequest(plan: other, mediaID: priorWire.mediaID, bytes: Data(repeating: 42, count: 46))
            previous = try .init(data: JSONSerialization.data(withJSONObject: row(otherWire)), wire: otherWire)
        }
        let transport = CaptureStageTransport(baseURL: "https://example.supabase.co", dispatcher: f.dispatcher)
        await #expect(throws: (any Error).self) {
            try await transport.upload(wire, previous: previous, validateAttempt: { if kind == "attempt" { throw MerianError.invalidResponse } }, validateResponse: {})
        }
    }

    @Test func forgedBytesAndReservedServerAudioCannotUpload() throws {
        let wire = try wire()
        #expect(throws: (any Error).self) { try CaptureStageWireRequest(plan: wire.plan, mediaID: wire.mediaID, bytes: Data(repeating: 43, count: 46)) }
        guard case let .audio(audio) = wire.plan.items[0] else { Issue.record("Expected audio"); return }
        #expect(throws: (any Error).self) { try CaptureStageWireRequest(plan: wire.plan, mediaID: audio.preparedMediaID, bytes: Data(repeating: 42, count: 46)) }
        var reply = row(wire); reply["request_sha256"] = String(repeating: "b", count: 64)
        let previous = try CaptureStageReceipt(data: JSONSerialization.data(withJSONObject: row(wire)), wire: wire)
        #expect(throws: (any Error).self) { try CaptureStageReceipt(data: JSONSerialization.data(withJSONObject: reply), wire: wire, previous: previous) }
    }
}
