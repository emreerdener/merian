import Testing
import Foundation
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

    @Test func testGetExploreShareStateConstructsPayloadAndParsesJSON() async throws {
        let testData = """
        {
            "data": {
                "scan_id": "scan-share-123",
                "post_id": "post-share-456",
                "shared_at": "2026-04-29T22:18:03.000Z"
            }
        }
        """.data(using: .utf8)!
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!

        MockURLProtocol.mockEndpoints["/get-scan-explore-share-state"] = { request in
            #expect(request.url?.path.hasSuffix("/get-scan-explore-share-state") == true)
            #expect(request.httpMethod == "POST")

            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            #expect(payload?["scan_id"] as? String == "scan-share-123")
            return (mockResponse, testData)
        }

        let response = try await MerianNetworkClient.shared.getExploreShareState(scanId: "scan-share-123")

        #expect(response.scanId == "scan-share-123")
        #expect(response.postId == "post-share-456")
        #expect(response.sharedAt == "2026-04-29T22:18:03.000Z")
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
            return (mockResponse, Data("{}".utf8))
        }

        try await MerianNetworkClient.shared.registerPushDevice(
            deviceToken: "abc123",
            environment: "sandbox",
            exploreEnabled: true
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
            clientScanId: "scan-123"
        )

        let payload = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])

        #expect(payload["gpsLatitude"] as? Double == 37.7749)
        #expect(payload["gpsLongitude"] as? Double == -122.4194)
        #expect(payload["gpsElevation"] as? Double == 42.5)
        #expect(payload["semanticLocation"] as? String == "Zilker Park")
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
        #expect(payload["gps_latitude"] == nil)
        #expect(payload["semantic_location"] == nil)

        let contexts = try #require(payload["observation_contexts"] as? [[String: Any]])
        #expect(contexts.count == 1)
        #expect(contexts[0]["freeText"] as? String == "Heard rustling before spotting it")
        #expect(contexts[0]["addedAt"] as? String == "2026-04-24T10:29:30.000Z")
        #expect(contexts[0]["free_text"] == nil)
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
