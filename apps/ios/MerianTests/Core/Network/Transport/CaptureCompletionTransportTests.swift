import Foundation
import os
import Testing
@testable import Merian

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct CaptureCompletionTransportTests {
    private func plan() throws -> CaptureInitialEvidencePlan {
        let source = try DatabaseActorTestSupport.loadRepositorySource(at: "services/supabase/functions/_shared/analysisHistory/fixtures/capture-plans-v1.json")
        let fixtures = try #require(JSONSerialization.jsonObject(with: Data(source.utf8)) as? [[String: Any]])
        let fixture = try #require(fixtures.first { $0["name"] as? String == "photo_audio" })
        return try .init(ownerID: ObservationHistoryPage.uuid(fixture["owner_id"]),
            data: JSONSerialization.data(withJSONObject: fixture["plan"]!))
    }
    private func row(_ plan: CaptureInitialEvidencePlan, held: Bool = true) -> [String: Any] {
        ["version": 1, "phase": "capture-completion", "owner_id": plan.ownerID.uuidString.lowercased(),
         "scan_id": plan.scanID.uuidString.lowercased(), "generation": plan.generation.uuidString.lowercased(),
         "status": held ? "held" : "completed", "completion": held ? NSNull() : [
            "initial_evidence": ["schema_version": 1, "owner_id": plan.ownerID.uuidString.lowercased(),
                "scan_id": plan.scanID.uuidString.lowercased(), "generation": plan.generation.uuidString.lowercased(),
                "evidence_digest": String(repeating: "a", count: 64)]
         ] as Any]
    }

    @Test(arguments: [true, false]) func recoversOnlyExactIdentity(held: Bool) async throws {
        let plan = try plan(), f = InitialPhotoAllocationTransportTests.Fixture(ownerID: plan.ownerID)
        defer { f.close() }
        let body = try CaptureCompletionTransport.request(plan)
        let reply = try JSONSerialization.data(withJSONObject: row(plan, held: held))
        let calls = OSAllocatedUnfairLock(initialState: 0)
        f.mock.register(path: "/check-scan-status") { request in
            calls.withLock { $0 += 1 }
            #expect(MockURLProtocol.bodyData(for: request) == body)
            #expect(request.httpMethod == "POST" && request.timeoutInterval == 5)
            #expect(request.value(forHTTPHeaderField: "X-Merian-Initial-Recovery") == "capture-completion-v1")
            #expect(request.value(forHTTPHeaderField: IdentificationRecipientExpectation.header) == nil)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, reply)
        }
        let result = try await CaptureCompletionTransport(baseURL: "https://example.supabase.co", dispatcher: f.dispatcher).recover(plan, validate: {})
        #expect((result == nil) == held)
        #expect(calls.withLock { $0 } == 1)
    }

    @Test(arguments: ["owner", "scan", "generation", "phase", "version", "extra", "missing", "held_object", "completed_null", "proof_owner"])
    func rejectsAmbiguousOrForeignReceipt(fault: String) throws {
        let plan = try plan()
        var reply = row(plan, held: fault != "proof_owner")
        switch fault {
        case "owner": reply["owner_id"] = UUID().uuidString.lowercased()
        case "scan": reply["scan_id"] = UUID().uuidString.lowercased()
        case "generation": reply["generation"] = UUID().uuidString.lowercased()
        case "phase": reply["phase"] = "completion"
        case "version": reply["version"] = true
        case "extra": reply["may_dispatch"] = true
        case "missing": reply.removeValue(forKey: "completion")
        case "held_object": reply["completion"] = [:] as [String: String]
        case "completed_null": reply["status"] = "completed"
        case "proof_owner":
            var completion = try #require(reply["completion"] as? [String: Any])
            var proof = try #require(completion["initial_evidence"] as? [String: Any])
            proof["owner_id"] = UUID().uuidString.lowercased(); completion["initial_evidence"] = proof; reply["completion"] = completion
        default: Issue.record("Unknown fault")
        }
        let data = try JSONSerialization.data(withJSONObject: reply)
        #expect(throws: (any Error).self) { try CaptureCompletionTransport.decode(data, plan: plan) }
    }

    @Test(arguments: ["owner", "attempt", "lost", "401", "503", "mime", "oversize"])
    func failureDoesNotRefreshRetryOrIdentify(fault: String) async throws {
        let plan = try plan(), f = InitialPhotoAllocationTransportTests.Fixture(ownerID: plan.ownerID)
        defer { f.close() }
        if fault == "owner" { f.dispatcher.overridingAuthUserID = UUID() }
        f.dispatcher.overridingAuthSessionRefresh = { Issue.record("Unexpected recovery retry"); return true }
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let bytes = fault == "oversize" ? Data(repeating: 32, count: CaptureCompletionTransport.maximumResponseBytes + 1)
            : try JSONSerialization.data(withJSONObject: row(plan))
        f.mock.register(path: "/check-scan-status") { request in
            calls.withLock { $0 += 1 }
            if fault == "lost" { throw URLError(.networkConnectionLost) }
            return (HTTPURLResponse(url: request.url!, statusCode: Int(fault) ?? 200, httpVersion: nil,
                headerFields: ["Content-Type": fault == "mime" ? "text/plain" : "application/json"])!, bytes)
        }
        let transport = CaptureCompletionTransport(baseURL: "https://example.supabase.co", dispatcher: f.dispatcher)
        await #expect(throws: (any Error).self) {
            try await transport.recover(plan, validate: { if fault == "attempt" { throw SharedMediaStorageFailure.stale } })
        }
        #expect(calls.withLock { $0 } == (["owner", "attempt"].contains(fault) ? 0 : 1))
    }
}
