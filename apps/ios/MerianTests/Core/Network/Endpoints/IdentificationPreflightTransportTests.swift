import Foundation
import os
import Testing

@testable import Merian

@MainActor
@Suite("Identification Preflight Transport")
struct IdentificationPreflightTransportTests {
    @Test(arguments: [("google_gemini", 0), ("openai", 4), ("openai", 5), ("recovery_only", 0)])
    func preparedAndLiveRequestsEchoOnlyTheAssignedRecipient(scenario: (String, Int)) async throws {
        let (recipient, identificationMinimum) = scenario
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        fixture.client.overridingInferenceConsentCheck = {}
        fixture.transport.register(path: "/get_my_identification_preflight") { request in
            if recipient == "recovery_only" {
                return try NetworkEndpointTestSupport.response(to: request, json:
                    #"[{"input_profile":"multimodal_text_v1","decision":"recovery_only","processor_permission":null,"minimum_client_protocol":null}]"#)
            }
            return try NetworkEndpointTestSupport.response(to: request, json:
                "[{\"input_profile\":\"multimodal_text_v1\",\"decision\":\"ready\",\"processor_permission\":\"\(recipient)\",\"minimum_client_protocol\":3,\"minimum_identification_protocol\":\(identificationMinimum)}]")
        }
        fixture.transport.register(path: "/identify-multimodal") { request in
            #expect(request.value(forHTTPHeaderField: IdentificationRecipientExpectation.header) == recipient)
            #expect(request.value(forHTTPHeaderField: IdentificationDispatchAuthorization.protocolHeader) == "6")
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
                "[{\"input_profile\":\"multimodal_text_v1\",\"decision\":\"\(decision)\",\"processor_permission\":\"openai\",\"minimum_client_protocol\":\(minimum),\"minimum_identification_protocol\":4}]")
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
    @Test(arguments: [IdentificationRecipientExpectation.gemini, .openAI])
    func nativePhotoAdmissionSynchronizesConsentBeforeShapeRead(_ recipient: IdentificationRecipientExpectation) async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let owner = try #require(fixture.client.overridingAuthUserID)
        let input = try IdentificationPreflightInput(nativePhotoObservationID: UUID(), photoCount: 1, contexts: [])
        let events = OSAllocatedUnfairLock(initialState: [String]())
        fixture.client.overridingInferenceConsentCheck = { events.withLock { $0.append("consent") } }
        fixture.transport.register(path: "/get_my_identification_preflight") { wire in
            #expect(events.withLock { $0 } == ["consent"])
            events.withLock { $0.append("preflight") }
            let body = try #require(MockURLProtocol.bodyData(for: wire))
            #expect(try NetworkEndpointTestSupport.canonicalRequestJSON(body)
                == NetworkEndpointTestSupport.canonicalRequestJSON(JSONEncoder().encode(input)))
            return try NetworkEndpointTestSupport.response(to: wire, json:
                "[{\"input_profile\":\"multimodal_photo_v1\",\"decision\":\"ready\",\"processor_permission\":\"\(recipient.rawValue)\",\"minimum_client_protocol\":3,\"minimum_identification_protocol\":\(recipient == .openAI ? 5 : 0)}]")
        }
        let authorization = try await fixture.client.prepareNativePhotoAdmissionAuthorization(
            input: input, expectedAuthUserID: owner, validateAttempt: {})
        #expect(authorization.recipient == recipient)
        try authorization.validate()
        #expect(events.withLock { $0 } == ["consent", "preflight"])
    }

    @Test(arguments: ["owner", "consent", "stale-before", "stale-after", "owner-after"])
    func nativePhotoAdmissionStopsBeforeReadWhenConsentOrAttemptChanges(_ reason: String) async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let owner = try #require(fixture.client.overridingAuthUserID)
        let input = try IdentificationPreflightInput(nativePhotoObservationID: UUID(), photoCount: 2, contexts: [])
        let synced = OSAllocatedUnfairLock(initialState: false), sends = OSAllocatedUnfairLock(initialState: 0)
        fixture.client.overridingInferenceConsentCheck = {
            synced.withLock { $0 = true }
            if reason == "consent" { throw MerianError.aiConsentRequired }
            if reason == "owner-after" { await MainActor.run { fixture.client.overridingAuthUserID = UUID() } }
        }
        fixture.transport.register(path: "/get_my_identification_preflight") { wire in
            sends.withLock { $0 += 1 }
            return try NetworkEndpointTestSupport.readyGeminiPreflight(wire)
        }
        await #expect(throws: (any Error).self) {
            try await fixture.client.prepareNativePhotoAdmissionAuthorization(input: input,
                expectedAuthUserID: reason == "owner" ? UUID() : owner, validateAttempt: {
                    if reason == "stale-before" || (reason == "stale-after" && synced.withLock({ $0 })) {
                        throw CancellationError()
                    }
                })
        }
        #expect(sends.withLock { $0 } == 0)
        if ["owner", "stale-before"].contains(reason) { #expect(!synced.withLock { $0 }) }
    }

    @Test func nativePhotoAdmissionRechecksAttemptAfterReadAndAtSave() async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let owner = try #require(fixture.client.overridingAuthUserID)
        let input = try IdentificationPreflightInput(nativePhotoObservationID: UUID(), photoCount: 1, contexts: [])
        let stale = OSAllocatedUnfairLock(initialState: false)
        fixture.client.overridingInferenceConsentCheck = {}
        let validate: @MainActor @Sendable () throws -> Void = {
            if stale.withLock({ $0 }) { throw CancellationError() }
        }
        let authorization = try await fixture.client.prepareNativePhotoAdmissionAuthorization(
            input: input, expectedAuthUserID: owner, validateAttempt: validate)
        stale.withLock { $0 = true }
        #expect(throws: CancellationError.self) { try authorization.validate() }
        stale.withLock { $0 = false }
        fixture.transport.register(path: "/get_my_identification_preflight") { wire in
            stale.withLock { $0 = true }
            return try NetworkEndpointTestSupport.readyGeminiPreflight(wire)
        }
        await #expect(throws: CancellationError.self) {
            try await fixture.client.prepareNativePhotoAdmissionAuthorization(
                input: input, expectedAuthUserID: owner, validateAttempt: validate)
        }
    }

    @Test func nativePhotoAdmissionRejectsNonPhotoShapeBeforeConsent() async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let owner = try #require(fixture.client.overridingAuthUserID)
        let input = try IdentificationPreflightInput(body: JSONSerialization.data(withJSONObject:
            ["client_scan_id": UUID().uuidString, "observation_contexts": [["freeText": "synthetic leaf"]]]),
            function: "identify-multimodal")
        fixture.client.overridingInferenceConsentCheck = { Issue.record("Non-photo shape reached consent") }
        await #expect(throws: MerianError.invalidResponse) {
            try await fixture.client.prepareNativePhotoAdmissionAuthorization(
                input: input, expectedAuthUserID: owner, validateAttempt: {})
        }
    }

    private func telemetry() -> CaptureTelemetry {
        CaptureTelemetry(subjectDistanceInMeters: nil, gpsLatitude: nil, gpsLongitude: nil,
                         gpsElevation: nil, locationName: nil, weatherCondition: nil,
                         weatherTemperatureF: nil, timeOfDay: nil, timestamp: nil)
    }

}
