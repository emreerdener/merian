import Foundation
import Testing

@testable import Merian

@MainActor
@Suite("Identification Preflight Transport")
struct IdentificationPreflightTransportTests {
    @Test(arguments: ["google_gemini", "openai", "recovery_only"])
    func preparedAndLiveRequestsEchoOnlyTheAssignedRecipient(recipient: String) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        fixture.client.overridingInferenceConsentCheck = {}
        fixture.transport.register(path: "/get_my_identification_preflight") { request in
            if recipient == "recovery_only" {
                return try NetworkEndpointTestSupport.response(to: request, json:
                    #"[{"input_profile":"multimodal_text_v1","decision":"recovery_only","processor_permission":null,"minimum_client_protocol":null}]"#)
            }
            return try NetworkEndpointTestSupport.response(to: request, json:
                "[{\"input_profile\":\"multimodal_text_v1\",\"decision\":\"ready\",\"processor_permission\":\"\(recipient)\",\"minimum_client_protocol\":3}]")
        }
        fixture.transport.register(path: "/identify-multimodal") { request in
            #expect(request.value(forHTTPHeaderField: IdentificationRecipientExpectation.header) == recipient)
            return try NetworkEndpointTestSupport.response(to: request, json: #"{"success":true}"#)
        }
        let prepared = try await fixture.client.buildMultiModalRequest(
            observationContextsJSON: [#"{"freeText":"synthetic leaf"}"#],
            telemetry: telemetry(), clientScanId: UUID().uuidString)
        #expect(prepared.request.value(forHTTPHeaderField: IdentificationRecipientExpectation.header) == recipient)
        #expect(prepared.identificationAuthorization?.recipient.rawValue == recipient)
        _ = try await fixture.client.performAuthenticatedInferenceRequest(
            prepared, timeoutInterval: 30, allowsTransientTransportRetry: false, onRequestBodySent: nil)
    }

    @Test(arguments: ["permission_required", "client_update_required", "invalid", "entitlement"])
    func deniedOrMalformedPreflightNeverSendsObservation(decision: String) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        fixture.client.overridingInferenceConsentCheck = {}
        fixture.transport.register(path: "/identify-multimodal") { _ in
            Issue.record("A denied preflight must not send the observation")
            throw URLError(.badServerResponse)
        }
        fixture.transport.register(path: "/get_my_identification_preflight") { request in
            if decision == "entitlement" {
                return try NetworkEndpointTestSupport.response(to: request, status: 400,
                    json: #"{"code":"P0001","message":"ai_entitlement_required"}"#)
            }
            if decision == "invalid" {
                return try NetworkEndpointTestSupport.response(to: request, json: "[]")
            }
            let minimum = decision == "client_update_required" ? 4 : 3
            return try NetworkEndpointTestSupport.response(to: request, json:
                "[{\"input_profile\":\"multimodal_text_v1\",\"decision\":\"\(decision)\",\"processor_permission\":\"openai\",\"minimum_client_protocol\":\(minimum)}]")
        }
        do {
            _ = try await fixture.client.identifyMultiModal(
                observationContextsJSON: [#"{"freeText":"synthetic leaf"}"#],
                telemetry: telemetry(), clientScanId: UUID().uuidString)
            Issue.record("Preflight should stop identification")
        } catch {
            switch decision {
            case "permission_required": #expect((error as? MerianError) == .openAIConsentRequired)
            case "client_update_required": #expect(EdgeFunctionErrorPolicy.stableCode(from: error) == "client_update_required")
            case "entitlement": #expect(EdgeFunctionErrorPolicy.stableCode(from: error) == "pro_required")
            default: #expect((error as? MerianError) == .invalidResponse)
            }
        }
    }

    @Test func staleAttemptAfterPreflightStopsBeforeProviderAndUploadRelease() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        fixture.client.overridingInferenceConsentCheck = {}
        fixture.transport.register(path: "/identify-multimodal") { _ in
            Issue.record("Stale attempt reached provider dispatch")
            throw URLError(.badServerResponse)
        }
        await #expect(throws: CancellationError.self) {
            try await fixture.client.identifyMultiModal(
                observationContextsJSON: [#"{"freeText":"synthetic leaf"}"#],
                telemetry: telemetry(), clientScanId: UUID().uuidString,
                validateAttempt: { throw CancellationError() },
                onProviderDispatchReady: { Issue.record("Stale attempt released upload") })
        }
    }
    private func telemetry() -> CaptureTelemetry {
        CaptureTelemetry(subjectDistanceInMeters: nil, gpsLatitude: nil, gpsLongitude: nil,
                         gpsElevation: nil, locationName: nil, weatherCondition: nil,
                         weatherTemperatureF: nil, timeOfDay: nil, timestamp: nil)
    }

}
