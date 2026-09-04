import Foundation
import Testing

@testable import Merian

private final class InferenceCallbackProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func mark() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var wasMarked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class InferenceRequestProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var requestCount = 0
    private var idempotencyKeys: [String?] = []

    func record(idempotencyKey: String?) -> Int {
        lock.lock()
        defer { lock.unlock() }
        requestCount += 1
        idempotencyKeys.append(idempotencyKey)
        return requestCount
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCount
    }

    var recordedIdempotencyKeys: [String?] {
        lock.lock()
        defer { lock.unlock() }
        return idempotencyKeys
    }
}

@Suite(
    "Inference Endpoint Transport",
    .serialized,
    .sharedProcessState(.networkClientOverrides)
)
@MainActor
struct InferenceEndpointTransportTests {
    @Test func testInferencePrewarmUsesPinnedClientSessionAndOptionsRoute() async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let probe = InferenceCallbackProbe()
        fixture.transport.register(path: "/identify-multimodal") { request in
            #expect(request.httpMethod == "OPTIONS")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
            #expect(request.value(forHTTPHeaderField: "X-Merian-Entitlement-Protocol") == nil)
            #expect(request.httpBody == nil)
            probe.mark()
            return try NetworkEndpointTestSupport.response(
                to: request,
                json: #"{"success":true}"#
            )
        }

