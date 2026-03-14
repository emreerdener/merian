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

@MainActor
struct MerianNetworkClientTests {
    
    init() {
        // Register the mock protocol to intercept URLSession.shared requests
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    @Test func testGenerateUploadURLsInjectsHeadersAndDecodesResponse() async throws {
        // Arrange
        let mockJSON = """
        {
            "urls": [
                {
                    "fileName": "test1.jpg",
                    "signedUrl": "https://r2.mock/test1",
                    "objectKey": "staging/uuid_test1.jpg"
                }
            ]
        }
        """.data(using: .utf8)!
        
        MockURLProtocol.requestHandler = { request in
            let urlString = request.url?.absoluteString ?? ""
            
            if urlString.contains("/auth/v1") {
                let mockAuthJSON = """
                {
                    "access_token": "mock-jwt-token",
                    "token_type": "bearer",
                    "expires_in": 3600,
                    "refresh_token": "mock-refresh",
                    "user": {
                        "id": "12345678-1234-1234-1234-123456789012",
                        "aud": "authenticated",
                        "role": "authenticated",
                        "email": "test@example.com",
                        "phone": "",
                        "app_metadata": {},
                        "user_metadata": {},
                        "created_at": "2023-01-01T00:00:00Z",
                        "updated_at": "2023-01-01T00:00:00Z"
                    }
                }
                """.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, mockAuthJSON)
            }
            
            // Only assert on the target endpoint to ignore background Telemetry pings
            if urlString.contains("/functions/v1/generate-upload-urls") {
                // Assert Headers
                #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true, "Kong requires Authorization: Bearer")
                #expect(request.value(forHTTPHeaderField: "apikey") != nil, "Kong requires Supabase apikey header")
                #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
                
                // Assert Method
                #expect(request.httpMethod == "POST")
                
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                return (response, mockJSON)
            }
            
            // Fallback for unrelated telemetry
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (response, Data("{}".utf8))
        }
        
        // Mock Session
        try? await SupabaseManager.shared.client.auth.setSession(accessToken: "mock-jwt-token", refreshToken: "mock-refresh-token")
        let client = MerianNetworkClient.shared
        
        // Act
        let urls = try await client.generateUploadURLs(fileNames: ["test1.jpg"])
        
        // Assert
        #expect(urls.count == 1)
        #expect(urls.first?.fileName == "test1.jpg")
        #expect(urls.first?.objectKey == "staging/uuid_test1.jpg")
    }
    
    @Test func testEdgeFunctionSelfHealingHandles401() async throws {
        // Arrange
        var attemptCount = 0
        
        let mockSuccessJSON = """
        {
            "urls": []
        }
        """.data(using: .utf8)!
        
        MockURLProtocol.requestHandler = { request in
            let urlString = request.url?.absoluteString ?? ""
            
            if urlString.contains("/auth/v1") {
                let mockAuthJSON = """
                {
                    "access_token": "mock-jwt-token",
                    "token_type": "bearer",
                    "expires_in": 3600,
                    "expires_at": 1672535000,
                    "refresh_token": "mock-refresh",
                    "user": {
                        "id": "12345678-1234-1234-1234-123456789012",
                        "aud": "authenticated",
                        "role": "authenticated",
                        "email": "test@example.com",
                        "phone": "",
                        "app_metadata": {},
                        "user_metadata": {},
                        "identities": [],
                        "created_at": "2023-01-01T00:00:00Z",
                        "updated_at": "2023-01-01T00:00:00Z"
                    }
                }
                """.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, mockAuthJSON)
            }
            
            if urlString.contains("/functions/v1/generate-upload-urls") {
                attemptCount += 1
                if attemptCount == 1 {
                    // Return 401 Unauthorized initially to trigger self-healing loop
                    let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                    return (response, Data("{}".utf8))
                } else {
                    // Return success on precisely the 2nd attempt
                    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                    return (response, mockSuccessJSON)
                }
            }
            
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (response, Data("{}".utf8))
        }
        
        // Mock Session
        try? await SupabaseManager.shared.client.auth.setSession(accessToken: "mock-jwt-token", refreshToken: "mock-refresh-token")
        let client = MerianNetworkClient.shared
        
        // Act
        let urls = try await client.generateUploadURLs(fileNames: ["retry.jpg"])
        
        // Assert
        #expect(urls.isEmpty == true, "Should return empty mapped array on successful self-healed retry")
        #expect(attemptCount == 2, "It must have exactly attempted twice due to the 401 trap")
    }
    
    @Test func testDeleteScanEndpoint() async throws {
        let testScanId = "abc-123"
        MockURLProtocol.requestHandler = { request in
            let urlString = request.url?.absoluteString ?? ""
            
            if urlString.contains("/auth/v1") {
                let mockAuthJSON = """
                {
                    "access_token": "mock-jwt-token",
                    "token_type": "bearer",
                    "expires_in": 3600,
                    "expires_at": 1672535000,
                    "refresh_token": "mock-refresh",
                    "user": {
                        "id": "12345678-1234-1234-1234-123456789012",
                        "aud": "authenticated",
                        "role": "authenticated",
                        "email": "test@example.com",
                        "phone": "",
                        "app_metadata": {},
                        "user_metadata": {},
                        "identities": [],
                        "created_at": "2023-01-01T00:00:00Z",
                        "updated_at": "2023-01-01T00:00:00Z"
                    }
                }
                """.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, mockAuthJSON)
            }
            
            // Analyze ONLY the explicit /delete-scan boundary payload
            if urlString.contains("/delete-scan") {
                // Analyze the JSON HTTP body mapped from the dictionary
                if let bodyData = request.httpBody ?? request.httpBodyStream?.readData(),
                   let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: String] {
                    #expect(json["scanId"] == testScanId)
                } else {
                    Issue.record("Failed to decode JSON body or missing scanId")
                }
            }
            
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (response, Data("{}".utf8))
        }
        
        // Mock Session
        try? await SupabaseManager.shared.client.auth.setSession(accessToken: "mock-jwt-token", refreshToken: "mock-refresh-token")
        let client = MerianNetworkClient.shared
        
        // Act / Assert
        try await client.deleteScan(scanId: testScanId)
        // If no exception is thrown, the test natively succeeds mapping 200 logic.
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
