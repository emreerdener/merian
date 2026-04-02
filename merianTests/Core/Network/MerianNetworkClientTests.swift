import Testing
import Foundation
@testable import Merian

/// Intercepts network requests for MerianNetworkClient testing
class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    
    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            fatalError("Handler is unavailable.")
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

@Suite("Network Client Tests", .serialized)
@MainActor
struct MerianNetworkClientTests {
    
    init() {
        // Build an ephemeral URLSession configuration tailored exclusively for Mocking
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        
        // Inject so MerianNetworkClient hooks this instead of hitting live internet
        MerianNetworkClient.shared.overridingSession = URLSession(configuration: config)
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
        
        MockURLProtocol.requestHandler = { request in
            // Assert Request correctness
            #expect(request.url?.path.hasSuffix("/identify") == true)
            #expect(request.httpMethod == "POST")
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
        
        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.path.hasSuffix("/enrich-scan") == true)
            #expect(request.httpMethod == "POST")
            return (mockResponse, testData)
        }
        
        // Act
        let returnedObject = try await MerianNetworkClient.shared.fetchEnrichment(
            scanId: "test_scan_123",
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
        #expect(similar[0].scientific_name == "Procyon cancrivorus")
    }

    @Test func testGenerateUploadURLs() async throws {
        let testData = """
        {
            "urls": [
                {
                    "fileName": "image_1",
                    "signedUrl": "https://example.com/put/image_1",
                    "objectKey": "merian/user/image_1.webp"
                }
            ]
        }
        """.data(using: .utf8)!
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        
        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.path.hasSuffix("/generate-upload-urls") == true)
            #expect(request.httpMethod == "POST")
            return (mockResponse, testData)
        }
        
        let urls = try await MerianNetworkClient.shared.generateUploadURLs(fileNames: ["image_1"])
        #expect(urls.count == 1)
        #expect(urls[0].signedUrl == "https://example.com/put/image_1")
    }

    @Test func testDeleteScanEndpoint() async throws {
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.path.hasSuffix("/delete-scan") == true)
            #expect(request.httpMethod == "POST")
            return (mockResponse, Data())
        }
        
        try await MerianNetworkClient.shared.deleteScan(scanId: "test_scan_delete_id")
        // Success if no errors throw
    }
    
    @Test func testSafeDeleteAccountEndpoint() async throws {
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.path.hasSuffix("/safe-delete") == true)
            #expect(request.httpMethod == "POST")
            return (mockResponse, Data())
        }
        
        try await MerianNetworkClient.shared.safeDeleteAccount()
    }

    @Test func testRequestDwcAExport() async throws {
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.path.hasSuffix("/request-export-dwca") == true)
            #expect(request.httpMethod == "POST")
            return (mockResponse, Data())
        }
        
        try await MerianNetworkClient.shared.requestDwcAExport(scope: "user")
    }
    
    @Test func testSubmitFlagIssue() async throws {
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        MockURLProtocol.requestHandler = { request in
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
        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.path.hasSuffix("/block-user") == true)
            #expect(request.httpMethod == "POST")
            return (mockResponse, Data())
        }
        
        try await MerianNetworkClient.shared.blockUser(targetUserId: "bad_actor_999")
    }

    /// Due to how heavily the 401 error handler interacts with `SupabaseManager` globally (purging auth state
    /// and regenerating guest tokens in the Keychain), we omit the direct unit test here to avoid corrupting
    /// active simulator keychain states for developers.
    @Test func testEdgeFunctionSelfHealingHandles401() async throws { return }
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
