import Foundation
import os
import Testing

@testable import Merian

@Suite("Media Upload Transport")
@MainActor
struct MediaUploadTests {
    @Test(arguments: MediaUploadTestKind.allCases, ["", "not-json", #"{"success":false}"#])
    func dataAndFileUploadsUseSignedPUTAndIgnoreSuccessBody(kind: MediaUploadTestKind, responseBody: String) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let files = try NetworkMediaFileFixture()
        defer { files.close() }
        let file = try files.write()
        fixture.client.overridingAuthUserID = nil
        fixture.client.overridingAuthSessionRefresh = {
            Issue.record("Storage uploads must not refresh Auth")
            return false
        }
        try await confirmation("One signed PUT") { sent in
            fixture.transport.register(path: "/put/media") { request in
                sent()
                #expect(request.httpMethod == "PUT")
                #expect(request.url?.absoluteString == MediaUploadTestFixtures.signedURL)
                #expect(request.value(forHTTPHeaderField: "Content-Type") == "video/mp4")
                #expect(request.value(forHTTPHeaderField: "Content-Length") == "4")
                for header in ["Authorization", "apikey", "Idempotency-Key", "X-Merian-Entitlement-Protocol"] {
                    #expect(request.value(forHTTPHeaderField: header) == nil)
                }
                if kind == .data {
                    #expect(try #require(MockURLProtocol.bodyData(for: request)) == MediaUploadTestFixtures.bytes)
                }
                return try NetworkEndpointTestSupport.response(to: request, json: responseBody)
            }
            try await kind.invoke(fixture.client, file: file, upload: MediaUploadTestFixtures.presignedURL())
        }
    }

    @Test(arguments: MediaUploadTestKind.allCases, [201, 204, 403, 503])
    func non200ResponsesFailWithoutRetry(kind: MediaUploadTestKind, status: Int) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let files = try NetworkMediaFileFixture()
        defer { files.close() }
        let file = try files.write()
        await confirmation("One failed PUT") { sent in
            fixture.transport.register(path: "/put/media") { request in
                sent()
                return try NetworkEndpointTestSupport.response(to: request, status: status, json: "{}")
            }
            await #expect(throws: MerianError.uploadFailed) {
                try await kind.invoke(fixture.client, file: file, upload: MediaUploadTestFixtures.presignedURL())
            }
        }
    }

    @Test(arguments: MediaUploadTestKind.allCases, [URLError.Code.cancelled, .networkConnectionLost, .timedOut])
    func transportErrorsRemainRawWithoutReplay(kind: MediaUploadTestKind, code: URLError.Code) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let files = try NetworkMediaFileFixture()
        defer { files.close() }
        let file = try files.write()
        await confirmation("One raw failure") { sent in
            fixture.transport.register(path: "/put/media") { _ in
                sent()
                throw URLError(code)
            }
            do {
                try await kind.invoke(fixture.client, file: file, upload: MediaUploadTestFixtures.presignedURL())
                Issue.record("A storage transport failure must propagate")
            } catch let error as URLError {
                #expect(error.code == code)
            } catch {
                Issue.record("Unexpected error type: \(type(of: error))")
            }
        }
    }

    @Test(arguments: MediaUploadTestKind.allCases)
    func cancellingTheOwningTaskStopsTheHeldPUTWithoutMappingItsError(kind: MediaUploadTestKind) async throws {
        let transport = MediaUploadCancellationTransport()
        defer { transport.close() }
        let files = try NetworkMediaFileFixture()
        defer { files.close() }
        let file = try files.write()
        let client = MerianNetworkClient()
        client.overridingSession = transport.session
        let completion = AsyncStream<Result<Void, Error>>.makeStream(bufferingPolicy: .bufferingOldest(1))
        let task = Task { @MainActor in
            do {
                try await kind.invoke(client, file: file, upload: MediaUploadTestFixtures.presignedURL())
                completion.continuation.yield(.success(()))
            } catch {
                completion.continuation.yield(.failure(error))
            }
            completion.continuation.finish()
        }
        defer {
            task.cancel()
            completion.continuation.finish()
        }

        let didStart = await transport.waitUntilStarted()
        task.cancel()
        guard let result = await transport.waitForCompletion(completion.stream) else {
            transport.close()
            Issue.record("Cancelled upload did not complete within the watchdog deadline")
            return
        }
        do {
            try result.get()
            Issue.record("Cancelling the owning task must fail the held upload")
        } catch let error as URLError {
            #expect(error.code == .cancelled)
        } catch {
            Issue.record("Raw uploads must not translate cancellation: \(type(of: error))")
        }
        #expect(didStart, "The upload must reach the held transport before cancellation")
        #expect(await transport.waitUntilStopped(), "Cancellation must stop the underlying URLSession request")
    }

    @Test(arguments: MediaUploadTestKind.allCases)
    func signedLengthMismatchFailsBeforeTransport(kind: MediaUploadTestKind) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let files = try NetworkMediaFileFixture()
        defer { files.close() }
        let file = try files.write()
        await confirmation("No invalid signed upload", expectedCount: 0) { sent in
            fixture.transport.register(path: "/put/media") { request in
                sent()
                return try NetworkEndpointTestSupport.response(to: request, json: "")
            }
            await #expect(throws: MerianError.invalidResponse) {
                try await kind.invoke(fixture.client, file: file, upload: MediaUploadTestFixtures.presignedURL(size: 5))
            }
        }
    }

    @Test func fileIsRestattedAfterSigning() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let files = try NetworkMediaFileFixture()
        defer { files.close() }
        let file = try files.write()
        let signed = MediaUploadTestFixtures.presignedURL()
        try Data([0]).write(to: file, options: .atomic)
        await confirmation("No stale-length upload", expectedCount: 0) { sent in
            fixture.transport.register(path: "/put/media") { request in
                sent()
                return try NetworkEndpointTestSupport.response(to: request, json: "")
            }
            await #expect(throws: MerianError.invalidResponse) {
                try await fixture.client.uploadToR2(uploadURL: signed, fileURL: file, contentType: "video/mp4")
            }
        }
    }

    @Test func missingFileFailurePrecedesSignedURLValidation() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let files = try NetworkMediaFileFixture()
        defer { files.close() }
        do {
            try await fixture.client.uploadToR2(
                uploadURL: MediaUploadTestFixtures.presignedURL(signedURL: ""),
                fileURL: files.directory.appendingPathComponent("missing.mp4"), contentType: "video/mp4"
            )
            Issue.record("Missing file must fail before transfer")
        } catch {
            #expect((error as NSError).domain == NSCocoaErrorDomain)
        }
    }
}

