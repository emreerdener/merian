import Foundation
@testable import Merian
import Testing

@Suite("Private capture inference request")
struct PrivateCaptureInferenceRequestTests {
    static func plan(_ name: String = "photo_audio", owner: UUID? = nil) throws -> CaptureInitialEvidencePlan {
        let source = try DatabaseActorTestSupport.loadRepositorySource(at:
            "services/supabase/functions/_shared/analysisHistory/fixtures/capture-plans-v1.json")
        let fixtures = try #require(JSONSerialization.jsonObject(with: Data(source.utf8)) as? [[String: Any]])
        let fixture = try #require(fixtures.first { $0["name"] as? String == name })
        return try .init(ownerID: owner ?? ObservationHistoryPage.uuid(fixture["owner_id"]),
            data: JSONSerialization.data(withJSONObject: #require(fixture["plan"])))
    }

    private func body(_ plan: CaptureInitialEvidencePlan) throws -> Data {
        let frozen = try SharedMediaCaptureSubmissionContextTests.context(plan)
        return try InferencePayloadBuilder.privateCaptureBody(plan: plan, frozen: frozen,
            context: InferencePayloadBuilder.makeContext(userId: plan.ownerID.uuidString,
                telemetry: frozen.telemetry, defaultGeoprivacy: "private"))
    }

    @Test(arguments: ["two_photos", "two_audio", "photo_audio", "video_audio"])
    func wholePlanDefinesPreflightWithoutPublicMedia(_ name: String) throws {
        let plan = try Self.plan(name), data = try body(plan)
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let preflight = try IdentificationPreflightInput(body: data, function: "identify-multimodal")
        let profiles: [String: IdentificationPreflightInput.Profile] = [
            "two_photos": .photo, "two_audio": .audio, "photo_audio": .photoAudio, "video_audio": .videoAudio]
        #expect(preflight.inputProfile == profiles[name])
        #expect(!preflight.flashFallbackEligible)
        #expect(preflight.originalAnalysisID == plan.scanID)
        #expect(payload["user_id"] as? String == plan.ownerID.uuidString.lowercased())
        let roundTrip = try CaptureInitialEvidencePlan(ownerID: plan.ownerID,
            data: JSONSerialization.data(withJSONObject: #require(payload["capturePlan"])))
        #expect(roundTrip == plan)
        for key in ["imageBase64s", "audioBase64s", "r2ObjectKeys", "audioR2ObjectKeys", "videoR2ObjectKeys",
                    "initialEvidence", "privateCaptureStage", "observation_contexts"] {
            #expect(payload[key] == nil)
        }
    }

    @Test func privatePlanRejectsConflictingIdentityPublicMediaAndForgedProof() throws {
        let plan = try Self.plan(owner: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")), data = try body(plan)
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for (key, value) in ["client_scan_id": UUID().uuidString.lowercased(), "initialEvidence": "forged",
                             "audioBase64": "AA==", "user_id": plan.ownerID.uuidString] {
            var changed = payload; changed[key] = value
            #expect(throws: (any Error).self) {
                try IdentificationPreflightInput(body: JSONSerialization.data(withJSONObject: changed), function: "identify-multimodal")
            }
        }
        var changed = payload; changed["imageBase64s"] = ["AA=="]
        #expect(throws: (any Error).self) {
            try IdentificationPreflightInput(body: JSONSerialization.data(withJSONObject: changed), function: "identify-multimodal")
        }
        #expect(throws: (any Error).self) { try IdentificationPreflightInput(body: data, function: "identify") }
        let frozen = try SharedMediaCaptureSubmissionContextTests.context(plan)
        #expect(throws: (any Error).self) {
            try InferencePayloadBuilder.privateCaptureBody(plan: plan, frozen: frozen,
                context: InferencePayloadBuilder.makeContext(userId: UUID().uuidString,
                    telemetry: frozen.telemetry, defaultGeoprivacy: "private"))
        }
    }

    @MainActor @Test func authenticatedRequestUsesPlanProfileAndAccountBoundAuthorization() async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        fixture.client.overridingInferenceConsentCheck = {}
        let owner = try #require(fixture.client.overridingAuthUserID)
        let plan = try Self.plan(owner: owner), frozen = try SharedMediaCaptureSubmissionContextTests.context(plan)
        fixture.transport.register(path: "/get_my_identification_preflight") { request in
            let data = try #require(MockURLProtocol.bodyData(for: request))
            let shape = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(shape["p_input_profile"] as? String == "multimodal_photo_audio_v1")
            #expect(shape["capturePlan"] == nil)
            return try NetworkEndpointTestSupport.response(to: request, json:
                #"[{"input_profile":"multimodal_photo_audio_v1","decision":"ready","processor_permission":"google_gemini","minimum_client_protocol":3,"minimum_identification_protocol":7}]"#)
        }
        let prepared = try await fixture.client.buildPrivateCaptureRequest(plan: plan, context: frozen, validateAttempt: {})
        #expect(prepared.expectedAuthUserID == owner)
        #expect(prepared.identificationAuthorization?.recipient == .gemini)
        #expect(prepared.request.url?.lastPathComponent == "identify-multimodal")
        #expect(prepared.request.value(forHTTPHeaderField: IdentificationRecipientExpectation.header) == "google_gemini")
        await #expect(throws: CancellationError.self) {
            try await fixture.client.buildPrivateCaptureRequest(plan: plan, context: frozen,
                validateAttempt: { throw CancellationError() })
        }
    }
}
