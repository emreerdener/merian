import Foundation
import os
import Testing
@testable import Merian

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct CapturePrimaryTransportTests {
    private func plan() throws -> CaptureInitialEvidencePlan {
        let source = try DatabaseActorTestSupport.loadRepositorySource(at: "services/supabase/functions/_shared/analysisHistory/fixtures/capture-plans-v1.json")
        let fixtures = try #require(JSONSerialization.jsonObject(with: Data(source.utf8)) as? [[String: Any]])
        let fixture = try #require(fixtures.first { $0["name"] as? String == "photo_audio" })
        return try .init(ownerID: ObservationHistoryPage.uuid(fixture["owner_id"]),
            data: JSONSerialization.data(withJSONObject: fixture["plan"]!))
    }
    private func request(_ plan: CaptureInitialEvidencePlan, authorize: @escaping @MainActor @Sendable () throws -> Void = {}) -> AuthenticatedInferenceRequest {
        var request = URLRequest(url: URL(string: "https://example.supabase.co/functions/v1/identify-multimodal")!)
        request.httpMethod = "POST"; request.httpBody = Data("{}".utf8)
        request.setValue(plan.scanID.uuidString.lowercased(), forHTTPHeaderField: "Idempotency-Key")
        return .init(request: request, expectedAuthUserID: plan.ownerID,
            identificationAuthorization: .init(recipient: .gemini, validate: authorize))
    }

    @Test(arguments: ["success", "lost", "401", "503", "mime", "oversize", "save", "consent", "owner", "late_consent", "late_owner"])
    func sendsOnlyAfterPositiveReservationAndNeverRetries(fault: String) async throws {
        let plan = try plan(), f = InitialPhotoAllocationTransportTests.Fixture(ownerID: plan.ownerID)
        defer { f.close() }
        if fault == "owner" { f.dispatcher.overridingAuthUserID = UUID() }
        let state = OSAllocatedUnfairLock(initialState: (reserved: false, calls: 0))
        let bytes = fault == "oversize" ? Data(repeating: 32, count: OrdinaryInferenceCompletion.maximumBytes + 1) : Data("{}".utf8)
        f.mock.register(path: "/identify-multimodal") { request in
            state.withLock { value in #expect(value.reserved); value.calls += 1 }
            #expect(request.timeoutInterval == CapturePrimaryTransport.requestSeconds)
            if fault == "lost" { throw URLError(.networkConnectionLost) }
            return (HTTPURLResponse(url: request.url!, statusCode: Int(fault) ?? 200, httpVersion: nil,
                headerFields: ["Content-Type": fault == "mime" ? "text/plain" : "application/json"])!, bytes)
        }
        let request = request(plan) {
            if fault == "consent" || (fault == "late_consent" && state.withLock { $0.reserved }) {
                throw SharedMediaStorageFailure.closed
            }
        }
        let transport = CapturePrimaryTransport(baseURL: "https://example.supabase.co", dispatcher: f.dispatcher)
        var reservations = 0
        let send = {
            try await transport.submit(request, plan: plan, validate: {}) {
                reservations += 1
                if fault == "save" { throw SharedMediaStorageFailure.unavailable }
                state.withLock { $0.reserved = true }
                if fault == "late_owner" { f.dispatcher.overridingAuthUserID = UUID() }
            }
        }
        if fault == "success" { #expect(try await send() == bytes) } else {
            await #expect(throws: (any Error).self) { try await send() }
        }
        #expect(reservations == (["consent", "owner"].contains(fault) ? 0 : 1))
        #expect(state.withLock { $0.calls } == (["save", "consent", "owner", "late_consent", "late_owner"].contains(fault) ? 0 : 1))
    }
}
