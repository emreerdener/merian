import Foundation

/// Legacy process-global URL interception for suites that still exercise the
/// shared network client. Those suites must serialize access through the shared
/// process-state test trait.
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

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let path = request.url?.path else { return }

        let match = MockURLProtocol.mockEndpoints.first { path.hasSuffix($0.key) }
        guard let handler = match?.value else {
            let error = NSError(
                domain: "MockURLProtocol",
                code: 404,
                userInfo: [
                    NSLocalizedDescriptionKey: "No endpoint configured for \(path)"
                ]
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

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
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