enum MediaUploadTestKind: CaseIterable, Sendable {
    case data, file

    @MainActor
    func invoke(_ client: MerianNetworkClient, file: URL, upload: PreSignedURL) async throws {
        switch self {
        case .data:
            try await client.uploadToR2(uploadURL: upload, data: MediaUploadTestFixtures.bytes, contentType: "video/mp4")
        case .file:
            try await client.uploadToR2(uploadURL: upload, fileURL: file, contentType: "video/mp4")
        }
    }
}

/// Holds a real URLSession request open until cancellation, with per-test signals.
private struct MediaUploadCancellationTransport {
    let session: URLSession
    private let scopeID = UUID().uuidString
    private let started: AsyncStream<Void>
    private let stopped: AsyncStream<Void>

    init() {
        let startSignal = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingOldest(1))
        let stopSignal = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingOldest(1))
        started = startSignal.stream
        stopped = stopSignal.stream
        MediaUploadCancellationURLProtocol.register(
            scopeID: scopeID, started: startSignal.continuation, stopped: stopSignal.continuation
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MediaUploadCancellationURLProtocol.self]
        configuration.httpAdditionalHeaders = [MediaUploadCancellationURLProtocol.scopeHeader: scopeID]
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        session = URLSession(configuration: configuration)
    }

    func close() {
        session.invalidateAndCancel()
        MediaUploadCancellationURLProtocol.remove(scopeID: scopeID)
    }

    func waitUntilStarted() async -> Bool { await firstValue(from: started) != nil }
    func waitUntilStopped() async -> Bool { await firstValue(from: stopped) != nil }

    func waitForCompletion(_ completion: AsyncStream<Result<Void, Error>>) async -> Result<Void, Error>? {
        await firstValue(from: completion)
    }

    private func firstValue<Value: Sendable>(from stream: AsyncStream<Value>) async -> Value? {
        await withTaskGroup(of: Value?.self) { group in
            group.addTask {
                for await value in stream { return value }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return nil
            }
            defer { group.cancelAll() }
            guard let value = await group.next() else { return nil }
            return value
        }
    }
}

private final class MediaUploadCancellationURLProtocol: URLProtocol {
    static let scopeHeader = "X-Merian-Upload-Cancellation-Test"
    private struct Signals: Sendable {
        let started: AsyncStream<Void>.Continuation
        let stopped: AsyncStream<Void>.Continuation
    }
    private static let signals = OSAllocatedUnfairLock(initialState: [String: Signals]())

    override static func canInit(with _: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let signal = currentSignals else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        signal.started.yield(())
        signal.started.finish()
        // Do not synthesize a response or error: URLSession cancellation must stop us.
    }

    override func stopLoading() {
        currentSignals?.stopped.yield(())
        currentSignals?.stopped.finish()
    }

    private var currentSignals: Signals? {
        guard let scopeID = request.value(forHTTPHeaderField: Self.scopeHeader) else { return nil }
        return Self.signals.withLock { $0[scopeID] }
    }

    static func register(
        scopeID: String,
        started: AsyncStream<Void>.Continuation,
        stopped: AsyncStream<Void>.Continuation
    ) {
        signals.withLock { $0[scopeID] = Signals(started: started, stopped: stopped) }
    }

    static func remove(scopeID: String) {
        let removed = signals.withLock { $0.removeValue(forKey: scopeID) }
        removed?.started.finish()
        removed?.stopped.finish()
    }
}