        await fixture.client.prewarmInferenceEndpoint()
        #expect(probe.wasMarked)
    }

    @Test func testIdentifyMultiModalSignalsWhenInlineRequestBodyIsSent() async throws {
        let fixture = inferenceFixture()
        defer { fixture.close() }
        let probe = InferenceCallbackProbe()
        fixture.transport.register(path: "/identify-multimodal") { request in
            #expect(
                request.value(forHTTPHeaderField: "X-Merian-Entitlement-Protocol") == "3"
            )
            #expect(
                request.value(forHTTPHeaderField: "Idempotency-Key")
                    == "019f6650-34cc-7dc0-a31b-e8ec3d8eadd6"
            )
            return try NetworkEndpointTestSupport.response(
                to: request,
                json: #"{"success":true}"#
            )
        }

        _ = try await fixture.client.identifyMultiModal(
            base64ImageDatas: ["AA=="],
            telemetry: telemetry(timestamp: "2026-07-15T15:00:00Z"),
            clientScanId: "019f6650-34cc-7dc0-a31b-e8ec3d8eadd6",
            onRequestBodySent: { probe.mark() }
        )
        #expect(probe.wasMarked)
    }

    @Test func queueBackedIdentifyReturnsFirstTransportFailureWithoutInlineReplay() async {
        let fixture = inferenceFixture()
        defer { fixture.close() }
        let requestProbe = InferenceRequestProbe()
        let bodySentProbe = InferenceCallbackProbe()
        let scanID = "019f6650-34cc-7dc0-a31b-e8ec3d8eadd6"
        fixture.transport.register(path: "/identify-multimodal") { request in
            #expect(
                request.timeoutInterval == 15,
                "Durable queue ownership must bound the foreground wait."
            )
            _ = requestProbe.record(
                idempotencyKey: request.value(forHTTPHeaderField: "Idempotency-Key")
            )
            throw URLError(.networkConnectionLost)
        }

        do {
            _ = try await fixture.client.identifyMultiModal(
                base64ImageDatas: ["AA=="],
                telemetry: telemetry(),
                clientScanId: scanID,
                durableQueueOwnsRecovery: true,
                onRequestBodySent: { bodySentProbe.mark() }
            )
            Issue.record("Expected the first transport failure to reach the queue owner.")
        } catch let error as URLError {
            #expect(error.code == .networkConnectionLost)
        } catch {
            Issue.record("Expected URLError.networkConnectionLost, got \(error).")
        }

        #expect(
            requestProbe.count == 1,
            "Queue-backed transport must return the first failure without inline replay."
        )
        #expect(requestProbe.recordedIdempotencyKeys == [scanID])
        #expect(bodySentProbe.wasMarked)
    }

    @Test func queueLessIdentifyRetainsOneReviewedInlineTransportReplay() async throws {
        let fixture = inferenceFixture()
        defer { fixture.close() }
        let requestProbe = InferenceRequestProbe()
        let scanID = "019f6650-34cc-7dc0-a31b-e8ec3d8eadd7"
        fixture.transport.register(path: "/identify-multimodal") { request in
            #expect(
                request.timeoutInterval == 90,
                "Queue-less callers must retain the reviewed provider window."
            )
            let attempt = requestProbe.record(
                idempotencyKey: request.value(forHTTPHeaderField: "Idempotency-Key")
            )
            if attempt == 1 {
                throw URLError(.networkConnectionLost)
            }
            return try NetworkEndpointTestSupport.response(
                to: request,
                json: #"{"success":true}"#
            )
        }

        _ = try await fixture.client.identifyMultiModal(
            base64ImageDatas: ["AA=="],
            telemetry: telemetry(),
            clientScanId: scanID
        )

        #expect(requestProbe.count == 2)
        #expect(requestProbe.recordedIdempotencyKeys == [scanID, scanID])
    }

    @Test func testIdentifyMultiModalStopsBeforeDispatchWhenConsentIsMissing() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let probe = InferenceCallbackProbe()
        fixture.client.overridingInferenceConsentCheck = {
            throw MerianError.aiConsentRequired
        }
        fixture.transport.register(path: "/identify-multimodal") { request in
            probe.mark()
            return try NetworkEndpointTestSupport.response(to: request, json: "{}")
        }

        do {
            _ = try await fixture.client.identifyMultiModal(
                base64ImageDatas: ["AA=="],
                telemetry: telemetry(),
                clientScanId: "019f6650-34cc-7dc0-a31b-e8ec3d8eadd6"
            )
            Issue.record("Expected missing consent to stop inference")
        } catch MerianError.aiConsentRequired {
            // Expected path.
        } catch {
            Issue.record("Expected MerianError.aiConsentRequired, got \(error)")
        }

        #expect(!probe.wasMarked)
    }

    @Test func cancelledIdentifyStopsBeforeRequestPreparationOrDispatch() async {
        let fixture = inferenceFixture()
        defer { fixture.close() }
        let probe = InferenceCallbackProbe()
        fixture.transport.register(path: "/identify-multimodal") { request in
            probe.mark()
            return try NetworkEndpointTestSupport.response(to: request, json: "{}")
        }

        let requestTask = Task { @MainActor in
            try await fixture.client.identifyMultiModal(
                base64ImageDatas: ["AA=="],
                telemetry: telemetry(),
                clientScanId: "019f6650-34cc-7dc0-a31b-e8ec3d8eadd6"
            )
        }
        requestTask.cancel()

        do {
            _ = try await requestTask.value
            Issue.record("Expected cancellation before inference dispatch.")
        } catch is CancellationError {
            // Expected path.
        } catch {
            Issue.record("Expected CancellationError, got \(error).")
        }

        #expect(!probe.wasMarked)
    }

    @Test func testIdentifyMultiModalMapsServerConsentRejectionToDisclosureError() async {
        let fixture = inferenceFixture()
        defer { fixture.close() }
        fixture.transport.register(path: "/identify-multimodal") { request in
            try NetworkEndpointTestSupport.response(
                to: request,
                status: 403,
                json: #"{"code":"ai_consent_required"}"#
            )
        }

        await #expect(throws: MerianError.aiConsentRequired) {
            try await fixture.client.identifyMultiModal(
                base64ImageDatas: ["AA=="],
                telemetry: telemetry(),
                clientScanId: "019f6650-34cc-7dc0-a31b-e8ec3d8eadd6"
            )
        }
    }

    @Test func testAnalyzeSubjectSuccessfullyConstructsPayloadAndParsesJSON() async throws {
        let fixture = inferenceFixture()
        defer { fixture.close() }
        let responseJSON = """
        {
            "success": true,
            "data": {
                "scan_id": "test_scan_001",
                "is_biological_subject": true,
                "scientific_name": "Procyon lotor",
                "common_name": "Raccoon"
            }
        }
        """
        fixture.transport.register(path: "/identify") { request in
            #expect(request.url?.path.hasSuffix("/identify") == true)
            #expect(request.httpMethod == "POST")
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            #expect(payload["imageBase64s"] as? [String] == ["fake_base64_string"])
            #expect(payload["mimeType"] as? String == "image/webp")
            #expect(payload["semanticLocation"] as? String == "Central Park")
            #expect(payload["publicLocationLabel"] == nil)
            #expect(payload["zoomFactor"] as? Double == 1.5)
            #expect(payload["gps_latitude"] == nil)
            #expect(payload["semantic_location"] == nil)
            let clientScanID = try #require(payload["client_scan_id"] as? String)
            #expect(UUID(uuidString: clientScanID) != nil)
            #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == clientScanID)
            return try NetworkEndpointTestSupport.response(
                to: request,
                json: responseJSON
            )
        }

        let returnedData = try await fixture.client.analyzeSubject(
            r2ObjectKeys: nil,
            base64ImageDatas: ["fake_base64_string"],
            mimeType: "image/webp",
            telemetry: CaptureTelemetry(
                subjectDistanceInMeters: nil,
                gpsLatitude: nil,
                gpsLongitude: nil,
                gpsElevation: nil,
                locationName: "Central Park",
                weatherCondition: nil,
                weatherTemperatureF: nil,
                timeOfDay: nil,
                timestamp: nil,
                zoomFactor: 1.5,
                estimatedSizeCm: nil
            )
        )

        let decoded = try JSONDecoder().decode(EdgeResponseWrapper.self, from: returnedData)
        #expect(decoded.success == true)
        #expect(decoded.data.common_name == "Raccoon")
        #expect(decoded.data.scan_id == "test_scan_001")
    }

    @Test func testAnalyzeSubjectRejectsOversizedInlineImagePayloadBeforeNetwork() async throws {
        let fixture = inferenceFixture()
        defer { fixture.close() }
        await confirmation("Oversized payload does not dispatch", expectedCount: 0) { sent in
            fixture.transport.register(path: "/identify") { request in
                sent()
                return try NetworkEndpointTestSupport.response(to: request, json: "{}")
            }

            await #expect(throws: MerianError.payloadTooLarge) {
                try await fixture.client.analyzeSubject(
                    r2ObjectKeys: nil,
                    base64ImageDatas: [String(
                        repeating: "X",
                        count: MerianNetworkClient.maxInlineInferenceBodyBytes + 1
                    )],
                    telemetry: telemetry()
                )
            }
        }
    }

    private func inferenceFixture() -> NetworkEndpointFixture {
        let fixture = NetworkEndpointFixture()
        fixture.client.overridingInferenceConsentCheck = {}
        return fixture
    }

    private func telemetry(timestamp: String? = nil) -> CaptureTelemetry {
        CaptureTelemetry(
            subjectDistanceInMeters: nil,
            gpsLatitude: nil,
            gpsLongitude: nil,
            gpsElevation: nil,
            locationName: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil,
            timeOfDay: nil,
            timestamp: timestamp,
            zoomFactor: nil,
            estimatedSizeCm: nil
        )
    }
}
