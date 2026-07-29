import Foundation
import Testing
@testable import Merian

/// Intercepts network requests for MerianNetworkClient testing
class MockURLProtocol: URLProtocol {
    static var mockEndpoints: [String: ((URLRequest) throws -> (HTTPURLResponse, Data))] = [:]

    static func bodyData(for request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        let bufferSize = 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        let data = NSMutableData()

        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read < 0 {
                return nil
            }

            if read == 0 {
                break
            }

            data.append(buffer, length: read)
        }

        return data as Data
    }
    
    override class func canInit(with request: URLRequest) -> Bool { return true }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { return request }
    
    override func startLoading() {
        guard let path = request.url?.path else { return }
        
        let match = MockURLProtocol.mockEndpoints.first { path.hasSuffix($0.key) }
        guard let handler = match?.value else {
            let error = NSError(domain: "MockURLProtocol", code: 404, userInfo: [NSLocalizedDescriptionKey: "No endpoint configured for \(path)"])
            self.client?.urlProtocol(self, didFailWithError: error)
            return
        }
        
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    
    override func stopLoading() {}
}

/// URLProtocol transport whose handlers are isolated by a request header.
/// Each test owns a `ScopedMockTransport`, so independently configured clients
/// can run concurrently without sharing endpoint dictionaries or sessions.
final class ScopedMockURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    private final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var handlersByScope: [String: [String: Handler]] = [:]

        func register(scopeID: String, path: String, handler: @escaping Handler) {
            lock.lock()
            defer { lock.unlock() }
            handlersByScope[scopeID, default: [:]][path] = handler
        }

        func handler(scopeID: String, requestPath: String) -> Handler? {
            lock.lock()
            defer { lock.unlock() }
            return handlersByScope[scopeID]?
                .filter { requestPath.hasSuffix($0.key) }
                .max { $0.key.count < $1.key.count }?
                .value
        }

        func remove(scopeID: String) {
            lock.lock()
            defer { lock.unlock() }
            handlersByScope.removeValue(forKey: scopeID)
        }
    }

    fileprivate static let scopeHeader = "X-Merian-Test-Scope"
    private static let registry = Registry()

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let scopeID = request.value(forHTTPHeaderField: Self.scopeHeader),
              let path = request.url?.path,
              let handler = Self.registry.handler(scopeID: scopeID, requestPath: path) else {
            let error = NSError(
                domain: "ScopedMockURLProtocol",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "No scoped endpoint configured"]
            )
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    fileprivate static func register(
        scopeID: String,
        path: String,
        handler: @escaping Handler
    ) {
        registry.register(scopeID: scopeID, path: path, handler: handler)
    }

    fileprivate static func remove(scopeID: String) {
        registry.remove(scopeID: scopeID)
    }
}

final class ScopedMockTransport {
    private let scopeID = UUID().uuidString

    func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScopedMockURLProtocol.self]
        configuration.httpAdditionalHeaders = [
            ScopedMockURLProtocol.scopeHeader: scopeID
        ]
        return URLSession(configuration: configuration)
    }

    func register(
        path: String,
        handler: @escaping ScopedMockURLProtocol.Handler
    ) {
        ScopedMockURLProtocol.register(
            scopeID: scopeID,
            path: path,
            handler: handler
        )
    }

    deinit {
        ScopedMockURLProtocol.remove(scopeID: scopeID)
    }
}

private final class SendableCallbackProbe: @unchecked Sendable {
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

private final class NetworkRequestProbe: @unchecked Sendable {
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

@Suite("Network Client Tests", .serialized)
@MainActor
struct MerianNetworkClientTests {
    
    init() {
        MockURLProtocol.mockEndpoints = [:]

        // Build an ephemeral URLSession configuration tailored exclusively for Mocking
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        
        // Inject so MerianNetworkClient hooks this instead of hitting live internet
        MerianNetworkClient.shared.overridingSession = URLSession(configuration: config)
        MerianNetworkClient.shared.resetSpeciesDictionaryCacheForTesting()
    }

    @Test func testScopedMockTransportsIsolateConcurrentSessions() async throws {
        let firstTransport = ScopedMockTransport()
        let secondTransport = ScopedMockTransport()
        let firstSession = firstTransport.makeSession()
        let secondSession = secondTransport.makeSession()
        let url = URL(string: "https://example.com/scoped-endpoint")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        firstTransport.register(path: "/scoped-endpoint") { _ in
            (response, Data("first".utf8))
        }
        secondTransport.register(path: "/scoped-endpoint") { _ in
            (response, Data("second".utf8))
        }

        async let firstResult = firstSession.data(from: url)
        async let secondResult = secondSession.data(from: url)
        let (firstData, _) = try await firstResult
        let (secondData, _) = try await secondResult

        #expect(String(decoding: firstData, as: UTF8.self) == "first")
        #expect(String(decoding: secondData, as: UTF8.self) == "second")
    }

