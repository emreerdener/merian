import Foundation
import Testing

@testable import Merian

@Suite("Scan Enrichment Endpoints")
@MainActor
struct ScanEnrichmentEndpointTests {
    private typealias RequestCase = EnrichmentExportFeedbackRequestCase

    @Test(arguments: ["enrichment", "lookalikes", "full", " Unknown scope \n", ""])
    func enrichmentPreservesRawFieldsAndUsesTheCanonicalScanKey(scope: String) async throws {
        let testCase = try RequestCase.make(.enrichment, enrichmentScope: scope)
        try await testCase.withResponse { client in try await testCase.invoke(client) }
    }

    @Test func enrichmentKeepsExplicitSnakeCaseProjection() async throws {
        let testCase = try RequestCase.make(.enrichment)
        try await testCase.withResponse { client in
            let response = try await client.fetchEnrichment(
                scanId: RequestCase.scanID, scientificName: " Testus example ", confidenceScore: 0,
                inferenceTier: " RAW-TIER ", scope: "lookalikes"
            )
            #expect(response.success == true)
            #expect(response.data?.habitat_description == "Synthetic habitat.")
            #expect(response.data?.gbif_taxon_key == 42)
            #expect(response.data?.alternative_common_names == ["Synthetic synonym"])
            #expect(response.data?.similar_species?.first?.scientific_name == "Testus example")
            #expect(response.data?.similar_species?.first?.common_name == "Synthetic species")
        }
    }

    @Test(arguments: ["", "not-json", "null", "[]", #"{"success":"true"}"#, #"{"data":42}"#])
    func malformedEnrichmentSuccessKeepsDecodingError(json: String) async throws {
        let testCase = try RequestCase.make(.enrichment)
        try await testCase.withResponse(json) { client in
            await #expect(throws: DecodingError.self) { try await testCase.invoke(client) }
        }
    }

    @Test(arguments: ["{}", #"{"success":false}"#, #"{"success":null,"data":null}"#])
    func enrichmentDoesNotAddSuccessOrDataRequirements(json: String) async throws {
        let testCase = try RequestCase.make(.enrichment)
        try await testCase.withResponse(json) { client in try await testCase.invoke(client) }
    }

    @Test func enrichmentSerializesBeforeUUIDValidationAndCancellation() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        await confirmation("Invalid JSON never dispatches", expectedCount: 0) { sent in
            fixture.transport.register(path: "/enrich-scan") { request in
                sent()
                return try NetworkEndpointTestSupport.response(to: request, json: "{}")
            }
            let task = Task { @MainActor in
                withUnsafeCurrentTask { $0?.cancel() }
                return try await fixture.client.fetchEnrichment(
                    scanId: "not-a-uuid", scientificName: "", confidenceScore: .nan,
                    inferenceTier: "", scope: ""
                )
            }
            do {
                _ = try await task.value
                Issue.record("Non-finite confidence must fail JSON serialization")
            } catch {
                let serializationError = error as NSError
                #expect(serializationError.domain == NSCocoaErrorDomain)
                #expect(serializationError.code == CocoaError.propertyListReadCorrupt.rawValue)
            }
        }
    }

    @Test func invalidEnrichmentUUIDPrecedesCancellationWithoutDispatch() async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        await confirmation("Invalid UUID never dispatches", expectedCount: 0) { sent in
            fixture.transport.register(path: "/enrich-scan") { request in
                sent()
                return try NetworkEndpointTestSupport.response(to: request, json: "{}")
            }
            let task = Task { @MainActor in
                withUnsafeCurrentTask { $0?.cancel() }
                return try await fixture.client.fetchEnrichment(
                    scanId: "not-a-uuid", scientificName: "", confidenceScore: 0,
                    inferenceTier: "", scope: ""
                )
            }
            await #expect(throws: MerianError.invalidResponse) { try await task.value }
        }
    }

    @Test(arguments: DeferredContextVariant.all)
    func deferredContextKeepsOptionalOmissionAndRawValues(_ variant: DeferredContextVariant) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        try await confirmation("One deferred-context request") { sent in
            fixture.transport.register(path: "/update-scan-context") { request in
                sent()
                try NetworkEndpointTestSupport.expectPOST(
                    request, function: "update-scan-context", json: variant.expectedJSON, timeout: 15
                )
                return try NetworkEndpointTestSupport.response(to: request, json: "")
            }
            try await fixture.client.updateDeferredScanContext(scanId: " Raw-Scan ", telemetry: variant.telemetry)
        }
    }

    @Test func noDeferredContextReturnsBeforeAuthAndCancellation() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        fixture.client.overridingAuthUserID = nil
        try await confirmation("No empty-context request", expectedCount: 0) { sent in
            fixture.transport.register(path: "/update-scan-context") { request in
                sent()
                return try NetworkEndpointTestSupport.response(to: request, json: "")
            }
            let task = Task { @MainActor in
                withUnsafeCurrentTask { $0?.cancel() }
                try await fixture.client.updateDeferredScanContext(scanId: "", telemetry: RequestCase.telemetry())
            }
            try await task.value
        }
    }

