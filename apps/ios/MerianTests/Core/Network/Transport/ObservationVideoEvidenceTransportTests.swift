import CryptoKit
import Foundation
@testable import Merian
import os
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationVideoEvidenceTransportTests {
    static let path = "/upload-observation-video"
    let owner = UUID(uuidString: "00000000-0000-4000-8000-000000000090")!

    private func wire() throws -> ObservationVideoEvidenceWireRequest {
        let source = try DatabaseActorTestSupport.loadRepositorySource(at: "services/supabase/functions/_shared/analysisHistory/fixtures/video-request-v4.json")
        let vectors = try #require(JSONSerialization.jsonObject(with: Data(source.utf8)) as? [[String: Any]])
        let input = try #require(vectors.first?["input"] as? [String: Any])
        let original = try ObservationVideoReanalysisRequest(savedBody: JSONSerialization.data(withJSONObject: input))
        var manifest = try #require(input["evidence_manifest"] as? [String: Any])
        var graph = try #require(manifest["provenance"] as? [String: Any])
        var clip = try #require(graph["source"] as? [String: Any])
        let bytes = Data(repeating: 42, count: original.manifest.provenance.source.byteCount)
        clip["sha256"] = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        graph["source"] = clip; manifest["provenance"] = graph
        let video = try ObservationVideoReanalysisRequest(observationID: original.observationID, analysisID: original.analysisID,
            sourceAnalysisID: original.sourceAnalysisID, manifestBytes: JSONSerialization.data(withJSONObject: manifest))
        return try .init(candidate: .init(video: video), mediaID: original.manifest.provenance.source.mediaID, bytes: bytes)
    }
    private func receipt(_ wire: ObservationVideoEvidenceWireRequest) throws -> [String: Any] {
        var row = try #require(JSONSerialization.jsonObject(with: wire.request.body) as? [String: Any])
        var items = try #require(row["items"] as? [[String: Any]])
        for index in items.indices {
            items[index]["object_id"] = UUID().uuidString.lowercased()
            items[index]["ready_at"] = index == 0 ? "2026-10-10T00:00:00.000Z" : NSNull()
        }
        row["items"] = items; row["owner_id"] = owner.uuidString.lowercased()
        row["state"] = "allocated"; row["expires_at"] = "2026-10-11T00:00:00.000Z"
        return row
    }

    @Test func exactSingleUploadAndKnownSettlement() async throws {
        let f = try ObservationSourceTransportTests.Fixture(); defer { f.close() }
        f.dispatcher.overridingAuthUserID = owner
        let wire = try wire(), row = try receipt(wire), data = try JSONSerialization.data(withJSONObject: row)
        let calls = OSAllocatedUnfairLock(initialState: 0)
        f.mock.register(path: Self.path) { request in
            calls.withLock { $0 += 1 }
            #expect(MockURLProtocol.bodyData(for: request) == wire.body)
            #expect(request.httpMethod == "POST" && request.timeoutInterval == 130)
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            #expect(request.value(forHTTPHeaderField: "X-Merian-Entitlement-Protocol") == "3")
            #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == nil)
            #expect(request.value(forHTTPHeaderField: IdentificationRecipientExpectation.header) == nil)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, data)
        }
        var attempts = 0, settlements = 0
        let transport = ObservationVideoEvidenceTransport(baseURL: "https://example.supabase.co", dispatcher: f.dispatcher)
        let task = Task { @MainActor in
            try await transport.upload(wire, ownerID: owner, validateAttempt: { attempts += 1 },
                validateResponse: { settlements += 1; withUnsafeCurrentTask { $0?.cancel() } })
        }
        #expect(try await task.value.data == data)
        #expect(calls.withLock { $0 } == 1 && attempts == 1 && settlements == 1)
        #expect(PinnedNetworkTransport.makeConfiguration().timeoutIntervalForResource == 90)
    }

    @Test(arguments: ["lost", "401", "404", "409", "503", "mime", "actual", "declared", "owner", "unready", "rollback", "settlement"])
    func invalidOrUncertainAnswersNeverRetry(kind: String) async throws {
        let f = try ObservationSourceTransportTests.Fixture(); defer { f.close() }
        f.dispatcher.overridingAuthUserID = owner
        f.dispatcher.overridingAuthSessionRefresh = { Issue.record("Unexpected upload Auth retry"); return true }
        let wire = try wire(), original = try receipt(wire)
        let prior = try ObservationVideoEvidenceReceipt(data: JSONSerialization.data(withJSONObject: original), request: wire.request, ownerID: owner)
        var row = original
        if kind == "owner" { row["owner_id"] = UUID().uuidString.lowercased() }
        if kind == "unready" || kind == "rollback" {
            var items = try #require(row["items"] as? [[String: Any]])
            items[0]["ready_at"] = NSNull(); row["items"] = items
        }
        let data = kind == "actual" ? Data(repeating: 32, count: 8193) : try JSONSerialization.data(withJSONObject: row)
        var headers = ["Content-Type": kind == "mime" ? "text/plain" : "application/json"]
        if kind == "declared" { headers["Content-Length"] = "8193" }
        let frozenHeaders = headers, calls = OSAllocatedUnfairLock(initialState: 0)
        f.mock.register(path: Self.path) { request in
            calls.withLock { $0 += 1 }
            if kind == "lost" { throw URLError(.networkConnectionLost) }
            return (HTTPURLResponse(url: request.url!, statusCode: Int(kind) ?? 200, httpVersion: nil, headerFields: frozenHeaders)!, data)
        }
        let transport = ObservationVideoEvidenceTransport(baseURL: "https://example.supabase.co", dispatcher: f.dispatcher)
        await #expect(throws: (any Error).self) {
            try await transport.upload(wire, ownerID: owner, previous: kind == "rollback" ? prior : nil, validateAttempt: {},
                validateResponse: { if kind == "settlement" { throw MerianError.invalidResponse } })
        }
        #expect(calls.withLock { $0 } == 1)
    }

    @Test(arguments: ["owner", "claim", "cancel", "prior"])
    func staleScopeNeverSends(kind: String) async throws {
        let f = try ObservationSourceTransportTests.Fixture(); defer { f.close() }
        f.dispatcher.overridingAuthUserID = kind == "owner" ? UUID() : owner
        let wire = try wire()
        let prior = try ObservationVideoEvidenceReceipt(data: JSONSerialization.data(withJSONObject: receipt(wire)), request: wire.request, ownerID: owner)
        f.mock.register(path: Self.path) { _ in Issue.record("Stale upload sent"); throw MerianError.invalidResponse }
        let transport = ObservationVideoEvidenceTransport(baseURL: "https://example.supabase.co", dispatcher: f.dispatcher)
        let task = Task { @MainActor in
            if kind == "cancel" { withUnsafeCurrentTask { $0?.cancel() } }
            return try await transport.upload(wire, ownerID: kind == "prior" ? UUID() : owner, previous: kind == "prior" ? prior : nil,
                validateAttempt: { if kind == "claim" { throw MerianError.invalidResponse } }, validateResponse: {})
        }
        await #expect(throws: (any Error).self) { try await task.value }
    }
}
