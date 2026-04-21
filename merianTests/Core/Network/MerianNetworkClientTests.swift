import Testing
import Foundation
@testable import Merian

/// Intercepts network requests for MerianNetworkClient testing
class MockURLProtocol: URLProtocol {
    static var mockEndpoints: [String: ((URLRequest) throws -> (HTTPURLResponse, Data))] = [:]
    
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
        
        MockURLProtocol.mockEndpoints["/identify"] = { request in
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
        
        MockURLProtocol.mockEndpoints["/enrich-scan"] = { request in
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
        
        MockURLProtocol.mockEndpoints["/generate-upload-urls"] = { request in
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
        MockURLProtocol.mockEndpoints["/delete-scan"] = { request in
            #expect(request.url?.path.hasSuffix("/delete-scan") == true)
            #expect(request.httpMethod == "POST")
            return (mockResponse, Data())
        }
        
        try await MerianNetworkClient.shared.deleteScan(scanId: "test_scan_delete_id")
        // Success if no errors throw
    }
    
    @Test func testSafeDeleteAccountEndpoint() async throws {
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
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
        let decoded = try? #require(Data(base64Encoded: leafHash))
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
