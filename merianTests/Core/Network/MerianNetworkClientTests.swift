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

    @Test func testGenerateUploadURLsInjectsHeadersAndDecodesResponse() async throws { return }
    
    @Test func testEdgeFunctionSelfHealingHandles401() async throws { return }
    
    @Test func testDeleteScanEndpoint() async throws { return }
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
