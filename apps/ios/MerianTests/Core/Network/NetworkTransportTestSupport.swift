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


/// Samples regular files open in the test process. Inodes and descriptor
/// numbers stay local. A sampled file is not necessarily an upload copy.
struct PhotoUploadResourceSample {
    private struct Identity: Hashable {
        let device: dev_t
        let inode: ino_t
        init(_ info: stat) { device = info.st_dev; inode = info.st_ino }
    }
    private var files: [Identity: Int64] = [:]
    let footprint: UInt64
    let lifetimePeak: Int64
    private(set) var originalOpen = false

    init(original: URL) throws {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        let capacity = Int(count)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { throw CocoaError(.fileReadUnknown) }
        footprint = info.phys_footprint
        lifetimePeak = info.ledger_phys_footprint_peak

        var source = stat(), limit = rlimit()
        guard lstat(original.path, &source) == 0, source.st_mode & S_IFMT == S_IFREG,
              getrlimit(RLIMIT_NOFILE, &limit) == 0, limit.rlim_cur <= 32768 else {
            throw CocoaError(.fileReadUnknown)
        }
        let originalID = Identity(source)
        for fd in 0..<Int32(limit.rlim_cur) {
            var item = stat()
            guard fstat(fd, &item) == 0 else {
                if errno == EBADF { continue }
                throw CocoaError(.fileReadUnknown)
            }
            guard item.st_mode & S_IFMT == S_IFREG else { continue }
            let id = Identity(item)
            if id == originalID {
                originalOpen = true
            } else {
                files[id] = Int64(item.st_blocks) * 512
            }
        }
    }

    func additionalOpenFileBytes(since baseline: Self) -> Int64 {
        files.reduce(0) { sum, entry in sum + max(0, entry.value - (baseline.files[entry.key] ?? 0)) }
    }
}