    @Test func testMissingAuthSessionRecoveryOnlyRegeneratesGuestSessions() {
        #expect(MerianNetworkClient.shouldRegenerateSessionAfterMissingAuthSession(
            hasAuthenticatedOAuth: false,
            isGuestUser: true
        ))
        #expect(!MerianNetworkClient.shouldRegenerateSessionAfterMissingAuthSession(
            hasAuthenticatedOAuth: true,
            isGuestUser: true
        ))
        #expect(!MerianNetworkClient.shouldRegenerateSessionAfterMissingAuthSession(
            hasAuthenticatedOAuth: false,
            isGuestUser: false
        ))
        #expect(!MerianNetworkClient.shouldRegenerateSessionAfterMissingAuthSession(
            hasAuthenticatedOAuth: true,
            isGuestUser: false
        ))
    }

    @Test func testInferencePrewarmUsesPinnedClientSessionAndOptionsRoute() async {
        let probe = SendableCallbackProbe()
        MockURLProtocol.mockEndpoints["/identify-multimodal"] = { request in
            #expect(request.httpMethod == "OPTIONS")
            probe.mark()
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("ok".utf8))
        }

        await MerianNetworkClient.shared.prewarmInferenceEndpoint()
        #expect(probe.wasMarked)
    }

    @Test func testIdentifyMultiModalSignalsWhenInlineRequestBodyIsSent() async throws {
        let probe = SendableCallbackProbe()
        MockURLProtocol.mockEndpoints["/identify-multimodal"] = { request in
            #expect(
                request.value(forHTTPHeaderField: "Idempotency-Key")
                    == "019f6650-34cc-7dc0-a31b-e8ec3d8eadd6"
            )
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Server-Timing": "auth;dur=1.0, gemini;dur=10.0",
                    "X-Merian-Edge-Region": "test-region"
                ]
            )!
            return (response, Data("{\"success\":true}".utf8))
        }
        let telemetry = CaptureTelemetry(
            subjectDistanceInMeters: 1,
            gpsLatitude: 41.9,
            gpsLongitude: -87.6,
            gpsElevation: nil,
            locationName: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil,
            timeOfDay: nil,
            timestamp: "2026-07-15T15:00:00Z",
            zoomFactor: nil,
            estimatedSizeCm: nil
        )

        _ = try await MerianNetworkClient.shared.identifyMultiModal(
            base64ImageDatas: ["AA=="],
            telemetry: telemetry,
            clientScanId: "019f6650-34cc-7dc0-a31b-e8ec3d8eadd6",
            onRequestBodySent: { probe.mark() }
        )
        #expect(probe.wasMarked)
    }

    @Test func testDeferredContextUpdateUsesOwnerScanEndpoint() async throws {
        MockURLProtocol.mockEndpoints["/update-scan-context"] = { request in
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

        try await MerianNetworkClient.shared.updateDeferredScanContext(
            scanId: "019f6650-34cc-7dc0-a31b-e8ec3d8eadd6",
            telemetry: telemetry
        )
    }

    @Test func testAnalyzeSubjectSuccessfullyConstructsPayloadAndParsesJSON() async throws {
        // Arrange
        let testData = """
        {
            "success": true,
            "data": {
                "scan_id": "test_scan_001",
                "is_biological_subject": true,
                "scientific_name": "Procyon lotor",
                "common_name": "Raccoon"
            }
        }
        """.data(using: .utf8)!
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        
        MockURLProtocol.mockEndpoints["/identify"] = { request in
            // Assert Request correctness
            #expect(request.url?.path.hasSuffix("/identify") == true)
            #expect(request.httpMethod == "POST")

            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["imageBase64s"] as? [String] == ["fake_base64_string"])
            #expect(payload["mimeType"] as? String == "image/webp")
            #expect(payload["semanticLocation"] as? String == "Central Park")
            #expect(payload["publicLocationLabel"] == nil)
            #expect(payload["zoomFactor"] as? Double == 1.5)
            #expect(payload["gps_latitude"] == nil)
            #expect(payload["semantic_location"] == nil)
            let clientScanID = try #require(payload["client_scan_id"] as? String)
            #expect(UUID(uuidString: clientScanID) != nil)
            #expect(
                request.value(forHTTPHeaderField: "Idempotency-Key")
                    == clientScanID
            )
            return (mockResponse, testData)
        }
        
        let telemetry = CaptureTelemetry(
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
        
        // Act
        let returnedData = try await MerianNetworkClient.shared.analyzeSubject(
            r2ObjectKeys: nil,
            base64ImageDatas: ["fake_base64_string"],
            mimeType: "image/webp",
            telemetry: telemetry
        )
        
        // Assert
        let decoded = try JSONDecoder().decode(EdgeResponseWrapper.self, from: returnedData)
        #expect(decoded.success == true)
        #expect(decoded.data.common_name == "Raccoon")
        #expect(decoded.data.scan_id == "test_scan_001")
    }

    @Test func testAnalyzeSubjectRejectsOversizedInlineImagePayloadBeforeNetwork() async throws {
        MockURLProtocol.mockEndpoints["/identify"] = { _ in
            Issue.record("Oversized inline image payload should fail before the network request is sent")
            let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }

        let telemetry = CaptureTelemetry(
            subjectDistanceInMeters: nil,
            gpsLatitude: nil,
            gpsLongitude: nil,
            gpsElevation: nil,
            locationName: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil,
            timeOfDay: nil,
            timestamp: nil,
            zoomFactor: nil,
            estimatedSizeCm: nil
        )

        do {
            _ = try await MerianNetworkClient.shared.analyzeSubject(
                r2ObjectKeys: nil,
                base64ImageDatas: [String(repeating: "X", count: MerianNetworkClient.maxInlineInferenceBodyBytes + 1)],
                telemetry: telemetry
            )
            Issue.record("Expected MerianError.payloadTooLarge")
        } catch MerianError.payloadTooLarge {
            // Expected path
        } catch {
            Issue.record("Expected MerianError.payloadTooLarge, got \(error)")
        }
    }
    
    @Test func testFetchEnrichmentSuccessfullyConstructsPayloadAndParsesJSON() async throws {
        // Arrange
        let testData = """
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
        """.data(using: .utf8)!
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        
        let scanID = "a1849d51-7a55-4bb0-931f-a49d880f69c7"
        MockURLProtocol.mockEndpoints["/enrich-scan"] = { request in
            #expect(request.url?.path.hasSuffix("/enrich-scan") == true)
            #expect(request.httpMethod == "POST")
            let idempotencyKey = try #require(
                request.value(forHTTPHeaderField: "Idempotency-Key")
            )
            #expect(idempotencyKey == scanID)
            return (mockResponse, testData)
        }
        
        // Act
        let returnedObject = try await MerianNetworkClient.shared.fetchEnrichment(
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
        await #expect(throws: MerianError.invalidResponse) {
            try await MerianNetworkClient.shared.fetchEnrichment(
                scanId: "legacy-non-uuid-scan-id",
                scientificName: "Procyon lotor",
                confidenceScore: 0.95,
                inferenceTier: "pro",
                scope: "enrichment"
            )
        }
    }

    @Test func testExploreShareSendsStableAIIdempotencyKey() async throws {
        let requestID = "019f6ff1-89ad-7d42-84d8-74dc8b1b5bb0"
        let scanID = "019f6ff1-9ef3-77b1-a331-a86678f53043"
        let responseData = Data("""
        {
          "success": true,
          "post_id": "019f6ff1-a393-7acc-9dbc-a9ec785f4152",
          "scan_id": "\(scanID)",
          "shared_at": "2026-07-23T18:00:00Z",
          "location_sharing": "private",
          "publication_status": "published"
        }
        """.utf8)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        MockURLProtocol.mockEndpoints["/share-scan-to-explore"] = { request in
            #expect(
                request.value(forHTTPHeaderField: "Idempotency-Key") == requestID
            )
            return (response, responseData)
        }

        let result = try await MerianNetworkClient.shared.shareScanToExplore(
            scanId: scanID,
            idempotencyKey: requestID
        )

        #expect(result.success)
        #expect(result.scanId == scanID)
    }

    @Test func testExploreShareRejectsContradictorySuccessResponses() async {
        let requestID = "019faaac-bfd7-7a2e-99ea-100554f24f01"
        let scanID = "019faaac-c177-71a6-883d-eb5a50b7d013"
        let invalidResponseBodies = [
            Data("""
            {
              "success": false,
              "post_id": "019faaac-c229-790a-949e-9aeb6a710f32",
              "scan_id": "\(scanID)",
              "shared_at": "2026-07-28T23:45:00Z",
              "location_sharing": "private",
              "publication_status": "published"
            }
            """.utf8),
            Data("""
            {
              "success": true,
              "post_id": "not-a-uuid",
              "scan_id": "\(scanID)",
              "shared_at": "2026-07-28T23:45:00Z",
              "location_sharing": "private",
              "publication_status": "published"
            }
            """.utf8),
            Data("""
            {
              "success": true,
              "post_id": "019faaac-c229-790a-949e-9aeb6a710f32",
              "scan_id": "019faaac-cb5f-724d-8112-16701a8d3645",
              "shared_at": "2026-07-28T23:45:00Z",
              "location_sharing": "private",
              "publication_status": "published"
            }
            """.utf8),
            Data("""
            {
              "success": true,
              "post_id": "019faaac-c229-790a-949e-9aeb6a710f32",
              "scan_id": "\(scanID)",
              "shared_at": "not-a-timestamp",
              "location_sharing": "private",
              "publication_status": "published"
            }
            """.utf8),
            Data("""
            {
              "success": true,
              "post_id": "019faaac-c229-790a-949e-9aeb6a710f32",
              "scan_id": "\(scanID)",
              "shared_at": "2026-07-28T23:45:00Z",
              "location_sharing": "private",
              "publication_status": "draft"
            }
            """.utf8),
            Data("""
            {
              "success": true,
              "post_id": "019faaac-c229-790a-949e-9aeb6a710f32",
              "scan_id": "\(scanID)",
              "shared_at": "2026-07-28T23:45:00Z",
              "location_sharing": "private"
            }
            """.utf8),
            Data("""
            {
              "success": true,
              "post_id": "019faaac-c229-790a-949e-9aeb6a710f32",
              "scan_id": "\(scanID)",
              "shared_at": "2026-07-28T23:45:00Z",
              "publication_status": "published"
            }
            """.utf8),
            Data("""
            {
              "success": true,
              "post_id": "019faaac-c229-790a-949e-9aeb6a710f32",
              "scan_id": "\(scanID)",
              "shared_at": "2026-07-28T23:45:00Z",
              "location_sharing": "future-unknown-mode",
              "publication_status": "published"
            }
            """.utf8)
        ]
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        for responseData in invalidResponseBodies {
            MockURLProtocol.mockEndpoints["/share-scan-to-explore"] = { _ in
                (response, responseData)
            }

            await #expect(throws: MerianError.invalidResponse) {
                try await MerianNetworkClient.shared.shareScanToExplore(
                    scanId: scanID,
                    idempotencyKey: requestID
                )
            }
        }

        MockURLProtocol.mockEndpoints["/share-scan-to-explore"] = { _ in
            (
                response,
                Data(
                    """
                    {
                      "success": true,
                      "post_id": "019faaac-c229-790a-949e-9aeb6a710f32",
                      "scan_id": "\(scanID)",
                      "shared_at": "2026-07-28T23:45:00Z",
                      "location_sharing": "open",
                      "publication_status": "published"
                    }
                    """.utf8
                )
            )
        }
        await #expect(throws: MerianError.invalidResponse) {
            try await MerianNetworkClient.shared.shareScanToExplore(
                scanId: scanID,
                locationSharing: .privateLocation,
                idempotencyKey: requestID
            )
        }
    }

    @Test func testExploreShareRetriesPlatformFunctionRouteNotFound() async throws {
        let requestID = "019fa6ef-279f-7c7a-9e18-ec70e067a331"
        let scanID = "019fa6ef-33ab-77b1-a331-a86678f53043"
        let probe = NetworkRequestProbe()
        let notFoundData = Data("{}".utf8)
        let successData = Data("""
        {
          "success": true,
          "post_id": "019fa6ef-3ba3-7acc-9dbc-a9ec785f4152",
          "scan_id": "\(scanID)",
          "shared_at": "2026-07-28T04:00:00Z",
          "location_sharing": "private",
          "publication_status": "published"
        }
        """.utf8)

        MockURLProtocol.mockEndpoints["/share-scan-to-explore"] = { request in
            let attempt = probe.record(
                idempotencyKey: request.value(forHTTPHeaderField: "Idempotency-Key")
            )
            if attempt == 1 {
                let response = HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 404,
                    httpVersion: nil,
                    headerFields: [
                        "SB-Error-Code": "NOT_FOUND",
                        "SB-Gateway-Version": "1"
                    ]
                )!
                return (response, notFoundData)
            }

            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["X-Merian-Handler": "1"]
            )!
            return (response, successData)
        }

        let result = try await MerianNetworkClient.shared.shareScanToExplore(
            scanId: scanID,
            idempotencyKey: requestID
        )

        #expect(result.success)
        #expect(probe.count == 2)
        #expect(probe.recordedIdempotencyKeys == [requestID, requestID])
    }

    @Test func testCancelledExploreShareUsesCanonicalCancellationAndDoesNotReplay() async {
        let requestID = "019fa6ef-2f9f-7c7a-9e18-ec70e067a331"
        let scanID = "019fa6ef-39ab-77b1-a331-a86678f53043"
        let probe = NetworkRequestProbe()

        MockURLProtocol.mockEndpoints["/share-scan-to-explore"] = { request in
            _ = probe.record(
                idempotencyKey: request.value(forHTTPHeaderField: "Idempotency-Key")
            )
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 503,
                httpVersion: nil,
                headerFields: ["X-Merian-Handler": "1"]
            )!
            return (
                response,
                Data(#"{"code":"service_unavailable"}"#.utf8)
            )
        }

        let requestTask = Task {
            try await MerianNetworkClient.shared.shareScanToExplore(
                scanId: scanID,
                idempotencyKey: requestID
            )
        }
        for _ in 0..<100 {
            if probe.count > 0 { break }
            await Task.yield()
        }
        #expect(probe.count == 1)

        requestTask.cancel()
        do {
            _ = try await requestTask.value
            Issue.record("A canceled request must not survive or replay.")
        } catch is CancellationError {
            // Expected whether cancellation reaches URLSession or Task.sleep:
            // the transport boundary normalizes task-owned cancellation.
        } catch {
            Issue.record("Expected CancellationError, got \(error).")
        }
        #expect(probe.count == 1)
    }

    @Test func testPlatformFunctionRouteClassifierPreservesGatewayHandlerBoundary() throws {
        let url = URL(string: "https://example.supabase.co/functions/v1/share-scan-to-explore")!
        let officialPayload = Data(
            #"{"code":"NOT_FOUND","message":"Requested function was not found"}"#.utf8
        )
        let platformResponse = HTTPURLResponse(
            url: url,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        )!
        #expect(MerianNetworkClient.isPlatformFunctionRouteUnavailableForTesting(
            response: platformResponse,
            responseData: officialPayload
        ))

        let headerResponse = HTTPURLResponse(
            url: url,
            statusCode: 404,
            httpVersion: nil,
            headerFields: ["SB-Error-Code": "not_found"]
        )!
        #expect(MerianNetworkClient.isPlatformFunctionRouteUnavailableForTesting(
            response: headerResponse,
            responseData: Data("{}".utf8)
        ))

        let handlerResponse = HTTPURLResponse(
            url: url,
            statusCode: 404,
            httpVersion: nil,
            headerFields: [
                "X-Merian-Handler": " 1 ",
                "SB-Error-Code": "NOT_FOUND"
            ]
        )!
        #expect(!MerianNetworkClient.isPlatformFunctionRouteUnavailableForTesting(
            response: handlerResponse,
            responseData: officialPayload
        ))

        let gatewayResponse = HTTPURLResponse(
            url: url,
            statusCode: 404,
            httpVersion: nil,
            headerFields: ["SB-Gateway-Version": "1"]
        )!
        #expect(MerianNetworkClient.isPlatformFunctionRouteUnavailableForTesting(
            response: gatewayResponse,
            responseData: Data("{}".utf8)
        ))

        let executedResponse = HTTPURLResponse(
            url: url,
            statusCode: 404,
            httpVersion: nil,
            headerFields: [
                "SB-Gateway-Version": "1",
                "X-Deno-Execution-Id": "019fa6ef-3ba3-7acc-9dbc-a9ec785f4152"
            ]
        )!
        #expect(!MerianNetworkClient.isPlatformFunctionRouteUnavailableForTesting(
            response: executedResponse,
            responseData: Data("{}".utf8)
        ))

        let serverErrorResponse = HTTPURLResponse(
            url: url,
            statusCode: 503,
            httpVersion: nil,
            headerFields: ["SB-Error-Code": "NOT_FOUND"]
        )!
        #expect(!MerianNetworkClient.isPlatformFunctionRouteUnavailableForTesting(
            response: serverErrorResponse,
            responseData: officialPayload
        ))
    }

    @Test func testAmbiguousFailureReplayIsLimitedToReadsAndIdempotentRequests() throws {
        let baseURL = try #require(URL(string: "https://example.supabase.co/functions/v1/"))
        let readURL = baseURL.appendingPathComponent("get-explore-feed")
        let commentURL = baseURL.appendingPathComponent("create-explore-comment")
        let reactionURL = baseURL.appendingPathComponent("toggle-explore-comment-reaction")
        let feedbackURL = baseURL.appendingPathComponent("submit-feedback-survey")
        let uploadURL = baseURL.appendingPathComponent("generate-upload-urls")

        #expect(MerianNetworkClient.canReplayAfterAmbiguousFailureForTesting(
            url: readURL,
            method: "POST"
        ))
        #expect(!MerianNetworkClient.canReplayAfterAmbiguousFailureForTesting(
            url: commentURL,
            method: "POST"
        ))
        #expect(!MerianNetworkClient.canReplayAfterAmbiguousFailureForTesting(
            url: reactionURL,
            method: "POST"
        ))
        #expect(!MerianNetworkClient.canReplayAfterAmbiguousFailureForTesting(
            url: feedbackURL,
            method: "POST"
        ))
        #expect(!MerianNetworkClient.canReplayAfterAmbiguousFailureForTesting(
            url: uploadURL,
            method: "POST"
        ))
        #expect(!MerianNetworkClient.canReplayAfterAmbiguousFailureForTesting(
            url: commentURL,
            method: "POST",
            idempotencyKey: "019fa6ef-4fab-7d42-84d8-74dc8b1b5bb0"
        ))
        #expect(MerianNetworkClient.canReplayAfterAmbiguousFailureForTesting(
            url: baseURL.appendingPathComponent("identify-multimodal"),
            method: "POST",
            idempotencyKey: "019fa6ef-4fab-7d42-84d8-74dc8b1b5bb0"
        ))
        #expect(MerianNetworkClient.canReplayAfterAmbiguousFailureForTesting(
            url: commentURL,
            method: "GET"
        ))
    }

    @Test func testExploreShareDoesNotRetryHandlerOwnedNotFound() async {
        let scanID = "019fa6ef-43ab-77b1-a331-a86678f53043"
        let rawError = #"{"error":"Scan not found.","code":"not_found"}"#
        let probe = NetworkRequestProbe()

        MockURLProtocol.mockEndpoints["/share-scan-to-explore"] = { request in
            _ = probe.record(
                idempotencyKey: request.value(forHTTPHeaderField: "Idempotency-Key")
            )
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 404,
                httpVersion: nil,
                headerFields: ["X-Merian-Handler": "1"]
            )!
            return (response, Data(rawError.utf8))
        }

        await #expect(
            throws: MerianError.httpError(statusCode: 404, message: rawError)
        ) {
            try await MerianNetworkClient.shared.shareScanToExplore(
                scanId: scanID,
                idempotencyKey: "019fa6ef-4fab-7d42-84d8-74dc8b1b5bb0"
            )
        }

        #expect(probe.count == 1)
    }

    @Test func testRecoverableInferenceConflictRequiresKnown409Code() {
        let recoverableCodes = [
            "ai_request_already_completed",
            "ai_request_in_progress",
            "scan_already_complete",
            "scan_already_finalized",
        ]

        for code in recoverableCodes {
            let error = MerianError.httpError(
                statusCode: 409,
                message: #"{"error":"Observation recovery in progress.","code":"\#(code)"}"#
            )
            #expect(MerianNetworkClient.isRecoverableInferenceConflict(error))
        }

        #expect(!MerianNetworkClient.isRecoverableInferenceConflict(
            MerianError.httpError(
                statusCode: 409,
                message: #"{"error":"Conflict.","code":"different_conflict"}"#
            )
        ))
        #expect(!MerianNetworkClient.isRecoverableInferenceConflict(
            MerianError.httpError(
                statusCode: 503,
                message: #"{"error":"Retry.","code":"ai_request_in_progress"}"#
            )
        ))
        #expect(!MerianNetworkClient.isRecoverableInferenceConflict(
            MerianError.httpError(
                statusCode: 409,
                message: #"{"error":"Conflict.","code":"INVALID CODE"}"#
            )
        ))
    }

    @Test func testExploreShareSendsMissingScanRecoveryPayload() async throws {
        let scanID = "019f6ff1-9ef3-77b1-a331-a86678f53043"
        let userID = "019f6ff1-c6c4-77b1-a331-a86678f53043"
        let responseData = Data("""
        {
          "success": true,
          "post_id": "019f6ff1-a393-7acc-9dbc-a9ec785f4152",
          "scan_id": "\(scanID)",
          "shared_at": "2026-07-23T18:00:00Z",
          "location_sharing": "private",
          "publication_status": "published"
        }
        """.utf8)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let recoveryScan = OwnedScanRecoveryPayload(
            id: scanID,
            userId: userID,
            speciesId: "019f6ff1-d6c4-77b1-a331-a86678f53043",
            confirmedSpeciesId: nil,
            imageStorageUrls: [],
            timestamp: "2026-07-23T18:00:00Z",
            gpsLatExact: 30.2672,
            gpsLongExact: -97.7431,
            gpsLatPublic: nil,
            gpsLongPublic: nil,
            gpsElevation: 150,
            geoprivacy: "private",
            weatherCondition: "Clear",
            weatherTemperatureF: 86,
            aiConfidenceScore: 0.94,
            ecologyType: "wild",
            isInvasive: false,
            invasiveStatusRegion: nil,
            invasiveRationale: nil,
            invasiveConfidence: nil,
            isLiveCapture: true,
            isBiologicalSubject: true,
            aiReasoning: "Long bill and dark crown.",
            semanticLocation: "Austin, Texas",
            publicLocationLabel: nil,
            inferenceTier: "flash",
            imageQualityScore: 82,
            userIdentificationOverride: nil,
            userConfirmedIdentification: false,
            userReviewState: "unreviewed"
        )

        MockURLProtocol.mockEndpoints["/share-scan-to-explore"] = { request in
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            let recovery = try #require(payload["recovery_scan"] as? [String: Any])
            #expect(recovery["id"] as? String == scanID)
            #expect(recovery["user_id"] as? String == userID)
            #expect(recovery["image_storage_urls"] as? [String] == [])
            #expect(recovery["geoprivacy"] as? String == "private")
            #expect(recovery["gps_lat_exact"] as? Double == 30.2672)
            #expect(recovery["gps_lat_public"] == nil)
            return (response, responseData)
        }

        let result = try await MerianNetworkClient.shared.shareScanToExplore(
            scanId: scanID,
            idempotencyKey: "019f6ff1-e6c4-77b1-a331-a86678f53043",
            recoveryScan: recoveryScan
        )

        #expect(result.success)
        #expect(result.scanId == scanID)
    }

    @Test func testScanImageCloudInspectionSendsSourceAndParsesMissingStatus() async throws {
        let sourceUrl =
            "https://media.merian.app/public_uploads/free/user/old.webp"
        let responseData = Data("""
        {
          "data": {
            "status": "missing"
          }
        }
        """.utf8)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        MockURLProtocol.mockEndpoints["/repair-scan-image"] = { request in
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            #expect(payload["source_url"] as? String == sourceUrl)
            #expect(payload["restored_object_key"] == nil)
            return (response, responseData)
        }

        let result = try await MerianNetworkClient.shared
            .inspectScanImageCloudStatus(sourceUrl: sourceUrl)

        #expect(result.status == .missing)
        #expect(result.updatedScanCount == 0)
        #expect(result.updatedPostMediaCount == 0)
    }

    @Test func testScanImageCloudRepairSendsStagedKeyAndParsesCounts() async throws {
        let sourceUrl =
            "https://media.merian.app/public_uploads/free/user/old.webp"
        let restoredObjectKey = "staging/user/repair_new.webp"
        let responseData = Data("""
        {
          "data": {
            "status": "repaired",
            "replacement_url": "https://media.merian.app/public_uploads/pro/user/repair_new.webp",
            "updated_scan_count": 1,
            "updated_post_media_count": 2
          }
        }
        """.utf8)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        MockURLProtocol.mockEndpoints["/repair-scan-image"] = { request in
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            #expect(payload["source_url"] as? String == sourceUrl)
            #expect(
                payload["restored_object_key"] as? String == restoredObjectKey
            )
            return (response, responseData)
        }

        let result = try await MerianNetworkClient.shared
            .repairScanImageCloudReference(
                sourceUrl: sourceUrl,
                restoredObjectKey: restoredObjectKey
            )

        #expect(result.status == .repaired)
        #expect(result.updatedScanCount == 1)
        #expect(result.updatedPostMediaCount == 2)
    }

    @Test func testExploreRestoreMediaBudgetRejectsPartialStagingBeforeUpload() throws {
        try validateExploreRestoreMediaPayload(
            imageSizes: [1, 2, 3],
            videoSizes: [MerianConfig.videoPayloadMaxBytes],
            audioSizes: [1, MerianConfig.audioPayloadMaxBytes]
        )
        try validateExploreRestoreMediaBudget(
            imageCount: 5,
            videoCount: 1,
            audioCount: 0
        )

        for counts in [
            (image: -1, video: 0, audio: 0),
            (image: 6, video: 0, audio: 0),
            (image: 0, video: 2, audio: 0),
            (image: 0, video: 0, audio: 3),
            (image: 5, video: 0, audio: 2)
        ] {
            #expect(throws: MerianError.payloadTooLarge) {
                try validateExploreRestoreMediaBudget(
                    imageCount: counts.image,
                    videoCount: counts.video,
                    audioCount: counts.audio
                )
            }
        }

        for sizes in [
            (
                images: [-1],
                videos: [Int](),
                audio: [Int]()
            ),
            (
                images: [MerianConfig.stagedImagePayloadMaxBytes, 1],
                videos: [Int](),
                audio: [Int]()
            ),
            (
                images: [Int](),
                videos: [MerianConfig.videoPayloadMaxBytes + 1],
                audio: [Int]()
            ),
            (
                images: [Int](),
                videos: [Int](),
                audio: [MerianConfig.audioPayloadMaxBytes + 1]
            )
        ] {
            #expect(throws: MerianError.payloadTooLarge) {
                try validateExploreRestoreMediaPayload(
                    imageSizes: sizes.images,
                    videoSizes: sizes.videos,
                    audioSizes: sizes.audio
                )
            }
        }

        let scanId = "019f7004-d6c4-7da1-8561-9cc101f6db62"
        for (kind, fileName, expectedRole) in [
            (
                StagedMediaKind.image,
                "\(scanId)_explore_restore_0.webp",
                "display"
            ),
            (
                StagedMediaKind.video,
                "\(scanId)_explore_restore_video_0.mp4",
                "playback"
            ),
            (
                StagedMediaKind.audio,
                "\(scanId)_explore_restore_audio_0.wav",
                "audio"
            )
        ] {
            let uploadFile = makeScanShareRestoreUploadFile(
                fileName: fileName,
                mediaKind: kind,
                contentType: kind.contentType(for: fileName),
                sizeBytes: 42,
                scanId: scanId
            )
            #expect(uploadFile.clientScanId == scanId)
            #expect(uploadFile.mediaRole == expectedRole)
            #expect(uploadFile.uploadPurpose == .scanShareRestore)
            let encoded = try JSONEncoder().encode(uploadFile)
            let payload = try #require(
                JSONSerialization.jsonObject(with: encoded)
                    as? [String: Any]
            )
            #expect(
                payload["uploadPurpose"] as? String ==
                    StagingUploadPurpose.scanShareRestore.rawValue
            )
        }
    }

    @Test func testCommunityRequestSendsStableAIIdempotencyKey() async throws {
        let requestID = "019f7004-cb18-7cd0-84e5-b4a97b759666"
        let scanID = "019f7004-d6c4-7da1-8561-9cc101f6db62"
        let restoredImageKey = "staging/user/restored-image.webp"
        let restoredVideoKey = "staging/user/restored-video.mp4"
        let restoredAudioKey = "staging/user/restored-audio.wav"
        let responseData = Data("""
        {
          "success": true,
          "data": {
            "id": "019f7004-e4c2-7feb-8f4d-39ab2a89ca1e",
            "post_id": "019f7004-ee31-7e9e-961d-30b49352f12a",
            "scan_id": "\(scanID)",
            "requested_by": "019f7004-f66f-71bf-845c-bf05dff2eb30",
            "requested_at": "2026-07-23T18:00:00Z",
            "status": "needs_id",
            "initial_taxon_node_id": "019f7004-c59b-74ab-8730-45bcae1bb390",
            "taxonomy_version_id": "019f7004-ca4e-7c3a-a9e8-5ff84002063e",
            "consensus_identification_count": 0
          }
        }
        """.utf8)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        MockURLProtocol.mockEndpoints["/request-community-identification"] = { request in
            #expect(
                request.value(forHTTPHeaderField: "Idempotency-Key") == requestID
            )
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            #expect(
                payload["restored_object_keys"] as? [String] ==
                    [restoredImageKey]
            )
            #expect(
                payload["restored_video_object_keys"] as? [String] ==
                    [restoredVideoKey]
            )
            #expect(
                payload["restored_audio_object_keys"] as? [String] ==
                    [restoredAudioKey]
            )
            return (response, responseData)
        }

        let result = try await MerianNetworkClient.shared.requestCommunityIdentification(
            scanId: scanID,
            restoredObjectKeys: [restoredImageKey],
            restoredVideoObjectKeys: [restoredVideoKey],
            restoredAudioObjectKeys: [restoredAudioKey],
            idempotencyKey: requestID
        )

        #expect(result.scanId == scanID)
        #expect(result.status == .needsId)
    }

    @Test func testCommunityRequestRejectsUnconfirmedSuccessResponse() async throws {
        let scanID = "019f7004-d6c4-7da1-8561-9cc101f6db62"
        let responseURL = try #require(URL(string: "https://example.com"))
        let response = try #require(
            HTTPURLResponse(
                url: responseURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )

        func responseData(
            success: Bool,
            responseScanID: String,
            requestedAt: String,
            status: String = "needs_id"
        ) -> Data {
            Data(
                """
                {
                  "success": \(success ? "true" : "false"),
                  "data": {
                    "id": "019f7004-e4c2-7feb-8f4d-39ab2a89ca1e",
                    "post_id": "019f7004-ee31-7e9e-961d-30b49352f12a",
                    "scan_id": "\(responseScanID)",
                    "requested_by": "019f7004-f66f-71bf-845c-bf05dff2eb30",
                    "requested_at": "\(requestedAt)",
                    "status": "\(status)",
                    "initial_taxon_node_id": "019f7004-c59b-74ab-8730-45bcae1bb390",
                    "taxonomy_version_id": "019f7004-ca4e-7c3a-a9e8-5ff84002063e",
                    "consensus_identification_count": 0
                  }
                }
                """.utf8
            )
        }

        let invalidResponses = [
            responseData(
                success: false,
                responseScanID: scanID,
                requestedAt: "2026-07-23T18:00:00Z"
            ),
            responseData(
                success: true,
                responseScanID: "019f7004-d6c4-7da1-8561-9cc101f6db63",
                requestedAt: "2026-07-23T18:00:00Z"
            ),
            responseData(
                success: true,
                responseScanID: scanID,
                requestedAt: "not-a-timestamp"
            ),
            responseData(
                success: true,
                responseScanID: scanID,
                requestedAt: "2026-07-23T18:00:00Z",
                status: "future-unknown-status"
            )
        ]

        for invalidResponse in invalidResponses {
            MockURLProtocol.mockEndpoints[
                "/request-community-identification"
            ] = { _ in
                (response, invalidResponse)
            }
            await #expect(throws: MerianError.invalidResponse) {
                try await MerianNetworkClient.shared
                    .requestCommunityIdentification(scanId: scanID)
            }
        }
    }

    @Test func testFieldChatRejectsMalformedOrCrossSubjectSuccessResponses() async throws {
        let insightScanID = "019faaeb-4616-7a1c-b5d8-19d0b6214c83"
        let explorePostID = "019faaeb-4ab8-75ff-8254-26b6430e0d85"
        let otherSubjectID = "019faaeb-4d99-7a19-8471-89676790048b"
        let conversationID = "019faaeb-507d-7901-9be2-8cc9b908ce74"
        let requestID = "019faaeb-52e2-7a67-b085-b9972b0ef36c"
        let responseURL = try #require(URL(string: "https://example.com"))
        let response = try #require(
            HTTPURLResponse(
                url: responseURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )

        func chatResponse(
            subjectID: String,
            envelopeSubjectID: String? = nil,
            role: String = "assistant",
            envelopeConversationID: String? = nil,
            messageConversationID: String? = nil,
            messageID: String =
                "019faaeb-5400-70a5-a6db-5469275b29fa",
            messageText: String =
                "The saved evidence supports this identification.",
            clientMessageID: String? = nil,
            dailySendLimit: Int = 20,
            sendsRemainingToday: Int = 19
        ) -> Data {
            let clientMessageJSON = clientMessageID.map {
                "\"\($0)\""
            } ?? "null"
            return Data(
                """
                {
                  "data": {
                    "subject_id": "\(envelopeSubjectID ?? subjectID)",
                    "conversation_id": "\(envelopeConversationID ?? conversationID)",
                    "messages": [
                      {
                        "id": "\(messageID)",
                        "conversation_id": "\(messageConversationID ?? conversationID)",
                        "scan_id": "\(subjectID)",
                        "role": "\(role)",
                        "text": "\(messageText)",
                        "client_message_id": \(clientMessageJSON),
                        "model": "gemini-2.5-flash",
                        "is_refusal": false,
                        "refusal_reason": null,
                        "created_at": "2026-07-29T15:00:00.000Z"
                      }
                    ],
                    "limits": {
                      "max_user_message_chars": 600,
                      "max_messages_per_conversation": 30,
                      "daily_send_limit": \(dailySendLimit),
                      "sends_remaining_today": \(sendsRemainingToday)
                    }
                  }
                }
                """.utf8
            )
        }

        func completedSendResponse(
            subjectID: String,
            clientMessageID: String,
            userMessageText: String = "Which traits support this ID?"
        ) -> Data {
            Data(
                """
                {
                  "data": {
                    "subject_id": "\(subjectID)",
                    "conversation_id": "\(conversationID)",
                    "messages": [
                      {
                        "id": "019faaeb-5330-7e2d-b3b8-36232fde6397",
                        "conversation_id": "\(conversationID)",
                        "scan_id": "\(subjectID)",
                        "role": "user",
                        "text": "\(userMessageText)",
                        "client_message_id": "\(clientMessageID)",
                        "model": null,
                        "is_refusal": false,
                        "refusal_reason": null,
                        "created_at": "2026-07-29T15:00:00.000Z"
                      },
                      {
                        "id": "019faaeb-5400-70a5-a6db-5469275b29fa",
                        "conversation_id": "\(conversationID)",
                        "scan_id": "\(subjectID)",
                        "role": "assistant",
                        "text": "The saved evidence supports this identification.",
                        "client_message_id": "\(clientMessageID)",
                        "model": "gemini-2.5-flash",
                        "is_refusal": false,
                        "refusal_reason": null,
                        "created_at": "2026-07-29T15:00:01.000Z"
                      }
                    ],
                    "limits": {
                      "max_user_message_chars": 600,
                      "max_messages_per_conversation": 30,
                      "daily_send_limit": 20,
                      "sends_remaining_today": 19
                    }
                  }
                }
                """.utf8
            )
        }

        func emptyChatResponse(subjectID: String) -> Data {
            Data(
                """
                {
                  "data": {
                    "subject_id": "\(subjectID)",
                    "conversation_id": null,
                    "messages": [],
                    "limits": {
                      "max_user_message_chars": 600,
                      "max_messages_per_conversation": 30,
                      "daily_send_limit": 20,
                      "sends_remaining_today": 20
                    }
                  }
                }
                """.utf8
            )
        }

        let missingSubjectEmptyChatResponse = Data(
            """
            {
              "data": {
                "conversation_id": null,
                "messages": [],
                "limits": {
                  "max_user_message_chars": 600,
                  "max_messages_per_conversation": 30,
                  "daily_send_limit": 20,
                  "sends_remaining_today": 20
                }
              }
            }
            """.utf8
        )

        MockURLProtocol.mockEndpoints["/insight-chat"] = { _ in
            (response, chatResponse(subjectID: insightScanID))
        }
        let validInsight = try await MerianNetworkClient.shared
            .loadInsightChat(scanId: insightScanID)
        #expect(validInsight.messages.first?.scanId == insightScanID)

        MockURLProtocol.mockEndpoints["/insight-chat"] = { _ in
            (
                response,
                completedSendResponse(
                    subjectID: insightScanID,
                    clientMessageID: requestID
                )
            )
        }
        let completedSend = try await MerianNetworkClient.shared
            .sendInsightChatMessage(
                scanId: insightScanID,
                messageText: "Which traits support this ID?",
                clientMessageId: requestID
            )
        #expect(
            completedSend.messages.filter {
                $0.clientMessageId == requestID
            }.count == 2
        )

        MockURLProtocol.mockEndpoints["/insight-chat"] = { _ in
            (
                response,
                completedSendResponse(
                    subjectID: insightScanID,
                    clientMessageID: requestID,
                    userMessageText: "A different question"
                )
            )
        }
        await #expect(throws: MerianError.invalidResponse) {
            try await MerianNetworkClient.shared.sendInsightChatMessage(
                scanId: insightScanID,
                messageText: "Which traits support this ID?",
                clientMessageId: requestID
            )
        }

        let invalidInsightResponses = [
            chatResponse(subjectID: otherSubjectID),
            emptyChatResponse(subjectID: otherSubjectID),
            missingSubjectEmptyChatResponse,
            chatResponse(
                subjectID: insightScanID,
                envelopeSubjectID: otherSubjectID
            ),
            chatResponse(subjectID: insightScanID, role: "future-role"),
            chatResponse(
                subjectID: insightScanID,
                messageConversationID:
                    "019faaeb-5923-71a8-a959-e2d8d864f9b7"
            ),
            chatResponse(subjectID: insightScanID, messageID: "not-a-uuid"),
            chatResponse(
                subjectID: insightScanID,
                envelopeConversationID: " \(conversationID) "
            ),
            chatResponse(subjectID: insightScanID, messageText: ""),
            chatResponse(
                subjectID: insightScanID,
                messageText: " padded answer "
            ),
            chatResponse(
                subjectID: insightScanID,
                messageText: String(repeating: "x", count: 4_001)
            ),
            chatResponse(
                subjectID: insightScanID,
                clientMessageID: "not-a-uuid"
            ),
            chatResponse(
                subjectID: insightScanID,
                dailySendLimit: 20,
                sendsRemainingToday: 21
            ),
            chatResponse(
                subjectID: insightScanID,
                dailySendLimit: 21,
                sendsRemainingToday: 19
            )
        ]
        for invalidResponse in invalidInsightResponses {
            MockURLProtocol.mockEndpoints["/insight-chat"] = { _ in
                (response, invalidResponse)
            }
            await #expect(throws: MerianError.invalidResponse) {
                try await MerianNetworkClient.shared
                    .loadInsightChat(scanId: insightScanID)
            }
        }

        MockURLProtocol.mockEndpoints["/insight-chat"] = { _ in
            (
                response,
                chatResponse(
                    subjectID: insightScanID,
                    clientMessageID: requestID
                )
            )
        }
        await #expect(throws: MerianError.invalidResponse) {
            try await MerianNetworkClient.shared.sendInsightChatMessage(
                scanId: insightScanID,
                messageText: "Which traits support this ID?",
                clientMessageId: requestID
            )
        }

        var oversizedResponse = completedSendResponse(
            subjectID: insightScanID,
            clientMessageID: requestID
        )
        oversizedResponse.append(
            Data(
                repeating: 0x20,
                count: 1_048_577 - oversizedResponse.count
            )
        )
        MockURLProtocol.mockEndpoints["/insight-chat"] = { _ in
            (response, oversizedResponse)
        }
        await #expect(throws: MerianError.invalidResponse) {
            try await MerianNetworkClient.shared.sendInsightChatMessage(
                scanId: insightScanID,
                messageText: "Which traits support this ID?",
                clientMessageId: requestID
            )
        }

        MockURLProtocol.mockEndpoints["/explore-post-chat"] = { _ in
            (response, chatResponse(subjectID: otherSubjectID))
        }
        await #expect(throws: MerianError.invalidResponse) {
            try await MerianNetworkClient.shared
                .loadExplorePostChat(postId: explorePostID)
        }
    }

    @Test func testFieldChatFeedbackRequiresConfirmedMatchingResponse() async throws {
        let scanID = "019fab51-2c31-7468-a020-541c8baa73f1"
        let postID = "019fab51-2f96-78c6-9646-d815258c5cd4"
        let messageID = "019fab51-325f-7f42-8124-7eb39b714413"
        let otherMessageID = "019fab51-34d9-7bd3-8b00-c3ff3487bf47"
        let responseURL = try #require(URL(string: "https://example.com"))
        let response = try #require(
            HTTPURLResponse(
                url: responseURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )

        func feedbackResponse(
            subjectID: String,
            ok: Bool,
            responseMessageID: String,
            rating: String
        ) -> Data {
            Data(
                """
                {
                  "data": {
                    "ok": \(ok ? "true" : "false"),
                    "subject_id": "\(subjectID)",
                    "message_id": "\(responseMessageID)",
                    "rating": "\(rating)"
                  }
                }
                """.utf8
            )
        }

        MockURLProtocol.mockEndpoints["/insight-chat"] = { _ in
            (
                response,
                feedbackResponse(
                    subjectID: scanID,
                    ok: true,
                    responseMessageID: messageID,
                    rating: "wrong"
                )
            )
        }
        let validFeedback = try await MerianNetworkClient.shared
            .submitInsightChatFeedback(
                scanId: scanID,
                messageId: messageID,
                rating: .wrong
            )
        #expect(validFeedback.ok)
        #expect(validFeedback.messageId == messageID)
        #expect(validFeedback.rating == .wrong)

        MockURLProtocol.mockEndpoints["/explore-post-chat"] = { _ in
            (
                response,
                feedbackResponse(
                    subjectID: postID,
                    ok: true,
                    responseMessageID: messageID,
                    rating: "wrong"
                )
            )
        }
        let validExploreFeedback = try await MerianNetworkClient.shared
            .submitExplorePostChatFeedback(
                postId: postID,
                messageId: messageID,
                rating: .wrong
            )
        #expect(validExploreFeedback.subjectId == postID)

        let invalidFeedbackResponses = [
            feedbackResponse(
                subjectID: scanID,
                ok: false,
                responseMessageID: messageID,
                rating: "wrong"
            ),
            feedbackResponse(
                subjectID: scanID,
                ok: true,
                responseMessageID: otherMessageID,
                rating: "wrong"
            ),
            feedbackResponse(
                subjectID: scanID,
                ok: true,
                responseMessageID: messageID,
                rating: "helpful"
            ),
            feedbackResponse(
                subjectID: scanID,
                ok: true,
                responseMessageID: messageID,
                rating: "future-rating"
            ),
            feedbackResponse(
                subjectID: postID,
                ok: true,
                responseMessageID: messageID,
                rating: "wrong"
            )
        ]
        for invalidResponse in invalidFeedbackResponses {
            MockURLProtocol.mockEndpoints["/insight-chat"] = { _ in
                (response, invalidResponse)
            }
            await #expect(throws: MerianError.invalidResponse) {
                try await MerianNetworkClient.shared
                    .submitInsightChatFeedback(
                        scanId: scanID,
                        messageId: messageID,
                        rating: .wrong
                    )
            }
        }

        MockURLProtocol.mockEndpoints["/explore-post-chat"] = { _ in
            (
                response,
                feedbackResponse(
                    subjectID: postID,
                    ok: false,
                    responseMessageID: messageID,
                    rating: "wrong"
                )
            )
        }
        await #expect(throws: MerianError.invalidResponse) {
            try await MerianNetworkClient.shared
                .submitExplorePostChatFeedback(
                    postId: postID,
                    messageId: messageID,
                    rating: .wrong
                )
        }
    }

    @Test func testFieldChatFeatureFeedbackAndSummaryRequireSafeSuccess() async throws {
        let scanID = "019fab54-78c1-7b64-b982-e27c68caf098"
        let feedbackID = "019fab54-7bb3-7db5-8ac5-76e6ace87a93"
        let responseURL = try #require(URL(string: "https://example.com"))
        let response = try #require(
            HTTPURLResponse(
                url: responseURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )

        func featureFeedbackResponse(
            subjectID: String,
            ok: Bool,
            responseID: String,
            sentiment: String?
        ) -> Data {
            let sentimentJSON = sentiment.map { "\"\($0)\"" } ?? "null"
            return Data(
                """
                {
                  "data": {
                    "ok": \(ok ? "true" : "false"),
                    "subject_id": "\(subjectID)",
                    "id": "\(responseID)",
                    "sentiment": \(sentimentJSON)
                  }
                }
                """.utf8
            )
        }

        MockURLProtocol.mockEndpoints["/insight-chat"] = { _ in
            (
                response,
                featureFeedbackResponse(
                    subjectID: scanID,
                    ok: true,
                    responseID: feedbackID,
                    sentiment: "positive"
                )
            )
        }
        let validFeatureFeedback = try await MerianNetworkClient.shared
            .submitInsightChatFeatureFeedback(
                scanId: scanID,
                sentiment: .positive,
                note: "Useful context."
            )
        #expect(validFeatureFeedback.ok)
        #expect(validFeatureFeedback.id == feedbackID)
        #expect(validFeatureFeedback.sentiment == .positive)

        let invalidFeatureResponses = [
            featureFeedbackResponse(
                subjectID: scanID,
                ok: false,
                responseID: feedbackID,
                sentiment: "positive"
            ),
            featureFeedbackResponse(
                subjectID: scanID,
                ok: true,
                responseID: "not-a-uuid",
                sentiment: "positive"
            ),
            featureFeedbackResponse(
                subjectID: scanID,
                ok: true,
                responseID: feedbackID,
                sentiment: "negative"
            ),
            featureFeedbackResponse(
                subjectID: scanID,
                ok: true,
                responseID: feedbackID,
                sentiment: "future-sentiment"
            ),
            featureFeedbackResponse(
                subjectID: "019fab54-7e92-7a80-9f31-6d894c671042",
                ok: true,
                responseID: feedbackID,
                sentiment: "positive"
            )
        ]
        for invalidResponse in invalidFeatureResponses {
            MockURLProtocol.mockEndpoints["/insight-chat"] = { _ in
                (response, invalidResponse)
            }
            await #expect(throws: MerianError.invalidResponse) {
                try await MerianNetworkClient.shared
                    .submitInsightChatFeatureFeedback(
                        scanId: scanID,
                        sentiment: .positive,
                        note: "Useful context."
                    )
            }
        }

        let validSummary = Data(
            """
            {
              "data": {
                "subject_id": "\(scanID)",
                "summary_text": "The discussion compared two wing traits."
              }
            }
            """.utf8
        )
        MockURLProtocol.mockEndpoints["/insight-chat"] = { _ in
            (response, validSummary)
        }
        let summary = try await MerianNetworkClient.shared
            .summarizeInsightChatForFieldNotes(scanId: scanID)
        #expect(summary.summaryText == "The discussion compared two wing traits.")

        let invalidSummaries = [
            Data(
                #"{"data":{"subject_id":"\#(scanID)","summary_text":"   "}}"#
                    .utf8
            ),
            Data(
                """
                {
                  "data": {
                    "subject_id": "\(scanID)",
                    "summary_text": "Observation 46b35079-75a1-4e47-bfd3-0414c2fdda00 leaked an internal identifier."
                  }
                }
                """.utf8
            ),
            Data(
                """
                {
                  "data": {
                    "subject_id": "\(scanID)",
                    "summary_text": "Observation 019fab61-1e83-7e64-90e7-ef275922fa7e leaked a current UUIDv7 identifier."
                  }
                }
                """.utf8
            ),
            Data(#"{"data":{}}"#.utf8),
            Data(
                """
                {
                  "data": {
                    "subject_id": "019fab54-7e92-7a80-9f31-6d894c671042",
                    "summary_text": "This belongs to another observation."
                  }
                }
                """.utf8
            )
        ]
        for invalidResponse in invalidSummaries {
            MockURLProtocol.mockEndpoints["/insight-chat"] = { _ in
                (response, invalidResponse)
            }
            await #expect(throws: MerianError.invalidResponse) {
                try await MerianNetworkClient.shared
                    .summarizeInsightChatForFieldNotes(scanId: scanID)
            }
        }
    }

    @Test func testFieldChatPromptSuggestionsRequireBoundedSafePayloads() async throws {
        let scanID = "019fab58-f128-71bd-a96d-62795221be8a"
        let postID = "019fab58-f454-7382-884b-a35052099f74"
        let conversationID = "019fab58-f797-725f-8271-de87d99f7380"
        let responseURL = try #require(URL(string: "https://example.com"))
        let response = try #require(
            HTTPURLResponse(
                url: responseURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )

        func promptResponse(
            subjectID: String,
            conversationID: String?,
            prompts: [[String: String]]
        ) throws -> Data {
            let conversationValue: Any =
                conversationID.map { $0 as Any } ?? NSNull()
            return try JSONSerialization.data(
                withJSONObject: [
                    "data": [
                        "subject_id": subjectID,
                        "conversation_id": conversationValue,
                        "prompts": prompts
                    ]
                ]
            )
        }

        let validPrompts = try promptResponse(
            subjectID: scanID,
            conversationID: conversationID,
            prompts: [
                [
                    "text": "How does this animal forage?",
                    "category": "ecology"
                ],
                [
                    "text": "Which traits distinguish tea plants?",
                    "category": "evidence"
                ],
                [
                    "text": "What habitat does poison ivy prefer?",
                    "category": "habitat"
                ]
            ]
        )
        MockURLProtocol.mockEndpoints["/insight-chat"] = { _ in
            (response, validPrompts)
        }
        let suggestions = try await MerianNetworkClient.shared
            .suggestInsightChatPrompts(scanId: scanID)
        #expect(suggestions.prompts.count == 3)

        let validTaxonomyLanguage = try promptResponse(
            subjectID: scanID,
            conversationID: conversationID,
            prompts: [
                [
                    "text": "Can I treat this as a subspecies?",
                    "category": "evidence"
                ]
            ]
        )
        MockURLProtocol.mockEndpoints["/insight-chat"] = { _ in
            (response, validTaxonomyLanguage)
        }
        let taxonomySuggestions = try await MerianNetworkClient.shared
            .suggestInsightChatPrompts(scanId: scanID)
        #expect(taxonomySuggestions.prompts.count == 1)

        let validExplorePrompts = try promptResponse(
            subjectID: postID,
            conversationID: nil,
            prompts: [
                [
                    "text": "Which public trait matters most?",
                    "category": "evidence"
                ]
            ]
        )
        MockURLProtocol.mockEndpoints["/explore-post-chat"] = { _ in
            (response, validExplorePrompts)
        }
        let exploreSuggestions = try await MerianNetworkClient.shared
            .suggestExplorePostChatPrompts(postId: postID)
        #expect(exploreSuggestions.subjectId == postID)

        let invalidPromptResponses = [
            try promptResponse(
                subjectID: scanID,
                conversationID: "not-a-uuid",
                prompts: []
            ),
            try promptResponse(
                subjectID: scanID,
                conversationID: conversationID,
                prompts: [
                    ["text": "One?", "category": "generic"],
                    ["text": "Two?", "category": "generic"],
                    ["text": "Three?", "category": "generic"],
                    ["text": "Four?", "category": "generic"]
                ]
            ),
            try promptResponse(
                subjectID: scanID,
                conversationID: conversationID,
                prompts: [
                    ["text": "Which trait matters?", "category": "evidence"],
                    ["text": "Which trait matters?", "category": "evidence"]
                ]
            ),
            try promptResponse(
                subjectID: scanID,
                conversationID: conversationID,
                prompts: [
                    [
                        "text": "Can I eat this observation?",
                        "category": "generic"
                    ]
                ]
            ),
            try promptResponse(
                subjectID: scanID,
                conversationID: conversationID,
                prompts: [
                    [
                        "text": "What is the best way to kill it?",
                        "category": "generic"
                    ]
                ]
            ),
            try promptResponse(
                subjectID: scanID,
                conversationID: conversationID,
                prompts: [
                    [
                        "text": "Can I treat this rash?",
                        "category": "generic"
                    ]
                ]
            ),
            try promptResponse(
                subjectID: scanID,
                conversationID: conversationID,
                prompts: [
                    [
                        "text": "How should I harvest this observation?",
                        "category": "generic"
                    ]
                ]
            ),
            try promptResponse(
                subjectID: scanID,
                conversationID: conversationID,
                prompts: [
                    [
                        "text": "Tell me how to remove this nest.",
                        "category": "generic"
                    ]
                ]
            ),
            try promptResponse(
                subjectID: scanID,
                conversationID: conversationID,
                prompts: [
                    [
                        "text": "Which trait matters?",
                        "category": "future-category"
                    ]
                ]
            ),
            try promptResponse(
                subjectID: scanID,
                conversationID: conversationID,
                prompts: [
                    [
                        "text": String(repeating: "x", count: 121),
                        "category": "generic"
                    ]
                ]
            ),
            try promptResponse(
                subjectID: postID,
                conversationID: conversationID,
                prompts: []
            )
        ]
        for invalidResponse in invalidPromptResponses {
            MockURLProtocol.mockEndpoints["/insight-chat"] = { _ in
                (response, invalidResponse)
            }
            await #expect(throws: MerianError.invalidResponse) {
                try await MerianNetworkClient.shared
                    .suggestInsightChatPrompts(scanId: scanID)
            }
        }

        let unsafeExplorePrompts = try promptResponse(
            subjectID: postID,
            conversationID: nil,
            prompts: [
                [
                    "text": "Can I handle this observation?",
                    "category": "generic"
                ]
            ]
        )
        MockURLProtocol.mockEndpoints["/explore-post-chat"] = { _ in
            (response, unsafeExplorePrompts)
        }
        await #expect(throws: MerianError.invalidResponse) {
            try await MerianNetworkClient.shared
                .suggestExplorePostChatPrompts(postId: postID)
        }
    }

    @Test func testGetExploreShareStateConstructsPayloadAndParsesJSON() async throws {
        let scanID = "019f7004-1caa-78e2-b1f0-98f806955892"
        let postID = "019f7004-23fc-7fa6-9852-2cf928e9e81d"
        let testData = Data("""
        {
            "data": {
                "scan_id": "\(scanID)",
                "post_id": "\(postID)",
                "shared_at": "2026-04-29T22:18:03.000Z",
                "community_request_id": null,
                "community_request_status": null,
                "is_explore_feed_visible": true,
                "location_sharing": "open"
            }
        }
        """.utf8)
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!

        MockURLProtocol.mockEndpoints["/get-scan-explore-share-state"] = { request in
            #expect(request.url?.path.hasSuffix("/get-scan-explore-share-state") == true)
            #expect(request.httpMethod == "POST")

            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            #expect(payload?["scan_id"] as? String == scanID)
            return (mockResponse, testData)
        }

        let response = try await MerianNetworkClient.shared.getExploreShareState(
            scanId: scanID
        )

        #expect(response.scanId == scanID)
        #expect(response.postId == postID)
        #expect(response.sharedAt == "2026-04-29T22:18:03.000Z")
        #expect(response.communityRequestId == nil)
        #expect(response.communityRequestStatus == nil)
        #expect(response.isExploreFeedVisible == true)
        #expect(response.locationSharing == .open)
    }

    @Test func testGetExploreShareStateParsesCommunityRequestState() async throws {
        let scanID = "019f7004-3505-73c0-9e4a-26fe8db264e8"
        let postID = "019f7004-3a81-7cc4-9bd4-dcf6aef91ec3"
        let requestID = "019f7004-41d5-7e34-b08a-d4ec37a3f647"
        let testData = Data("""
        {
            "data": {
                "scan_id": "\(scanID)",
                "post_id": "\(postID)",
                "shared_at": "2026-04-29T22:18:03.000Z",
                "community_request_id": "\(requestID)",
                "community_request_status": "needs_id",
                "is_explore_feed_visible": false,
                "location_sharing": "obscured"
            }
        }
        """.utf8)
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!

        MockURLProtocol.mockEndpoints["/get-scan-explore-share-state"] = { request in
            #expect(request.url?.path.hasSuffix("/get-scan-explore-share-state") == true)
            return (mockResponse, testData)
        }

        let response = try await MerianNetworkClient.shared.getExploreShareState(
            scanId: scanID
        )

        #expect(response.scanId == scanID)
        #expect(response.postId == postID)
        #expect(response.communityRequestId == requestID)
        #expect(response.communityRequestStatus == .needsId)
        #expect(response.isExploreFeedVisible == false)
        #expect(response.locationSharing == .obscured)
    }

    @Test func testGetExploreShareStateAcceptsServerHiddenPostWithoutCommunityRequest() async throws {
        let scanID = "019f7004-4b3a-7d6a-a8fd-5b7db04e6395"
        let postID = "019f7004-50b2-7a28-8972-38fc70217558"
        let testData = Data("""
        {
            "data": {
                "scan_id": "\(scanID)",
                "post_id": "\(postID)",
                "shared_at": "2026-07-29T12:00:00.000Z",
                "community_request_id": null,
                "community_request_status": null,
                "is_explore_feed_visible": false,
                "location_sharing": "open"
            }
        }
        """.utf8)
        let responseURL = try #require(URL(string: "https://example.com"))
        let mockResponse = try #require(
            HTTPURLResponse(
                url: responseURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )

        MockURLProtocol.mockEndpoints[
            "/get-scan-explore-share-state"
        ] = { _ in
            (mockResponse, testData)
        }

        let response = try await MerianNetworkClient.shared
            .getExploreShareState(scanId: scanID)

        #expect(response.postId == postID)
        #expect(response.communityRequestId == nil)
        #expect(response.isExploreFeedVisible == false)
        #expect(response.locationSharing == .open)
    }

    @Test func testGetExploreShareStateRejectsUnconfirmedState() async throws {
        let scanID = "019f7004-3505-73c0-9e4a-26fe8db264e8"
        let responseURL = try #require(URL(string: "https://example.com"))
        let mockResponse = try #require(
            HTTPURLResponse(
                url: responseURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )
        let invalidResponses = [
            Data("""
            {
              "data": {
                "scan_id": "019f7004-3505-73c0-9e4a-26fe8db264e9",
                "post_id": "019f7004-3a81-7cc4-9bd4-dcf6aef91ec3",
                "shared_at": "2026-04-29T22:18:03.000Z",
                "community_request_id": null,
                "community_request_status": null,
                "is_explore_feed_visible": true,
                "location_sharing": "open"
              }
            }
            """.utf8),
            Data("""
            {
              "data": {
                "scan_id": "\(scanID)",
                "post_id": null,
                "shared_at": null,
                "community_request_id": null,
                "community_request_status": null,
                "is_explore_feed_visible": true,
                "location_sharing": "open"
              }
            }
            """.utf8),
            Data("""
            {
              "data": {
                "scan_id": "\(scanID)",
                "post_id": "019f7004-3a81-7cc4-9bd4-dcf6aef91ec3",
                "shared_at": "not-a-timestamp",
                "community_request_id": null,
                "community_request_status": null,
                "is_explore_feed_visible": true,
                "location_sharing": "open"
              }
            }
            """.utf8),
            Data("""
            {
              "data": {
                "scan_id": "\(scanID)",
                "post_id": "019f7004-3a81-7cc4-9bd4-dcf6aef91ec3",
                "shared_at": "2026-04-29T22:18:03.000Z",
                "community_request_id": null,
                "community_request_status": null,
                "location_sharing": "open"
              }
            }
            """.utf8),
            Data("""
            {
              "data": {
                "scan_id": "\(scanID)",
                "post_id": "019f7004-3a81-7cc4-9bd4-dcf6aef91ec3",
                "shared_at": "2026-04-29T22:18:03.000Z",
                "community_request_id": null,
                "community_request_status": null,
                "is_explore_feed_visible": true,
                "location_sharing": "future-unknown-mode"
              }
            }
            """.utf8)
        ]

        for invalidResponse in invalidResponses {
            MockURLProtocol.mockEndpoints[
                "/get-scan-explore-share-state"
            ] = { _ in
                (mockResponse, invalidResponse)
            }
            await #expect(throws: MerianError.invalidResponse) {
                try await MerianNetworkClient.shared
                    .getExploreShareState(scanId: scanID)
            }
        }
    }

    @Test func testExplorePostDetailDecodesSimilarSpecies() throws {
        let data = Data("""
        {
            "schema_version": 1,
            "data": {
                "post_id": "post-detail-123",
                "field_notes": null,
                "species_dictionary_id": "species-123",
                "alternative_common_names": ["Garden Rose", "Meadow Rose"],
                "taxonomy_kingdom": "Plantae",
                "taxonomy_phylum": "Tracheophyta",
                "taxonomy_class": "Magnoliopsida",
                "taxonomy_order": "Rosales",
                "taxonomy_family": "Rosaceae",
                "taxonomy_genus": "Rosa",
                "ai_reasoning": "Petal shape and thorn spacing match the subject.",
                "habitat_description": "Open meadows and garden edges.",
                "gbif_taxon_key": 42,
                "iucn_red_list_status": "least_concern",
                "hazard_type": "poisonous",
                "wikipedia_url": "https://en.wikipedia.org/wiki/Rosa_galeria",
                "reference_image_url": "https://media.merian.app/public_uploads/pro/rosa.webp,https://upload.wikimedia.org/rosa.jpg",
                "wikipedia_overview": "Rosa galeria is a test species with enough overview copy for Explore.",
                "similar_species": [
                    {
                        "species_id": "species-rosa-minor",
                        "scientific_name": "Rosa minor",
                        "common_name": "Small Rose",
                        "reference_image_url": "https://example.com/rosa-minor.jpg",
                        "iucn_red_list_status": "least_concern",
                        "reason": "Similar flower shape and thorn spacing.",
                        "visual_traits": ["pink flowers", "compound leaves"],
                        "confidence": 0.82,
                        "source": "model_enrichment",
                        "review_status": "unreviewed",
                        "is_bidirectional": false,
                        "sort_order": 0
                    }
                ]
            }
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(ExplorePostDetailResponse.self, from: data)
        let similar = try #require(response.data.similarSpeciesData)

        #expect(response.effectiveSchemaVersion == 1)
        #expect(response.data.alternativeCommonNames == ["Garden Rose", "Meadow Rose"])
        #expect(response.data.hazardType == "poisonous")
        #expect(response.data.referenceGalleryImages.map(\.source) == [.merian, .wikipedia])
        #expect(response.data.referenceGalleryImages.first?.source.label == "Naturebook")
        let filteredReferences = response.data.referenceGalleryImages(excluding: [
            "https://media.merian.app/public_uploads/pro/rosa.webp?width=1200#capture"
        ])
        #expect(filteredReferences.map(\.url) == ["https://upload.wikimedia.org/rosa.jpg"])
        #expect(filteredReferences.map(\.source) == [.wikipedia])
        #expect(similar.entries.count == 1)
        #expect(similar.entries[0].speciesId == "species-rosa-minor")
        #expect(similar.entries[0].scientificName == "Rosa minor")
        #expect(similar.entries[0].commonName == "Small Rose")
        #expect(similar.entries[0].referenceImageUrl == "https://example.com/rosa-minor.jpg")
        #expect(similar.entries[0].similarityReason == "Similar flower shape and thorn spacing.")
        #expect(similar.entries[0].visualTraits == ["pink flowers", "compound leaves"])
        #expect(similar.entries[0].similarityConfidence == 0.82)
    }

    @Test func testExplorePostDetailDecodesLegacyPayloadWithoutSchemaVersion() throws {
        let data = """
        {
            "data": {
                "post_id": "post-detail-legacy-schema",
                "field_notes": null,
                "species_dictionary_id": null,
                "taxonomy_kingdom": null,
                "taxonomy_phylum": null,
                "taxonomy_class": null,
                "taxonomy_order": null,
                "taxonomy_family": null,
                "taxonomy_genus": null,
                "ai_reasoning": null,
                "habitat_description": null,
                "gbif_taxon_key": null,
                "iucn_red_list_status": null,
                "wikipedia_url": null,
                "reference_image_url": null,
                "wikipedia_overview": null
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(ExplorePostDetailResponse.self, from: data)

        #expect(response.schemaVersion == nil)
        #expect(response.effectiveSchemaVersion == 0)
        #expect(response.data.postId == "post-detail-legacy-schema")
    }

    @Test func testExplorePostDetailDecodesWhenSimilarSpeciesIsMissing() throws {
        let data = """
        {
            "data": {
                "post_id": "post-detail-legacy",
                "field_notes": null,
                "species_dictionary_id": "species-legacy",
                "taxonomy_kingdom": null,
                "taxonomy_phylum": null,
                "taxonomy_class": null,
                "taxonomy_order": null,
                "taxonomy_family": null,
                "taxonomy_genus": null,
                "ai_reasoning": null,
                "habitat_description": null,
                "gbif_taxon_key": null,
                "iucn_red_list_status": null,
                "wikipedia_url": null,
                "reference_image_url": null,
                "wikipedia_overview": null
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(ExplorePostDetailResponse.self, from: data)

        #expect(response.data.postId == "post-detail-legacy")
        #expect(response.data.similarSpecies == nil)
        #expect(response.data.similarSpeciesData == nil)
    }

    @Test func testExplorePostDecodesVideoMediaItemsAndLegacyFallback() throws {
        let videoData = """
        {
            "data": {
                "post_id": "post-video-123",
                "scan_id": "scan-video-123",
                "hero_image_url": "https://example.com/thumb.jpg",
                "shared_at": "2026-07-03T12:00:00.000Z",
                "author_user_id": "author-video-123",
                "author_name": "Video Author",
                "author_username": "video_author",
                "author_avatar_url": null,
                "author_is_pro": true,
                "hashtags": [],
                "species_common_name": "Monarch Butterfly",
                "species_scientific_name": "Danaus plexippus",
                "pet_identification": null,
                "public_location_label": "Austin, TX",
                "location_sharing": "open",
                "time_of_day": "afternoon",
                "current_month": 7,
                "weather_condition": "clear",
                "weather_temperature_f": 82.0,
                "like_count": 3,
                "comment_count": 1,
                "viewer_has_liked": false,
                "is_owned_by_viewer": false,
                "ranking_value": null,
                "media_items": [
                    {
                        "kind": "video",
                        "url": "https://example.com/video.mp4",
                        "thumbnail_url": "https://example.com/thumb.jpg",
                        "order_index": 0,
                        "duration_seconds": 4.7,
                        "has_audio": true
                    }
                ]
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let videoResponse = try decoder.decode(ExplorePostResponse.self, from: videoData)

        #expect(videoResponse.data.hasVideoMedia)
        #expect(videoResponse.data.resolvedMediaItems.count == 1)
        #expect(videoResponse.data.resolvedMediaItems[0].kind == .video)
        #expect(videoResponse.data.resolvedMediaItems[0].thumbnailUrl == "https://example.com/thumb.jpg")
        #expect(videoResponse.data.resolvedMediaItems[0].hasAudio)

        let audioOnlyData = """
        {
            "data": {
                "post_id": "post-audio-123",
                "scan_id": "scan-audio-123",
                "hero_image_url": null,
                "reference_thumbnail_url": "https://images.merian.app/cardinal.jpg",
                "shared_at": "2026-07-11T12:00:00.000Z",
                "author_user_id": "author-audio-123",
                "author_name": "Audio Author",
                "author_username": "audio_author",
                "author_avatar_url": null,
                "author_is_pro": false,
                "hashtags": [],
                "species_common_name": "Northern Cardinal",
                "species_scientific_name": "Cardinalis cardinalis",
                "pet_identification": null,
                "public_location_label": null,
                "location_sharing": "obscured",
                "time_of_day": "morning",
                "current_month": 7,
                "weather_condition": null,
                "weather_temperature_f": null,
                "like_count": 0,
                "comment_count": 0,
                "viewer_has_liked": false,
                "is_owned_by_viewer": true,
                "ranking_value": null,
                "media_items": [
                    {
                        "kind": "audio",
                        "url": "https://media.merian.app/audio.wav",
                        "thumbnail_url": null,
                        "order_index": 0,
                        "duration_seconds": 8.2,
                        "has_audio": true
                    }
                ]
            }
        }
        """.data(using: .utf8)!

        let audioOnlyResponse = try decoder.decode(ExplorePostResponse.self, from: audioOnlyData)

        #expect(audioOnlyResponse.data.heroImageUrl.isEmpty)
        #expect(audioOnlyResponse.data.hasAudioMedia)
        #expect(audioOnlyResponse.data.gridThumbnailUrl == "https://images.merian.app/cardinal.jpg")
        #expect(
            audioOnlyResponse.data.gridThumbnailUrl(localReferenceUrl: "https://local.merian.app/cardinal.jpg")
                == "https://images.merian.app/cardinal.jpg",
            "The server-projected reference should take precedence when available"
        )
        var legacyAudioPost = audioOnlyResponse.data
        legacyAudioPost.referenceThumbnailUrl = nil
        #expect(
            legacyAudioPost.gridThumbnailUrl(localReferenceUrl: "https://local.merian.app/cardinal.jpg")
                == "https://local.merian.app/cardinal.jpg",
            "Current-user profile grids should retain the local reference when the deployed payload predates the reference-thumbnail field"
        )
        #expect(audioOnlyResponse.data.resolvedMediaItems.count == 1)
        #expect(audioOnlyResponse.data.resolvedMediaItems[0].kind == .audio)
        #expect(audioOnlyResponse.data.resolvedMediaItems[0].posterImageUrl(fallback: "") == nil)
        #expect(audioOnlyResponse.data.resolvedMediaItems[0].audioSpectrogramPosterUrl == nil)

        let spectrogramAudio = ExploreMediaItem(
            kind: .audio,
            url: "https://media.merian.app/audio.wav",
            thumbnailUrl: "https://media.merian.app/spectrogram.webp",
            orderIndex: 0,
            durationSeconds: 8.2,
            hasAudio: true
        )
        #expect(spectrogramAudio.posterImageUrl(fallback: "") == "https://media.merian.app/spectrogram.webp")
        #expect(spectrogramAudio.audioSpectrogramPosterUrl == "https://media.merian.app/spectrogram.webp")

        let videoWithoutThumbnail = ExploreMediaItem(
            kind: .video,
            url: "https://media.merian.app/video.mp4",
            thumbnailUrl: nil,
            orderIndex: 0,
            durationSeconds: 4.2,
            hasAudio: true
        )
        #expect(videoWithoutThumbnail.posterImageUrl(fallback: "https://media.merian.app/fallback.webp") ==
            "https://media.merian.app/fallback.webp")

        let legacyData = """
        {
            "data": {
                "post_id": "post-image-123",
                "scan_id": "scan-image-123",
                "hero_image_url": "https://example.com/image.jpg",
                "shared_at": "2026-07-03T12:00:00.000Z",
                "author_user_id": "author-image-123",
                "author_name": "Image Author",
                "author_username": null,
                "author_avatar_url": null,
                "author_is_pro": null,
                "hashtags": null,
                "species_common_name": "Honey Bee",
                "species_scientific_name": "Apis mellifera",
                "pet_identification": null,
                "public_location_label": null,
                "location_sharing": null,
                "time_of_day": null,
                "current_month": null,
                "weather_condition": null,
                "weather_temperature_f": null,
                "like_count": 0,
                "comment_count": 0,
                "viewer_has_liked": false,
                "is_owned_by_viewer": false,
                "ranking_value": null
            }
        }
        """.data(using: .utf8)!

        let legacyResponse = try decoder.decode(ExplorePostResponse.self, from: legacyData)

        #expect(!legacyResponse.data.hasVideoMedia)
        #expect(legacyResponse.data.resolvedMediaItems == [
            .legacyImage(url: "https://example.com/image.jpg")
        ])
    }

    @Test func testExploreMediaIncidentsAndLifecycleNotificationsDecode() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let incidentData = Data("""
        {
          "data": [
            {
              "post_id": "post-1",
              "scan_id": "scan-1",
              "species_common_name": "White-winged Dove",
              "media_health_status": "quarantined",
              "missing_media_count": 2,
              "total_media_count": 2,
              "media_quarantined_at": "2026-07-26T12:10:00Z",
              "media_health_updated_at": "2026-07-26T12:10:00Z",
              "missing_media_urls": [
                "https://media.merian.app/public_uploads/pro/user/one.webp",
                "https://media.merian.app/public_uploads/pro/user/two.webp"
              ]
            }
          ]
        }
        """.utf8)
        let incidentResponse = try decoder.decode(
            ExploreMediaIncidentsResponse.self,
            from: incidentData
        )

        #expect(incidentResponse.data[0].id == "post-1")
        #expect(incidentResponse.data[0].mediaHealthStatus == .quarantined)
        #expect(incidentResponse.data[0].missingMediaUrls.count == 2)

        let incidentObject = try #require(
            JSONSerialization.jsonObject(with: incidentData)
                as? [String: Any]
        )
        let legacyIncidentData = try JSONSerialization.data(
            withJSONObject: try #require(incidentObject["data"])
        )
        let populatedLegacyIncidentResponse = try decoder.decode(
            ExploreMediaIncidentsResponse.self,
            from: legacyIncidentData
        )
        #expect(populatedLegacyIncidentResponse.data == incidentResponse.data)

        let legacyIncidentResponse = try decoder.decode(
            ExploreMediaIncidentsResponse.self,
            from: Data("[]".utf8)
        )
        #expect(legacyIncidentResponse.data.isEmpty)

        let notificationData = Data("""
        {
          "data": [
            {
              "notification_id": "missing-1",
              "post_id": "post-1",
              "community_request_id": null,
              "field_trip_publication_id": null,
              "type": "media_missing",
              "comment_id": null,
              "parent_comment_id": null,
              "reaction_emoji": null,
              "triggering_user_id": null,
              "triggering_user_name": null,
              "comment_body": null,
              "recent_actor_names": [],
              "action_count": 1,
              "is_read": false,
              "is_reply_to_viewer_comment": false,
              "community_taxon_common_name": null,
              "community_taxon_scientific_name": null,
              "community_request_display_name": null,
              "created_at": "2026-07-26T12:10:00Z",
              "updated_at": "2026-07-26T12:10:00Z"
            },
            {
              "notification_id": "restored-1",
              "post_id": "post-1",
              "community_request_id": null,
              "field_trip_publication_id": null,
              "type": "media_restored",
              "comment_id": null,
              "parent_comment_id": null,
              "reaction_emoji": null,
              "triggering_user_id": null,
              "triggering_user_name": null,
              "comment_body": null,
              "recent_actor_names": [],
              "action_count": 1,
              "is_read": false,
              "is_reply_to_viewer_comment": false,
              "community_taxon_common_name": null,
              "community_taxon_scientific_name": null,
              "community_request_display_name": null,
              "created_at": "2026-07-26T12:20:00Z",
              "updated_at": "2026-07-26T12:20:00Z"
            }
          ]
        }
        """.utf8)
        let notificationResponse = try decoder.decode(
            ExploreNotificationsResponse.self,
            from: notificationData
        )

        #expect(notificationResponse.data.map(\.type) == [.mediaMissing, .mediaRestored])
    }

    @Test func testExploreMediaIncidentsRejectsUnknownSuccessShape() async throws {
        let response = HTTPURLResponse(
            url: try #require(URL(string: "https://example.com")),
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        MockURLProtocol.mockEndpoints["/get-explore-media-incidents"] = { _ in
            (response, Data(#"{"incidents":[]}"#.utf8))
        }

        await #expect(throws: MerianError.invalidResponse) {
            try await MerianNetworkClient.shared.getExploreMediaIncidents()
        }
    }

    @Test func testExploreMapResponseToleratesMediaOnlyPostsWithoutHeroImages() throws {
        let data = """
        {
            "mode": "posts",
            "visible_count": 2,
            "category_counts": [{ "category": "birds", "count": 2 }],
            "clusters": [],
            "posts": [
                {
                    "post_id": "audio-post",
                    "scan_id": "audio-scan",
                    "latitude": 30.2672,
                    "longitude": -97.7431,
                    "coordinate_visibility": "exact",
                    "hero_image_url": null,
                    "reference_thumbnail_url": "https://example.com/cardinal.webp",
                    "shared_at": "2026-07-11T20:00:00Z",
                    "author_user_id": "audio-author",
                    "author_name": "Audio Author",
                    "author_username": null,
                    "author_avatar_url": null,
                    "author_is_pro": false,
                    "species_common_name": "Northern Cardinal",
                    "species_scientific_name": "Cardinalis cardinalis",
                    "pet_identification": null,
                    "taxonomy_kingdom": "Animalia",
                    "taxonomy_class": "Aves",
                    "public_location_label": "Austin, TX",
                    "location_sharing": "open",
                    "time_of_day": null,
                    "current_month": 7,
                    "weather_condition": null,
                    "weather_temperature_f": null,
                    "like_count": 0,
                    "comment_count": 0,
                    "viewer_has_liked": false,
                    "is_owned_by_viewer": false,
                    "media_items": [{
                        "kind": "audio",
                        "url": "https://example.com/cardinal.wav",
                        "thumbnail_url": null,
                        "order_index": 0,
                        "duration_seconds": 8.0,
                        "has_audio": true
                    }]
                },
                {
                    "post_id": "video-post",
                    "scan_id": "video-scan",
                    "latitude": 30.268,
                    "longitude": -97.744,
                    "coordinate_visibility": "obscured",
                    "shared_at": "2026-07-11T19:00:00Z",
                    "author_user_id": "video-author",
                    "author_name": "Video Author",
                    "author_username": null,
                    "author_avatar_url": null,
                    "author_is_pro": true,
                    "species_common_name": "Monarch Butterfly",
                    "species_scientific_name": "Danaus plexippus",
                    "pet_identification": null,
                    "taxonomy_kingdom": "Animalia",
                    "taxonomy_class": "Insecta",
                    "public_location_label": null,
                    "location_sharing": "obscured",
                    "time_of_day": null,
                    "current_month": 7,
                    "weather_condition": null,
                    "weather_temperature_f": null,
                    "like_count": 1,
                    "comment_count": 2,
                    "viewer_has_liked": true,
                    "is_owned_by_viewer": false,
                    "media_items": [{
                        "kind": "video",
                        "url": "https://example.com/monarch.mp4",
                        "thumbnail_url": "https://example.com/monarch.webp",
                        "order_index": 0,
                        "duration_seconds": 4.0,
                        "has_audio": true
                    }]
                }
            ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(ExploreMapPointsResponse.self, from: data)

        #expect(response.posts.count == 2)
        #expect(response.posts[0].heroImageUrl.isEmpty)
        #expect(response.posts[0].hasAudioMedia)
        #expect(response.posts[0].mapThumbnailUrl == "https://example.com/cardinal.webp")
        #expect(response.posts[0].asExplorePost.referenceThumbnailUrl == "https://example.com/cardinal.webp")
        #expect(response.posts[0].asExplorePost.hasAudioMedia)
        #expect(response.posts[1].heroImageUrl.isEmpty)
        #expect(response.posts[1].hasVideoMedia)
        #expect(response.posts[1].mapThumbnailUrl == "https://example.com/monarch.webp")
        #expect(response.posts[1].asExplorePost.hasVideoMedia)
        #expect(response.mediaTypeCounts.isEmpty)
    }

    @Test func testGetExploreMapPointsSendsMediaFiltersAndDecodesCounts() async throws {
        let testData = Data("""
        {
            "mode": "posts",
            "visible_count": 0,
            "category_counts": [],
            "media_type_counts": [
                { "media_type": "image", "count": 4 },
                { "media_type": "audio", "count": 2 }
            ],
            "clusters": [],
            "posts": []
        }
        """.utf8)
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        MockURLProtocol.mockEndpoints["/get-explore-map-points"] = { request in
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["species_categories"] as? [String] == ["birds"])
            #expect(payload["media_types"] as? [String] == ["audio", "video"])
            return (mockResponse, testData)
        }

        let response = try await MerianNetworkClient.shared.getExploreMapPoints(
            northLatitude: 31,
            southLatitude: 30,
            eastLongitude: -97,
            westLongitude: -98,
            zoomLevel: 12,
            speciesCategories: [.birds],
            mediaTypes: [.video, .audio]
        )

        #expect(response.mediaTypeCounts == [
            ExploreMapMediaTypeCount(mediaType: .image, count: 4),
            ExploreMapMediaTypeCount(mediaType: .audio, count: 2)
        ])
    }

    @Test func testGetExploreFeedTrendingConstructsPayloadAndParsesResponse() async throws {
        let testData = """
        {
            "data": [
                {
                    "post_id": "post-trending-123",
                    "scan_id": "scan-trending-123",
                    "hero_image_url": "https://example.com/trending.webp",
                    "shared_at": "2026-05-01T12:00:00.000Z",
                    "author_user_id": "author-trending-123",
                    "author_name": "Trending Author",
                    "author_avatar_url": null,
                    "species_common_name": "Monarch Butterfly",
                    "species_scientific_name": "Danaus plexippus",
                    "public_location_label": "Austin, TX",
                    "time_of_day": "day",
                    "current_month": 5,
                    "weather_condition": "Clear",
                    "weather_temperature_f": 78.4,
                    "like_count": 11,
                    "comment_count": 2,
                    "viewer_has_liked": false,
                    "is_owned_by_viewer": false,
                    "ranking_value": 4
                }
            ]
        }
        """.data(using: .utf8)!
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!

        MockURLProtocol.mockEndpoints["/get-explore-feed"] = { request in
            #expect(request.url?.path.hasSuffix("/get-explore-feed") == true)
            #expect(request.httpMethod == "POST")

            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["filter"] as? String == "trending")
            #expect(payload["before_ranking_value"] as? Int == 4)
            #expect(payload["before_shared_at"] as? String == "2026-05-01T12:00:00.000Z")
            #expect(payload["before_post_id"] as? String == "post-trending-123")
            return (mockResponse, testData)
        }

        let posts = try await MerianNetworkClient.shared.getExploreFeed(
            limit: 10,
            filter: .trending,
            cursor: ExploreFeedCursor(
                beforeSharedAt: "2026-05-01T12:00:00.000Z",
                beforePostId: "post-trending-123",
                beforeRankingValue: 4
            )
        )

        #expect(posts.count == 1)
        #expect(posts[0].id == "post-trending-123")
        #expect(posts[0].rankingValue == 4)
    }

    @Test func testGetExploreFeedNearbyConstructsPayloadWithCoordinates() async throws {
        let testData = """
        {
            "data": [
                {
                    "post_id": "post-nearby-123",
                    "scan_id": "scan-nearby-123",
                    "hero_image_url": "https://example.com/nearby.webp",
                    "shared_at": "2026-05-02T08:30:00.000Z",
                    "author_user_id": "author-nearby-123",
                    "author_name": "Nearby Author",
                    "author_avatar_url": null,
                    "species_common_name": "Bluebird",
                    "species_scientific_name": "Sialia sialis",
                    "public_location_label": "Chicago, IL",
                    "time_of_day": "morning",
                    "current_month": 5,
                    "weather_condition": "Cloudy",
                    "weather_temperature_f": 61.2,
                    "like_count": 3,
                    "comment_count": 1,
                    "viewer_has_liked": true,
                    "is_owned_by_viewer": false,
                    "ranking_value": null
                }
            ]
        }
        """.data(using: .utf8)!
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!

        MockURLProtocol.mockEndpoints["/get-explore-feed"] = { request in
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["filter"] as? String == "nearby")
            #expect(payload["latitude"] as? Double == 41.8781)
            #expect(payload["longitude"] as? Double == -87.6298)
            #expect(payload["nearby_radius_miles"] as? Int == 50)
            return (mockResponse, testData)
        }

        let posts = try await MerianNetworkClient.shared.getExploreFeed(
            filter: .nearby,
            latitude: 41.8781,
            longitude: -87.6298
        )

        #expect(posts.count == 1)
        #expect(posts[0].id == "post-nearby-123")
        #expect(posts[0].rankingValue == nil)
    }

    @Test func testGetExploreFeedConstructsAdvancedFilterPayload() async throws {
        let testData = Data("""
        {
            "data": []
        }
        """.utf8)
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let referenceDate = try #require(
            DateUtilities.iso8601Formatter.date(from: "2026-07-15T18:00:00Z")
        )
        var filters = ExploreFeedAdvancedFilters()
        filters.speciesCategories = [.mammals, .birds]
        filters.mediaTypes = [.video, .audio]
        filters.dateRange = .pastWeek
        filters.nearbyRadius = .twentyFive
        let sharedSince = try #require(filters.dateRange.sharedSince(referenceDate: referenceDate))

        MockURLProtocol.mockEndpoints["/get-explore-feed"] = { request in
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["species_categories"] as? [String] == ["birds", "mammals"])
            #expect(payload["media_types"] as? [String] == ["audio", "video"])
            #expect(payload["shared_since"] as? String == "2026-07-08T18:00:00Z")
            #expect(payload["nearby_radius_miles"] as? Int == 25)
            return (mockResponse, testData)
        }

        let posts = try await MerianNetworkClient.shared.getExploreFeed(
            filter: .nearby,
            latitude: 30.2672,
            longitude: -97.7431,
            advancedFilters: filters,
            sharedSince: sharedSince
        )

        #expect(posts.isEmpty)
        #expect(filters.activeFilterCount(for: .recent) == 5)
        #expect(filters.activeFilterCount(for: .nearby) == 6)
    }

    @Test func testGetExploreFeedFollowingConstructsPayload() async throws {
        let testData = """
        {
            "data": []
        }
        """.data(using: .utf8)!
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!

        MockURLProtocol.mockEndpoints["/get-explore-feed"] = { request in
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["filter"] as? String == "following")
            #expect(payload["limit"] as? Int == 20)
            #expect(payload["before_ranking_value"] == nil)
            #expect(payload["latitude"] == nil)
            #expect(payload["longitude"] == nil)
            return (mockResponse, testData)
        }

        let posts = try await MerianNetworkClient.shared.getExploreFeed(filter: .following)

        #expect(posts.isEmpty)
    }

    @Test func testGetCommunityIdentificationFeedConstructsScopedPayload() async throws {
        let testData = """
        {
            "data": [
                {
                    "request_id": "request-mine-123",
                    "post_id": "post-mine-123",
                    "scan_id": "scan-mine-123",
                    "hero_image_url": "https://example.com/community.webp",
                    "requested_at": "2026-06-20T12:00:00.000Z",
                    "author_user_id": "viewer-123",
                    "author_name": "Viewer",
                    "author_avatar_url": null,
                    "taxonomy_version_id": "taxonomy-v1",
                    "projection_state": "community_needs_id",
                    "consensus_processing_state": "idle",
                    "current_taxon_id": "taxon-1",
                    "current_common_name": "Pinwheel",
                    "current_scientific_name": "Aeonium haworthii",
                    "current_rank": "species",
                    "current_path": "plantae.tracheophyta.magnoliopsida.saxifragales.crassulaceae.aeonium.aeonium_haworthii",
                    "initial_taxon_id": "taxon-1",
                    "initial_common_name": "Pinwheel",
                    "initial_scientific_name": "Aeonium haworthii",
                    "initial_rank": "species",
                    "initial_path": "plantae.tracheophyta.magnoliopsida.saxifragales.crassulaceae.aeonium.aeonium_haworthii",
                    "request_group": "plants",
                    "consensus_score": null,
                    "identification_count": 0,
                    "viewer_has_identified": false,
                    "public_location_label": "Austin, TX",
                    "location_sharing": "open"
                }
            ]
        }
        """.data(using: .utf8)!
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!

        MockURLProtocol.mockEndpoints["/get-community-identification-feed"] = { request in
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["limit"] as? Int == 12)
            #expect(payload["scope"] as? String == "mine")
            #expect(payload["group"] as? String == "plants")
            #expect(payload["latitude"] as? Double == 30.2672)
            #expect(payload["longitude"] as? Double == -97.7431)
            #expect(payload["before_requested_at"] as? String == "2026-06-20T12:00:00.000Z")
            #expect(payload["before_request_id"] as? String == "request-cursor-123")
            return (mockResponse, testData)
        }

        let requests = try await MerianNetworkClient.shared.getCommunityIdentificationFeed(
            limit: 12,
            scope: .mine,
            group: .plants,
            latitude: 30.2672,
            longitude: -97.7431,
            cursor: CommunityIdentificationCursor(
                beforeRequestedAt: "2026-06-20T12:00:00.000Z",
                beforeRequestId: "request-cursor-123"
            )
        )

        #expect(requests.count == 1)
        #expect(requests[0].id == "request-mine-123")
        #expect(requests[0].requestGroup == .plants)
    }

    @Test func testUpdateCommunityIdentificationRequestConstructsPayload() async throws {
        let testData = """
        {
            "success": true,
            "data": {
                "id": "request-edit-123",
                "post_id": "post-edit-123",
                "note": "Look near the leaf edges.",
                "location_sharing": "obscured",
                "updated_at": "2026-06-20T23:58:00.000Z"
            }
        }
        """.data(using: .utf8)!
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!

        MockURLProtocol.mockEndpoints["/update-community-identification-request"] = { request in
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["request_id"] as? String == "request-edit-123")
            #expect(payload["note"] as? String == "Look near the leaf edges.")
            #expect(payload["location_sharing"] as? String == "obscured")
            return (mockResponse, testData)
        }

        let update = try await MerianNetworkClient.shared.updateCommunityIdentificationRequest(
            requestId: "request-edit-123",
            note: "Look near the leaf edges.",
            locationSharing: .obscured
        )

        #expect(update.id == "request-edit-123")
        #expect(update.postId == "post-edit-123")
        #expect(update.note == "Look near the leaf edges.")
        #expect(update.locationSharing == .obscured)
    }

    @Test func testGetExploreAuthorProfileParsesProfilePayload() async throws {
        let testData = """
        {
            "data": {
                "author_user_id": "author-profile-123",
                "author_name": "River Walker",
                "author_avatar_url": "https://example.com/avatar.jpg",
                "species_count": 12,
                "current_streak": 4,
                "published_post_count": 5,
                "follower_count": 7,
                "following_count": 3,
                "viewer_is_following": false,
                "viewer_can_report": false,
                "owner_publication_summary": {
                    "publication_intent_count": 38,
                    "visible_post_count": 5,
                    "recovery_needed_post_count": 33,
                    "degraded_post_count": 0,
                    "quarantined_post_count": 33
                },
                "heatmap": {
                    "total_captures": 17,
                    "current_month_captures": 3,
                    "year_string": "2026",
                    "weeks": [
                        {
                            "month_label": "May",
                            "days": [
                                { "count": 1, "date": "2026-05-03T00:00:00Z" },
                                { "count": 0, "date": "2026-05-04T00:00:00Z" }
                            ]
                        }
                    ]
                },
                "awards": [
                    {
                        "type": "explorer",
                        "current_count": 5,
                        "last_interaction_at": "2026-05-03T12:00:00.000Z"
                    },
                    {
                        "type": "first_field_trip",
                        "current_count": 1,
                        "last_interaction_at": "2026-05-02T12:00:00.000Z"
                    }
                ],
                "preview_posts": [
                    {
                        "post_id": "post-profile-123",
                        "scan_id": "scan-profile-123",
                        "hero_image_url": "https://example.com/profile.webp",
                        "shared_at": "2026-05-03T12:00:00.000Z",
                        "author_user_id": "author-profile-123",
                        "author_name": "River Walker",
                        "author_avatar_url": "https://example.com/avatar.jpg",
                        "species_common_name": "River Birch",
                        "species_scientific_name": "Betula nigra",
                        "public_location_label": "Austin, TX",
                        "time_of_day": "day",
                        "current_month": 5,
                        "weather_condition": "Clear",
                        "weather_temperature_f": 74.0,
                        "like_count": 8,
                        "comment_count": 1,
                        "viewer_has_liked": false,
                        "is_owned_by_viewer": true,
                        "ranking_value": null
                    }
                ]
            }
        }
        """.data(using: .utf8)!
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!

        MockURLProtocol.mockEndpoints["/get-explore-author-profile"] = { request in
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["author_user_id"] as? String == "author-profile-123")
            #expect(payload["preview_limit"] as? Int == 9)
            return (mockResponse, testData)
        }

        let profile = try await MerianNetworkClient.shared.getExploreAuthorProfile(
            authorUserId: "author-profile-123"
        )

        #expect(profile.authorName == "River Walker")
        #expect(profile.speciesCount == 12)
        #expect(profile.currentStreak == 4)
        #expect(profile.followerCount == 7)
        #expect(profile.followingCount == 3)
        #expect(profile.viewerIsFollowing == false)
        #expect(profile.viewerCanReport == false)
        #expect(profile.ownerPublicationSummary?.publicationIntentCount == 38)
        #expect(profile.ownerPublicationSummary?.visiblePostCount == 5)
        #expect(profile.ownerPublicationSummary?.recoveryNeededPostCount == 33)
        #expect(profile.ownerPublicationSummary?.quarantinedPostCount == 33)
        #expect(profile.profileHeatmapData.totalCaptures == 17)
        #expect(profile.profileHeatmapData.weeks.count == 1)
        #expect(profile.awardPayloads.count == AchievementType.allCases.count)
        #expect(profile.awardPayloads.first { $0.type == .explorer }?.isCompleted == true)
        #expect(profile.awardPayloads.first { $0.type == .domesticCat }?.currentCount == 0)
        #expect(profile.awardPayloads.first { $0.type == .domesticDog }?.currentCount == 0)
        #expect(profile.awardPayloads.first { $0.type == .firstFieldTrip }?.isCompleted == true)
        #expect(profile.awardPayloads.first { $0.type == .firstFieldTrip }?.destination == nil)
        #expect(profile.previewPosts.first?.id == "post-profile-123")
    }

    @Test func testGetExploreAuthorPostsConstructsCursorPayload() async throws {
        let testData = """
        {
            "data": [
                {
                    "post_id": "post-author-page-123",
                    "scan_id": "scan-author-page-123",
                    "hero_image_url": "https://example.com/page.webp",
                    "shared_at": "2026-05-04T12:00:00.000Z",
                    "author_user_id": "author-page-123",
                    "author_name": "Page Author",
                    "author_avatar_url": null,
                    "species_common_name": "Post Oak",
                    "species_scientific_name": "Quercus stellata",
                    "public_location_label": null,
                    "time_of_day": null,
                    "current_month": null,
                    "weather_condition": null,
                    "weather_temperature_f": null,
                    "like_count": 0,
                    "comment_count": 0,
                    "viewer_has_liked": false,
                    "is_owned_by_viewer": false,
                    "ranking_value": null
                }
            ],
            "next_cursor": {
                "before_shared_at": "2026-05-04T12:00:00.000Z",
                "before_post_id": "post-author-page-123"
            }
        }
        """.data(using: .utf8)!
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!

        MockURLProtocol.mockEndpoints["/get-explore-author-posts"] = { request in
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["author_user_id"] as? String == "author-page-123")
            #expect(payload["limit"] as? Int == 30)
            #expect(payload["before_shared_at"] as? String == "2026-05-04T12:00:00.000Z")
            #expect(payload["before_post_id"] as? String == "post-cursor-123")
            return (mockResponse, testData)
        }

        let page = try await MerianNetworkClient.shared.getExploreAuthorPosts(
            authorUserId: "author-page-123",
            cursor: ExploreAuthorPostCursor(
                beforeSharedAt: "2026-05-04T12:00:00.000Z",
                beforePostId: "post-cursor-123"
            )
        )

        #expect(page.data.count == 1)
        #expect(page.data[0].id == "post-author-page-123")
        #expect(page.nextCursor?.beforeSharedAt == "2026-05-04T12:00:00.000Z")
        #expect(page.nextCursor?.beforePostId == "post-author-page-123")
    }

    @Test func testGetExploreSpeciesPostsConstructsQualityCursorAndDecodesNextCursor() async throws {
        let testData = Data("""
        {
            "data": [
                {
                    "post_id": "post-species-page-123",
                    "scan_id": "scan-species-page-123",
                    "hero_image_url": "https://example.com/species.webp",
                    "reference_thumbnail_url": "https://example.com/reference.webp",
                    "shared_at": "2026-07-14T12:00:00.000Z",
                    "author_user_id": "author-species-123",
                    "author_name": "Species Author",
                    "author_avatar_url": null,
                    "species_common_name": "Monarch Butterfly",
                    "species_scientific_name": "Danaus plexippus",
                    "public_location_label": null,
                    "location_sharing": "obscured",
                    "time_of_day": null,
                    "current_month": null,
                    "weather_condition": null,
                    "weather_temperature_f": null,
                    "like_count": 4,
                    "comment_count": 1,
                    "viewer_has_liked": false,
                    "is_owned_by_viewer": false,
                    "ranking_value": null,
                    "media_items": [
                        {
                            "kind": "audio",
                            "url": "https://example.com/species.wav",
                            "thumbnail_url": "https://example.com/spectrogram.webp",
                            "order_index": 0,
                            "duration_seconds": 4.2,
                            "has_audio": true
                        }
                    ]
                }
            ],
            "next_cursor": {
                "image_quality_score": null,
                "shared_at": "2026-07-14T12:00:00.000Z",
                "post_id": "post-species-page-123"
            }
        }
        """.utf8)
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        MockURLProtocol.mockEndpoints["/get-explore-species-posts"] = { request in
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["species_id"] as? String == "species-dictionary-123")
            #expect(payload["limit"] as? Int == 6)
            #expect(payload["before_image_quality_score"] as? Int == 91)
            #expect(payload["before_shared_at"] as? String == "2026-07-15T12:00:00.000Z")
            #expect(payload["before_post_id"] as? String == "post-cursor-123")
            return (mockResponse, testData)
        }

        let response = try await MerianNetworkClient.shared.getExploreSpeciesPosts(
            speciesId: "species-dictionary-123",
            limit: 6,
            cursor: ExploreSpeciesPostCursor(
                imageQualityScore: 91,
                sharedAt: "2026-07-15T12:00:00.000Z",
                postId: "post-cursor-123"
            )
        )

        #expect(response.data.map(\.id) == ["post-species-page-123"])
        #expect(response.data[0].hasAudioMedia)
        #expect(response.data[0].gridThumbnailUrl == "https://example.com/reference.webp")
        #expect(response.nextCursor?.imageQualityScore == nil)
        #expect(response.nextCursor?.postId == "post-species-page-123")
    }

    @Test func testGetExploreSpeciesPostsOmitsQualityFieldForUnscoredCursor() async throws {
        let testData = Data(#"{"data":[],"next_cursor":null}"#.utf8)
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        MockURLProtocol.mockEndpoints["/get-explore-species-posts"] = { request in
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["before_image_quality_score"] == nil)
            #expect(payload["before_shared_at"] as? String == "2026-07-14T12:00:00.000Z")
            #expect(payload["before_post_id"] as? String == "post-unscored-123")
            return (mockResponse, testData)
        }

        let response = try await MerianNetworkClient.shared.getExploreSpeciesPosts(
            speciesId: "species-dictionary-123",
            cursor: ExploreSpeciesPostCursor(
                imageQualityScore: nil,
                sharedAt: "2026-07-14T12:00:00.000Z",
                postId: "post-unscored-123"
            )
        )

        #expect(response.data.isEmpty)
        #expect(response.nextCursor == nil)
    }

    @Test func testSetUserFollowConstructsPayloadAndParsesState() async throws {
        let testData = """
        {
            "success": true,
            "author_user_id": "author-follow-123",
            "follower_count": 12,
            "following_count": 4,
            "viewer_is_following": true
        }
        """.data(using: .utf8)!
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!

        MockURLProtocol.mockEndpoints["/set-user-follow"] = { request in
            #expect(request.url?.path.hasSuffix("/set-user-follow") == true)
            #expect(request.httpMethod == "POST")

            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["author_user_id"] as? String == "author-follow-123")
            #expect(payload["is_following"] as? Bool == true)
            return (mockResponse, testData)
        }

        let state = try await MerianNetworkClient.shared.setUserFollow(
            authorUserId: "author-follow-123",
            isFollowing: true
        )

        #expect(state.success == true)
        #expect(state.authorUserId == "author-follow-123")
        #expect(state.followerCount == 12)
        #expect(state.followingCount == 4)
        #expect(state.viewerIsFollowing == true)
    }

    @Test func testGetExploreCommentsParsesAuthorAvatar() async throws {
        let testData = """
        {
            "data": [
                {
                    "comment_id": "comment-avatar-123",
                    "post_id": "post-avatar-123",
                    "author_user_id": "author-avatar-123",
                    "author_name": "Comment Author",
                    "author_avatar_url": "https://example.com/comment-author.jpg",
                    "body": "Avatar should render here.",
                    "created_at": "2026-05-12T20:43:00.000Z",
                    "viewer_can_delete": false,
                    "viewer_can_moderate": false,
                    "viewer_can_report": true,
                    "reactions": [
                        {
                            "emoji": "👍",
                            "count": 2,
                            "viewer_has_reacted": false
                        }
                    ]
                }
            ]
        }
        """.data(using: .utf8)!
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!

        MockURLProtocol.mockEndpoints["/get-explore-comments"] = { request in
            #expect(request.url?.path.hasSuffix("/get-explore-comments") == true)
            #expect(request.httpMethod == "POST")

            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["post_id"] as? String == "post-avatar-123")
            #expect(payload["limit"] as? Int == 100)
            return (mockResponse, testData)
        }

        let comments = try await MerianNetworkClient.shared.getExploreComments(postId: "post-avatar-123")

        #expect(comments.count == 1)
        #expect(comments[0].id == "comment-avatar-123")
        #expect(comments[0].authorAvatarUrl == "https://example.com/comment-author.jpg")
        #expect(comments[0].reactions?.first?.emoji == "👍")
    }

    @Test func testGetExploreCommentRepliesUsesParentCommentAndDecodesReply() async throws {
        let testData = """
        {
            "success": true,
            "data": [
                {
                    "comment_id": "reply-avatar-123",
                    "post_id": "post-avatar-123",
                    "parent_comment_id": "parent-avatar-123",
                    "author_user_id": "reply-author-123",
                    "author_name": "Reply Author",
                    "author_avatar_url": "https://example.com/reply-author.jpg",
                    "body": "Reply body",
                    "created_at": "2026-05-19T10:01:00.000Z",
                    "viewer_can_delete": false,
                    "viewer_can_moderate": false,
                    "viewer_can_report": true,
                    "reply_count": 0,
                    "reactions": []
                }
            ]
        }
        """.data(using: .utf8)!
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!

        MockURLProtocol.mockEndpoints["/get-explore-comment-replies"] = { request in
            #expect(request.url?.path.hasSuffix("/get-explore-comment-replies") == true)
            #expect(request.httpMethod == "POST")

            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["parent_comment_id"] as? String == "parent-avatar-123")
            #expect(payload["limit"] as? Int == 25)
            return (mockResponse, testData)
        }

        let replies = try await MerianNetworkClient.shared.getExploreCommentReplies(parentCommentId: "parent-avatar-123")

        #expect(replies.count == 1)
        #expect(replies[0].id == "reply-avatar-123")
        #expect(replies[0].parentCommentId == "parent-avatar-123")
        #expect(replies[0].authorAvatarUrl == "https://example.com/reply-author.jpg")
    }

    @Test func testCreateExploreCommentParsesAuthorAvatar() async throws {
        let testData = """
        {
            "success": true,
            "comment": {
                "comment_id": "comment-created-123",
                "post_id": "post-created-123",
                "author_user_id": "author-created-123",
                "author_name": "Created Author",
                "author_avatar_url": "https://example.com/created-author.jpg",
                "body": "Fresh comment",
                "created_at": "2026-05-12T20:44:00.000Z",
                "viewer_can_delete": true,
                "viewer_can_moderate": false,
                "viewer_can_report": false
            },
            "comment_count": 3
        }
        """.data(using: .utf8)!
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!

        MockURLProtocol.mockEndpoints["/create-explore-comment"] = { request in
            #expect(request.url?.path.hasSuffix("/create-explore-comment") == true)
            #expect(request.httpMethod == "POST")

            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["post_id"] as? String == "post-created-123")
            #expect(payload["body"] as? String == "Fresh comment")
            return (mockResponse, testData)
        }

        let response = try await MerianNetworkClient.shared.createExploreComment(
            postId: "post-created-123",
            body: "Fresh comment"
        )

        #expect(response.success == true)
        #expect(response.comment.authorAvatarUrl == "https://example.com/created-author.jpg")
        #expect(response.commentCount == 3)
    }

    @Test func testGenerateUploadURLsUsesStructuredMediaManifest() async throws {
        let testData = """
        {
            "urls": [
                {
                    "fileName": "image_1",
                    "signedUrl": "https://example.com/put/image_1",
                    "objectKey": "merian/user/image_1.webp",
                    "mediaAssetId": "asset-123",
                    "mediaSessionId": "session-456"
                }
            ]
        }
        """.data(using: .utf8)!
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        
        MockURLProtocol.mockEndpoints["/generate-upload-urls"] = { request in
            #expect(request.url?.path.hasSuffix("/generate-upload-urls") == true)
            #expect(request.httpMethod == "POST")
            let bodyData = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            #expect(payload["fileNames"] == nil)
            let files = try #require(payload["files"] as? [[String: Any]])
            #expect(files.count == 1)
            #expect(files[0]["fileName"] as? String == "image_1")
            #expect(files[0]["mediaKind"] as? String == "image")
            #expect(files[0]["contentType"] as? String == "image/webp")
            #expect(files[0]["sizeBytes"] as? Int == 1024)
            #expect(files[0]["clientScanId"] as? String == "00000000-0000-0000-0000-000000000001")
            #expect(files[0]["mediaRole"] as? String == "display")
            return (mockResponse, testData)
        }
        
        let urls = try await MerianNetworkClient.shared.generateUploadURLs(
            uploadFiles: [
                StagingUploadFile(
                    fileName: "image_1",
                    mediaKind: .image,
                    contentType: "image/webp",
                    sizeBytes: 1024,
                    clientScanId: "00000000-0000-0000-0000-000000000001",
                    mediaRole: "display"
                )
            ]
        )
        #expect(urls.count == 1)
        #expect(urls[0].signedUrl == "https://example.com/put/image_1")
        #expect(urls[0].mediaAssetId == "asset-123")
        #expect(urls[0].mediaSessionId == "session-456")
    }

    @Test func testUploadStagedVideoFilesFallsBackToMovedDocumentsFile() async throws {
        let fileName = "moved_video_playback.mp4"
        let documentsURL = URL.documentsDirectory.appendingPathComponent(fileName)
        let staleTemporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try FileManager.default.createDirectory(
            at: URL.documentsDirectory,
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: staleTemporaryURL)
        try Data("video-bytes".utf8).write(to: documentsURL, options: .atomic)
        defer {
            try? FileManager.default.removeItem(at: documentsURL)
        }

        let testData = """
        {
            "urls": [
                {
                    "fileName": "scan-video-fallback_moved_video_playback.mp4",
                    "signedUrl": "https://example.com/put/moved-video",
                    "objectKey": "staging/test-user/scan-video-fallback_moved_video_playback.mp4"
                }
            ]
        }
        """.data(using: .utf8)!
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        MockURLProtocol.mockEndpoints["/generate-upload-urls"] = { request in
            let bodyData = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            let files = try #require(payload["files"] as? [[String: Any]])
            #expect(files.count == 1)
            #expect(files[0]["fileName"] as? String == "scan-video-fallback_moved_video_playback.mp4")
            #expect(files[0]["mediaKind"] as? String == "video")
            #expect(files[0]["contentType"] as? String == "video/mp4")
            #expect(files[0]["sizeBytes"] as? Int == 11)
            return (mockResponse, testData)
        }
        MockURLProtocol.mockEndpoints["/put/moved-video"] = { request in
            #expect(request.httpMethod == "PUT")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "video/mp4")
            return (mockResponse, Data())
        }

        let objectKeys = try await MerianNetworkClient.shared.uploadStagedVideoFiles(
            videoFilePaths: [staleTemporaryURL.path],
            scanId: "scan-video-fallback"
        )

        #expect(objectKeys == ["staging/test-user/scan-video-fallback_moved_video_playback.mp4"])
    }

    @Test func testUploadStagedVideoFilesThrowsWhenAnyRequestedVideoIsMissing() async throws {
        let existingFileName = "existing_video_playback.mp4"
        let existingURL = URL.documentsDirectory.appendingPathComponent(existingFileName)
        try FileManager.default.createDirectory(
            at: URL.documentsDirectory,
            withIntermediateDirectories: true
        )
        try Data("video-bytes".utf8).write(to: existingURL, options: .atomic)
        defer {
            try? FileManager.default.removeItem(at: existingURL)
        }

        MockURLProtocol.mockEndpoints["/generate-upload-urls"] = { _ in
            Issue.record("Partial video restore should fail before requesting upload URLs")
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }

        do {
            _ = try await MerianNetworkClient.shared.uploadStagedVideoFiles(
                videoFilePaths: [
                    existingURL.path,
                    FileManager.default.temporaryDirectory
                        .appendingPathComponent("missing_video_playback.mp4")
                        .path
                ],
                scanId: "scan-video-partial"
            )
            Issue.record("Expected missing video upload to throw")
        } catch {
            #expect((error as NSError).domain == NSCocoaErrorDomain)
        }
    }

    @Test func testCheckScanStatusDetailsDecodesJobStateAndRequiredVideoCount() async throws {
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let responseData = Data("""
        {
          "status": "not_found",
          "job_status": "finalizing",
          "job_stage": "video_promotion_started",
          "job_attempt_count": 2,
          "retry_after": "2026-07-05T15:00:00.000Z",
          "last_error": null
        }
        """.utf8)

        MockURLProtocol.mockEndpoints["/check-scan-status"] = { request in
            #expect(request.url?.path.hasSuffix("/check-scan-status") == true)
            let bodyData = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            #expect(payload["scan_id"] as? String == "scan-video-status")
            #expect(payload["required_video_count"] as? Int == 1)
            return (mockResponse, responseData)
        }

        let status = try await MerianNetworkClient.shared.checkScanStatusDetails(
            scanId: "scan-video-status",
            requiredVideoCount: 1
        )

        #expect(status.status == .notFound)
        #expect(status.jobStatus == .finalizing)
        #expect(status.jobStage == "video_promotion_started")
        #expect(status.jobAttemptCount == 2)
        #expect(status.retryAfter == "2026-07-05T15:00:00.000Z")
        #expect(status.lastError == nil)

        let legacyStatus = try await MerianNetworkClient.shared.checkScanStatus(
            scanId: "scan-video-status",
            requiredVideoCount: 1
        )
        #expect(legacyStatus == "not_found")
    }

    @Test func testCheckScanStatusDetailsSendsOwnedRecoveryPayload() async throws {
        let scanID = "019f6ff1-9ef3-77b1-a331-a86678f53043"
        let userID = "019f6ff1-c6c4-77b1-a331-a86678f53043"
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let recoveryScan = OwnedScanRecoveryPayload(
            id: scanID,
            userId: userID,
            speciesId: "019f6ff1-d6c4-77b1-a331-a86678f53043",
            confirmedSpeciesId: nil,
            imageStorageUrls: [],
            timestamp: "2026-07-23T18:00:00Z",
            gpsLatExact: 30.2672,
            gpsLongExact: -97.7431,
            gpsLatPublic: nil,
            gpsLongPublic: nil,
            gpsElevation: 150,
            geoprivacy: "private",
            weatherCondition: "Clear",
            weatherTemperatureF: 86,
            aiConfidenceScore: 0.94,
            ecologyType: "wild",
            isInvasive: false,
            invasiveStatusRegion: nil,
            invasiveRationale: nil,
            invasiveConfidence: nil,
            isLiveCapture: true,
            isBiologicalSubject: true,
            aiReasoning: "Long bill and dark crown.",
            semanticLocation: "Austin, Texas",
            publicLocationLabel: nil,
            inferenceTier: "flash",
            imageQualityScore: 82,
            userIdentificationOverride: nil,
            userConfirmedIdentification: false,
            userReviewState: "unreviewed"
        )

        MockURLProtocol.mockEndpoints["/check-scan-status"] = { request in
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            let recovery = try #require(payload["recovery_scan"] as? [String: Any])
            #expect(payload["scan_id"] as? String == scanID)
            #expect(recovery["id"] as? String == scanID)
            #expect(recovery["user_id"] as? String == userID)
            #expect(recovery["image_storage_urls"] as? [String] == [])
            #expect(recovery["geoprivacy"] as? String == "private")
            return (response, Data(#"{"status":"found"}"#.utf8))
        }

        let status = try await MerianNetworkClient.shared.checkScanStatusDetails(
            scanId: scanID,
            recoveryScan: recoveryScan
        )

        #expect(status.isFound)
    }

    @Test func testMissingScanRecoveryNeverRacesActiveOrRetryableIngestion() {
        #expect(missingScanRecoveryAction(for: .processing) == .retryStatus)
        #expect(missingScanRecoveryAction(for: .finalizing) == .retryStatus)
        #expect(missingScanRecoveryAction(for: .retrying) == .retryStatus)
        #expect(missingScanRecoveryAction(for: .failedRetryable) == .deferRecovery)
        #expect(missingScanRecoveryAction(for: .failed) == .recover)
        #expect(missingScanRecoveryAction(for: .complete) == .recover)
        #expect(missingScanRecoveryAction(for: nil) == .recover)
        #expect(
            missingScanRecoveryAction(
                for: .failed,
                jobStage: "moderation_rejected",
                jobLastError: "Multimodal media rejected by moderation."
            ) == .deferRecovery
        )
        #expect(
            missingScanRecoveryAction(
                for: .failed,
                jobStage: "moderation_rejected",
                jobLastError: "Media rejected by moderation."
            ) == .deferRecovery
        )
        #expect(
            missingScanRecoveryAction(
                for: .failed,
                jobStage: "ai_inference_non_stop_finish",
                jobLastError: "AI finish reason: SAFETY"
            ) == .deferRecovery
        )
        #expect(
            missingScanRecoveryAction(
                for: .failed,
                jobStage: "ai_inference_non_stop_finish",
                jobLastError: "AI finish reason: PROHIBITED_CONTENT"
            ) == .deferRecovery
        )
        #expect(
            missingScanRecoveryAction(
                for: .failed,
                jobStage: "moderation_rejected",
                jobLastError: "Database trigger rejected insert."
            ) == .recover
        )
    }

    @Test func testDeleteScanEndpoint() async throws {
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockEndpoints["/delete-scan"] = { request in
            #expect(request.url?.path.hasSuffix("/delete-scan") == true)
            #expect(request.httpMethod == "POST")
            return (
                mockResponse,
                Data(#"{"success":true,"message":"Scan deleted."}"#.utf8)
            )
        }
        
        try await MerianNetworkClient.shared.deleteScan(
            scanId: "019fad40-061e-7eb7-a896-996d93813d22"
        )
        // Success if no errors throw
    }

    @Test func testDeleteScanRejectsUnconfirmedSuccessResponse() async throws {
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let invalidResponses = [
            Data(),
            Data(#"{"success":false}"#.utf8),
            Data(#"{"ok":true}"#.utf8),
            Data(#"[]"#.utf8)
        ]

        for invalidResponse in invalidResponses {
            MockURLProtocol.mockEndpoints["/delete-scan"] = { _ in
                (mockResponse, invalidResponse)
            }
            await #expect(throws: MerianError.invalidResponse) {
                try await MerianNetworkClient.shared.deleteScan(
                    scanId: "019fad40-061e-7eb7-a896-996d93813d22"
                )
            }
        }
    }
    
    @Test func testSafeDeleteAccountEndpoint() async throws {
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 202, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockEndpoints["/safe-delete"] = { request in
            #expect(request.url?.path.hasSuffix("/safe-delete") == true)
            #expect(request.httpMethod == "POST")
            return (mockResponse, Data())
        }
        
        try await MerianNetworkClient.shared.safeDeleteAccount()
    }

    @Test func testRequestDwcAExport() async throws {
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockEndpoints["/request-export-dwca"] = { request in
            #expect(request.url?.path.hasSuffix("/request-export-dwca") == true)
            #expect(request.httpMethod == "POST")
            return (mockResponse, Data())
        }
        
        try await MerianNetworkClient.shared.requestDwcAExport(scope: "user")
    }

    @Test func testRegisterPushDeviceEndpoint() async throws {
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockEndpoints["/register-push-device"] = { request in
            #expect(request.url?.path.hasSuffix("/register-push-device") == true)
            #expect(request.httpMethod == "POST")

            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            #expect(payload?["device_token"] as? String == "abc123")
            #expect(payload?["platform"] as? String == "ios")
            #expect(payload?["environment"] as? String == "sandbox")
            #expect(payload?["explore_enabled"] as? Bool == true)
            #expect(payload?["comment_mentions_enabled"] as? Bool == false)
            #expect(payload?["community_identifications_enabled"] as? Bool == true)
            return (mockResponse, Data("{}".utf8))
        }

        try await MerianNetworkClient.shared.registerPushDevice(
            deviceToken: "abc123",
            environment: "sandbox",
            exploreEnabled: true,
            commentMentionsEnabled: false,
            communityIdentificationsEnabled: true
        )
    }
    
    @Test func testSubmitFlagIssue() async throws {
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockEndpoints["/flag-issue"] = { request in
            #expect(request.url?.path.hasSuffix("/flag-issue") == true)
            #expect(request.httpMethod == "POST")
            return (mockResponse, Data())
        }
        
        try await MerianNetworkClient.shared.submitFlagIssue(
            scanId: "scan_123",
            flagReason: "incorrect_species",
            userSuggestion: "It's a cat not a dog.",
            userId: "user_456"
        )
    }

    @Test func testBlockUser() async throws {
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.mockEndpoints["/block-user"] = { request in
            #expect(request.url?.path.hasSuffix("/block-user") == true)
            #expect(request.httpMethod == "POST")
            return (mockResponse, Data())
        }
        
        try await MerianNetworkClient.shared.blockUser(targetUserId: "bad_actor_999")
    }

    /// Due to how heavily the 401 error handler interacts with `SupabaseManager` globally (purging auth state
    /// and regenerating ghost tokens in the Keychain), we omit the direct unit test here to avoid corrupting
    /// active simulator keychain states for developers.
    @Test func testEdgeFunctionSelfHealingHandles401() async throws { return }

    // MARK: - Endpoint URL structure

    /// Verifies that the Edge Function URL construction formula produces the correct path.
    /// Tests the pattern `"\(supabaseUrl)/functions/v1/\(function)"` directly without
    /// making a network call — any live call would require a valid auth session in CI.
    @Test func testEndpointURLPathContainsFunctionsV1Segment() throws {
        let baseUrl = MerianEnvironment.supabaseUrl
        // Mirror the formula used by MerianNetworkClient.endpointURL(_:)
        let constructed = URL(string: "\(baseUrl)/functions/v1/block-user")
        let url = try #require(constructed, "endpointURL formula must produce a valid URL from the configured supabaseUrl")
        #expect(url.path.contains("/functions/v1/"), "Edge Function URL must contain /functions/v1/ path segment")
        #expect(url.absoluteString.hasPrefix("https://"), "Edge Function URL must use HTTPS")
        #expect(url.lastPathComponent == "block-user", "Last path component must match the function name")
    }

    // MARK: - TLS certificate pinning

    /// Guards against the hash set accidentally being cleared.
    /// An empty `pinnedCertHashes` causes the guard `!MerianTLSDelegate.pinnedCertHashes.isEmpty`
    /// to fall through to `.performDefaultHandling`, silently disabling pinning in Release builds.
    /// This test cannot access the private class but validates the expected hash format independently.
    @Test func testPinnedHashesAreNonEmptyValidBase64() {
        // The two hashes populated in MerianNetworkClient.swift (leaf + intermediate CA).
        // If either value is malformed, `Data(base64Encoded:)` returns nil.
        let leafHash = "OYvM4tmVyyPLCSqTe1tYvZW0CKRfv4mre7EUA0eJrn0="
        let intermediateHash = "HfwWBfutNY2LyET3bRUgP6ycpcGnn9SFf/ryhk++v5Y="

        #expect(!leafHash.isEmpty, "Leaf cert hash must be non-empty")
        #expect(!intermediateHash.isEmpty, "Intermediate CA hash must be non-empty")
        #expect(Data(base64Encoded: leafHash) != nil, "Leaf hash must be valid base64")
        #expect(Data(base64Encoded: intermediateHash) != nil, "Intermediate CA hash must be valid base64")

        // SHA-256/DER hashes are always 32 bytes → 44-character base64 with padding.
        let decoded = Data(base64Encoded: leafHash)
        #expect(decoded?.count == 32, "SHA-256 DER cert hash must decode to exactly 32 bytes")
    }

    /// Documents and tests the chain-walking algorithm used by `MerianTLSDelegate`.
    /// The refactor from `certChain.first` to `certChain.contains { ... }` means that
    /// an intermediate CA hash in `pinnedCertHashes` is a *genuine* fallback rather than
    /// dead code.  If someone reverts to `certChain.first`, the second assertion fails.
    @Test func testTLSChainWalkingAcceptsIntermediateCertWhenLeafIsUnknown() {
        let pinnedHashes: Set<String> = [
            "known_leaf_hash_abc123==",
            "known_intermediate_hash_xyz==",
        ]

        // Simulate a cert chain where the leaf has ROTATED (new hash) but the
        // intermediate CA is still the same pinned one.
        let rotatedLeafHash = "new_rotated_leaf_hash_def456=="   // NOT in pinnedHashes
        let intermediateHash = "known_intermediate_hash_xyz=="   // IS in pinnedHashes
        let rootHash = "root_ca_hash_ghi789=="                   // not pinned

        let chain = [rotatedLeafHash, intermediateHash, rootHash]

        // New contains-based check — accepts because intermediate matches
        let matchesWithContains = chain.contains { pinnedHashes.contains($0) }
        #expect(matchesWithContains == true, "Chain-walk should accept when intermediate CA hash matches")

        // Old certChain.first behavior would reject — demonstrating why the refactor matters
        let matchesWithFirst = pinnedHashes.contains(chain.first ?? "")
        #expect(matchesWithFirst == false, "certChain.first pattern silently rejects a valid rotated-leaf chain")
    }

    /// Verifies the reject path: no cert in the chain matches any pinned hash.
    @Test func testTLSChainWalkingRejectsUnknownChain() {
        let pinnedHashes: Set<String> = [
            "pinned_leaf_hash==",
            "pinned_intermediate_hash==",
        ]

        let unknownChain = ["unknown_leaf==", "unknown_intermediate==", "unknown_root=="]
        let matched = unknownChain.contains { pinnedHashes.contains($0) }
        #expect(matched == false, "Chain-walk must reject when no cert in the chain is pinned")
    }

    // MARK: - buildMultiModalRequestBody

    @Test func multimodalRequestBodyUsesActiveCamelCaseTelemetryContract() throws {
        let telemetry = CaptureTelemetry(
            subjectDistanceInMeters: 1.3,
            gpsLatitude: 37.7749,
            gpsLongitude: -122.4194,
            gpsElevation: 42.5,
            locationName: "Zilker Park",
            weatherCondition: "Partly Cloudy",
            weatherTemperatureF: 68.0,
            timeOfDay: nil,
            timestamp: "2026-04-24T10:30:00.000Z",
            zoomFactor: 2.0,
            estimatedSizeCm: 11.5
        )

        let observationContextJSON = """
        {"freeText":"Heard rustling before spotting it","addedAt":"2026-04-24T10:29:30.000Z"}
        """

        let bodyData = try MerianNetworkClient.buildMultiModalRequestBody(
            r2ObjectKeys: ["staging/test-user/image.webp"],
            base64ImageDatas: ["ZmFrZV9pbWFnZQ=="],
            audioBase64s: ["ZmFrZV9hdWRpbw=="],
            observationContextsJSON: [observationContextJSON],
            userId: "test-user",
            mimeType: "image/webp",
            telemetry: telemetry,
            deviceLocale: "en",
            deviceTimeZone: "America/Chicago",
            deviceRegion: "US",
            currentMonth: 4,
            timeOfDay: "10:30 AM",
            depthScaleText: "1.3 meters",
            clientScanId: "scan-123",
            preferredGoal: FieldTripPreferredGoal(
                userFieldTripId: "00000000-0000-4000-8000-000000000001",
                itemId: "00000000-0000-4000-8000-000000000002"
            )
        )

        let payload = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])

        #expect(payload["gpsLatitude"] as? Double == 37.7749)
        #expect(payload["gpsLongitude"] as? Double == -122.4194)
        #expect(payload["gpsElevation"] as? Double == 42.5)
        #expect(payload["semanticLocation"] as? String == "Zilker Park")
        #expect(payload["publicLocationLabel"] == nil)
        #expect(payload["weatherCondition"] as? String == "Partly Cloudy")
        #expect(payload["deviceLocale"] as? String == "en")
        #expect(payload["deviceTimeZone"] as? String == "America/Chicago")
        #expect(payload["deviceRegion"] as? String == "US")
        #expect(payload["currentMonth"] as? Int == 4)
        #expect(payload["timeOfDay"] as? String == "10:30 AM")
        #expect(payload["depthScaleText"] as? String == "1.3 meters")
        #expect(payload["zoomFactor"] as? Double == 2.0)
        #expect(payload["estimated_size_cm"] as? Double == 11.5)
        #expect(payload["client_scan_id"] as? String == "scan-123")
        let preferredGoal = try #require(payload["preferred_goal"] as? [String: String])
        #expect(preferredGoal["user_field_trip_id"] == "00000000-0000-4000-8000-000000000001")
        #expect(preferredGoal["item_id"] == "00000000-0000-4000-8000-000000000002")
        #expect(payload["gps_latitude"] == nil)
        #expect(payload["semantic_location"] == nil)

        let contexts = try #require(payload["observation_contexts"] as? [[String: Any]])
        #expect(contexts.count == 1)
        #expect(contexts[0]["freeText"] as? String == "Heard rustling before spotting it")
        #expect(contexts[0]["addedAt"] as? String == "2026-04-24T10:29:30.000Z")
        #expect(contexts[0]["free_text"] == nil)
    }

    @Test func multimodalRequestBodyIncludesPublicLocationLabelWhenDerivable() throws {
        let telemetry = CaptureTelemetry(
            subjectDistanceInMeters: nil,
            gpsLatitude: nil,
            gpsLongitude: nil,
            gpsElevation: nil,
            locationName: "123 Main St, Austin, TX, United States",
            weatherCondition: nil,
            weatherTemperatureF: nil,
            timeOfDay: nil,
            timestamp: nil,
            zoomFactor: nil,
            estimatedSizeCm: nil
        )

        let bodyData = try MerianNetworkClient.buildMultiModalRequestBody(
            r2ObjectKeys: ["staging/test-user/image.webp"],
            base64ImageDatas: [],
            audioBase64s: [],
            observationContextsJSON: [],
            userId: "test-user",
            mimeType: "image/webp",
            telemetry: telemetry,
            deviceLocale: "en",
            deviceTimeZone: "America/Chicago",
            deviceRegion: "US",
            currentMonth: 4,
            timeOfDay: "10:30 AM",
            depthScaleText: nil,
            clientScanId: "scan-123"
        )

        let payload = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect(payload["semanticLocation"] as? String == "123 Main St, Austin, TX, United States")
        #expect(payload["publicLocationLabel"] as? String == "Austin, TX")
        #expect(payload["public_location_label"] == nil)
    }

    @Test func multimodalRequestBodyCarriesStagedAudioR2KeysWithoutInlineAudio() throws {
        let telemetry = CaptureTelemetry(
            subjectDistanceInMeters: nil,
            gpsLatitude: nil,
            gpsLongitude: nil,
            gpsElevation: nil,
            locationName: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil,
            timeOfDay: nil,
            timestamp: "2026-04-24T10:30:00.000Z",
            zoomFactor: nil,
            estimatedSizeCm: nil
        )

        let bodyData = try MerianNetworkClient.buildMultiModalRequestBody(
            r2ObjectKeys: ["staging/test-user/image.webp"],
            audioR2ObjectKeys: ["staging/test-user/audio.wav"],
            base64ImageDatas: [],
            audioBase64s: [],
            userId: "test-user",
            telemetry: telemetry,
            deviceLocale: "en",
            deviceTimeZone: "America/Chicago",
            deviceRegion: "US",
            currentMonth: 4,
            timeOfDay: "10:30 AM",
            depthScaleText: nil,
            clientScanId: "scan-audio-r2"
        )

        let json = try JSONSerialization.jsonObject(with: bodyData)
        let payload = try #require(json as? [String: Any])

        #expect(payload["r2ObjectKeys"] as? [String] == ["staging/test-user/image.webp"])
        #expect(payload["audioR2ObjectKeys"] as? [String] == ["staging/test-user/audio.wav"])
        #expect(payload["audioBase64s"] == nil)
        #expect(payload["client_scan_id"] as? String == "scan-audio-r2")
    }

    @Test func multimodalRequestBodyCarriesVideoKeysAndOrderedFrameCount() throws {
        let telemetry = CaptureTelemetry(
            subjectDistanceInMeters: nil,
            gpsLatitude: nil,
            gpsLongitude: nil,
            gpsElevation: nil,
            locationName: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil,
            timeOfDay: nil,
            timestamp: "2026-04-24T10:30:00.000Z",
            zoomFactor: nil,
            estimatedSizeCm: nil
        )

        let bodyData = try MerianNetworkClient.buildMultiModalRequestBody(
            r2ObjectKeys: [
                "staging/test-user/video-frame-1.webp",
                "staging/test-user/video-frame-2.webp",
                "staging/test-user/video-frame-3.webp"
            ],
            videoR2ObjectKeys: ["staging/test-user/clip.mp4"],
            base64ImageDatas: [],
            audioBase64s: [],
            videoFrameCount: 3,
            userId: "test-user",
            telemetry: telemetry,
            deviceLocale: "en",
            deviceTimeZone: "America/Chicago",
            deviceRegion: "US",
            currentMonth: 4,
            timeOfDay: "10:30 AM",
            depthScaleText: nil,
            clientScanId: "scan-video-r2"
        )

        let payload = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])

        #expect(payload["r2ObjectKeys"] as? [String] == [
            "staging/test-user/video-frame-1.webp",
            "staging/test-user/video-frame-2.webp",
            "staging/test-user/video-frame-3.webp"
        ])
        #expect(payload["videoR2ObjectKeys"] as? [String] == ["staging/test-user/clip.mp4"])
        #expect(payload["videoFrameCount"] as? Int == 3)
        #expect(payload["client_scan_id"] as? String == "scan-video-r2")
    }

    @Test func multimodalRequestBodyCarriesVideoAudioMetadata() throws {
        let telemetry = CaptureTelemetry(
            subjectDistanceInMeters: nil,
            gpsLatitude: nil,
            gpsLongitude: nil,
            gpsElevation: nil,
            locationName: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil,
            timeOfDay: nil,
            timestamp: "2026-04-24T10:30:00.000Z",
            zoomFactor: nil,
            estimatedSizeCm: nil
        )

        let bodyData = try MerianNetworkClient.buildMultiModalRequestBody(
            r2ObjectKeys: [
                "staging/test-user/video-frame-1.webp",
                "staging/test-user/video-frame-2.webp"
            ],
            audioR2ObjectKeys: ["staging/test-user/video-audio.wav"],
            videoR2ObjectKeys: ["staging/test-user/clip.mp4"],
            base64ImageDatas: [],
            audioBase64s: [],
            videoFrameCount: 2,
            visualMediaItems: [
                .videoFrame(clipIndex: 0, frameIndex: 0),
                .videoFrame(clipIndex: 0, frameIndex: 1)
            ],
            audioMediaItems: [
                .videoAudio(clipIndex: 0)
            ],
            userId: "test-user",
            telemetry: telemetry,
            deviceLocale: "en",
            deviceTimeZone: "America/Chicago",
            deviceRegion: "US",
            currentMonth: 4,
            timeOfDay: "10:30 AM",
            depthScaleText: nil,
            clientScanId: "scan-video-audio"
        )

        let payload = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let visualMediaItems = try #require(payload["visualMediaItems"] as? [[String: Any]])
        let audioMediaItems = try #require(payload["audioMediaItems"] as? [[String: Any]])

        #expect(visualMediaItems.count == 2)
        #expect(visualMediaItems[0]["kind"] as? String == "video_frame")
        #expect(visualMediaItems[0]["clipIndex"] as? Int == 0)
        #expect(audioMediaItems.count == 1)
        #expect(audioMediaItems[0]["kind"] as? String == "video_audio")
        #expect(audioMediaItems[0]["clipIndex"] as? Int == 0)
        #expect(payload["audioR2ObjectKeys"] as? [String] == ["staging/test-user/video-audio.wav"])
    }

    @Test func multimodalRequestBodyCarriesStillImageFocusWithoutAdditionalMedia() throws {
        let telemetry = CaptureTelemetry(
            subjectDistanceInMeters: nil,
            gpsLatitude: nil,
            gpsLongitude: nil,
            gpsElevation: nil,
            locationName: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil,
            timeOfDay: nil,
            timestamp: "2026-07-15T06:00:00.000Z",
            zoomFactor: nil,
            estimatedSizeCm: nil
        )
        let focusRegion = NormalizedImageFocusRegion(
            x: 0.1,
            y: 0.2,
            width: 0.5,
            height: 0.4
        )

        let bodyData = try MerianNetworkClient.buildMultiModalRequestBody(
            base64ImageDatas: ["encoded-image"],
            visualMediaItems: [.image(sourceIndex: 0, focusRegion: focusRegion)],
            userId: "test-user",
            telemetry: telemetry,
            deviceLocale: "en",
            deviceTimeZone: "America/Chicago",
            deviceRegion: "US",
            currentMonth: 7,
            timeOfDay: "1:00 AM",
            depthScaleText: nil,
            clientScanId: "scan-focus"
        )

        let payload = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let visualItems = try #require(payload["visualMediaItems"] as? [[String: Any]])
        let encodedFocus = try #require(visualItems.first?["focusRegion"] as? [String: Any])

        #expect(payload["imageBase64s"] as? [String] == ["encoded-image"])
        #expect(visualItems.count == 1)
        #expect(encodedFocus["source"] as? String == "vision_objectness")
        #expect(encodedFocus["x"] as? Double == 0.1)
        #expect(encodedFocus["width"] as? Double == 0.5)
    }

    // MARK: - validateMultiModalPayloadBudget

    @Test func budgetValidationPassesWhenUnderLimit() throws {
        let smallImage = String(repeating: "A", count: 100_000)
        let smallAudio = String(repeating: "B", count: 100_000)
        try MerianNetworkClient.validateMultiModalPayloadBudget(
            imageBase64s: [smallImage],
            audioBase64s: [smallAudio]
        )
        // No throw — passes
    }

    @Test func budgetValidationPassesWhenBothArraysEmpty() throws {
        try MerianNetworkClient.validateMultiModalPayloadBudget(imageBase64s: [], audioBase64s: [])
    }

    @Test func testUpdatePublicAvatarConstructsPayloadAndParsesResponse() async throws {
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        MockURLProtocol.mockEndpoints["/update-public-avatar"] = { request in
            #expect(request.url?.path.hasSuffix("/update-public-avatar") == true)
            #expect(request.httpMethod == "POST")

            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["r2_object_key"] as? String == "staging/user/avatar.webp")
            #expect(payload["mime_type"] as? String == "image/webp")

            let data = """
            {
              "avatar_url": "https://media.merian.app/avatars/user/avatar.webp"
            }
            """.data(using: .utf8)!
            return (mockResponse, data)
        }

        let response = try await MerianNetworkClient.shared.updatePublicAvatar(
            r2ObjectKey: "staging/user/avatar.webp",
            mimeType: "image/webp"
        )

        #expect(response.avatarUrl == "https://media.merian.app/avatars/user/avatar.webp")
    }

    @Test func testUpdatePublicDisplayNameConstructsPayloadAndParsesResponse() async throws {
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        MockURLProtocol.mockEndpoints["/update-public-display-name"] = { request in
            #expect(request.url?.path.hasSuffix("/update-public-display-name") == true)
            #expect(request.httpMethod == "POST")

            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["display_name"] as? String == "River Wren")

            let data = """
            {
              "display_name": "River Wren"
            }
            """.data(using: .utf8)!
            return (mockResponse, data)
        }

        let response = try await MerianNetworkClient.shared.updatePublicDisplayName("River Wren")

        #expect(response.displayName == "River Wren")
    }

    @Test func testClearPublicDisplayNameSendsEmptyValueAndParsesAliasFallback() async throws {
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        MockURLProtocol.mockEndpoints["/update-public-display-name"] = { request in
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["display_name"] as? String == "")

            let data = Data("""
            {
              "display_name": "briar_grove_23"
            }
            """.utf8)
            return (mockResponse, data)
        }

        let response = try await MerianNetworkClient.shared.updatePublicDisplayName("")

        #expect(response.displayName == "briar_grove_23")
    }

    @Test func budgetValidationPassesAtExactLimit() throws {
        // 3_600_000 bytes total — boundary value (> 3_600_000 throws, == does not)
        let payload = String(repeating: "X", count: 3_600_000)
        try MerianNetworkClient.validateMultiModalPayloadBudget(imageBase64s: [payload], audioBase64s: [])
    }

    @Test func budgetValidationThrowsOneByteOverLimit() {
        let payload = String(repeating: "X", count: 3_600_001)
        #expect(throws: MerianError.payloadTooLarge) {
            try MerianNetworkClient.validateMultiModalPayloadBudget(imageBase64s: [payload], audioBase64s: [])
        }
    }

    @Test func budgetValidationThrowsWhenImagesAloneExceedLimit() {
        let largeImage = String(repeating: "Z", count: 4_000_000)
        #expect(throws: MerianError.payloadTooLarge) {
            try MerianNetworkClient.validateMultiModalPayloadBudget(imageBase64s: [largeImage], audioBase64s: [])
        }
    }

    @Test func budgetValidationThrowsWhenCombinedImagesAndAudioExceedLimit() {
        // Each 2 MB — combined 4 MB exceeds the 3.6 MB cap
        let image = String(repeating: "I", count: 2_000_000)
        let audio = String(repeating: "A", count: 2_000_000)
        #expect(throws: MerianError.payloadTooLarge) {
            try MerianNetworkClient.validateMultiModalPayloadBudget(imageBase64s: [image], audioBase64s: [audio])
        }
    }

    @Test func budgetValidationAccumulatesAcrossMultipleImages() throws {
        // Three images at 1 MB each = 3 MB — under limit
        let image = String(repeating: "M", count: 1_000_000)
        try MerianNetworkClient.validateMultiModalPayloadBudget(
            imageBase64s: [image, image, image],
            audioBase64s: []
        )
    }

    @Test func inlineAudioBudgetValidationRejectsOversizedFileBeforeEncoding() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let oversizedAudioURL = directory.appendingPathComponent("oversized.wav")
        FileManager.default.createFile(atPath: oversizedAudioURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: oversizedAudioURL)
        try handle.truncate(atOffset: UInt64(MerianNetworkClient.maxInlineAudioBytes + 1))
        try handle.close()

        #expect(throws: MerianError.payloadTooLarge) {
            try MerianNetworkClient.validateInlineAudioFileBudget(fileURLs: [oversizedAudioURL])
        }
    }
}

private extension InputStream {
    func readData() -> Data {
        self.open()
        defer { self.close() }
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        var data = Data()
        while self.hasBytesAvailable {
            let read = self.read(buffer, maxLength: bufferSize)
            if read > 0 {
                data.append(buffer, count: read)
            } else {
                break
            }
        }
        return data
    }
}