    @Test func nonFiniteContextFailsSerializationBeforeDispatch() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        await confirmation("No invalid-context request", expectedCount: 0) { sent in
            fixture.transport.register(path: "/update-scan-context") { request in
                sent()
                return try NetworkEndpointTestSupport.response(to: request, json: "")
            }
            do {
                try await fixture.client.updateDeferredScanContext(
                    scanId: " Raw-Scan ", telemetry: RequestCase.telemetry(elevation: .infinity)
                )
                Issue.record("Non-finite context must fail JSON serialization")
            } catch {
                let serializationError = error as NSError
                #expect(serializationError.domain == NSCocoaErrorDomain)
                #expect(serializationError.code == CocoaError.propertyListReadCorrupt.rawValue)
            }
        }
    }

    @Test func testDeferredContextUpdateUsesOwnerScanEndpoint() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        fixture.transport.register(path: "/update-scan-context") { request in
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            #expect(payload["scan_id"] as? String == "019f6650-34cc-7dc0-a31b-e8ec3d8eadd6")
            #expect(payload["gps_elevation"] as? Double == 181.5)
            #expect(payload["weather_condition"] as? String == "Clear")
            #expect(payload["weather_temperature_f"] as? Double == 72.0)
            #expect(payload["semantic_location"] as? String == "Chicago, Illinois")
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{\"success\":true}".utf8))
        }
        let telemetry = CaptureTelemetry(
            subjectDistanceInMeters: nil,
            gpsLatitude: nil,
            gpsLongitude: nil,
            gpsElevation: 181.5,
            locationName: "Chicago, Illinois",
            weatherCondition: "Clear",
            weatherTemperatureF: 72,
            timeOfDay: nil,
            timestamp: nil,
            zoomFactor: nil,
            estimatedSizeCm: nil
        )

        try await fixture.client.updateDeferredScanContext(
            scanId: "019f6650-34cc-7dc0-a31b-e8ec3d8eadd6",
            telemetry: telemetry
        )
    }

    @Test func testFetchEnrichmentSuccessfullyConstructsPayloadAndParsesJSON() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        // Arrange
        let testData = Data("""
        {
            "success": true,
            "data": {
                "gbif_taxon_key": 2433697,
                "habitat_description": "Deciduous forests and urban areas.",
                "similar_species": [
                    {
                        "species_id": "species-cancrivorus",
                        "scientific_name": "Procyon cancrivorus",
                        "common_name": "Crab-eating Raccoon",
                        "reference_image_url": "https://example.com/cancrivorus.jpg",
                        "iucn_red_list_status": "LC"
                    }
                ]
            }
        }
        """.utf8)
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!

        let scanID = "a1849d51-7a55-4bb0-931f-a49d880f69c7"
        fixture.transport.register(path: "/enrich-scan") { request in
            #expect(request.url?.path.hasSuffix("/enrich-scan") == true)
            #expect(request.httpMethod == "POST")
            let idempotencyKey = try #require(
                request.value(forHTTPHeaderField: "Idempotency-Key")
            )
            #expect(idempotencyKey == scanID)
            return (mockResponse, testData)
        }

        // Act
        let returnedObject = try await fixture.client.fetchEnrichment(
            scanId: scanID,
            scientificName: "Procyon lotor",
            confidenceScore: 0.95,
            inferenceTier: "pro",
            scope: "full"
        )

        // Assert
        #expect(returnedObject.success == true)
        let enrichmentData = try #require(returnedObject.data)
        #expect(enrichmentData.gbif_taxon_key == 2433697)
        #expect(enrichmentData.habitat_description == "Deciduous forests and urban areas.")
        let similar = try #require(enrichmentData.similar_species)
        #expect(similar.count == 1)
        #expect(similar[0].species_id == "species-cancrivorus")
        #expect(similar[0].scientific_name == "Procyon cancrivorus")
    }

    @Test func testFetchEnrichmentRejectsNonUUIDScanIdInsteadOfMintingANewQuotaKey() async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        await #expect(throws: MerianError.invalidResponse) {
            try await fixture.client.fetchEnrichment(
                scanId: "legacy-non-uuid-scan-id",
                scientificName: "Procyon lotor",
                confidenceScore: 0.95,
                inferenceTier: "pro",
                scope: "enrichment"
            )
        }
    }
}

struct DeferredContextVariant: Sendable, CustomTestStringConvertible {
    private typealias RequestCase = EnrichmentExportFeedbackRequestCase
    let name: String
    let telemetry: CaptureTelemetry
    let expectedJSON: String
    var testDescription: String { name }

    static let all: [Self] = [
        Self(name: "zero elevation", telemetry: RequestCase.telemetry(elevation: 0),
             expectedJSON: #"{"scan_id":" Raw-Scan ","gps_elevation":0}"#),
        Self(name: "blank condition", telemetry: RequestCase.telemetry(condition: ""),
             expectedJSON: #"{"scan_id":" Raw-Scan ","weather_condition":""}"#),
        Self(name: "zero temperature", telemetry: RequestCase.telemetry(temperature: 0),
             expectedJSON: #"{"scan_id":" Raw-Scan ","weather_temperature_f":0}"#),
        Self(name: "raw semantic label", telemetry: RequestCase.telemetry(location: " Synthetic site \n"),
             expectedJSON: #"{"scan_id":" Raw-Scan ","semantic_location":" Synthetic site \n"}"#),
        Self(name: "all fields without client range filtering",
             telemetry: RequestCase.telemetry(elevation: -501, condition: " Clear ", temperature: 201, location: ""),
             expectedJSON: """
             {"scan_id":" Raw-Scan ","gps_elevation":-501,"weather_condition":" Clear ",
              "weather_temperature_f":201,"semantic_location":""}
             """)
    ]
}
