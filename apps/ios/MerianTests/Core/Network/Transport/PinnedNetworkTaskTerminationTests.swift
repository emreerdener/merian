import CryptoKit
import Foundation
import os
import Security
import Testing

@testable import Merian

@Suite("Pinned network local task termination", .serialized)
struct PinnedNetworkTaskTerminationTests {
    @Test(arguments: [false, true])
    func callerCompletionDoesNotReleaseTaskLifetime(timeout: Bool) async throws {
        let pause = CompletionPause()
        let state = PinnedNetworkDataTaskState(completionPause: { pause.wait() })
        let session = hangingSession()
        defer { pause.release(); session.invalidateAndCancel() }
        let call = Task {
            try await state.response(using: session, for: request(), timeoutInterval: timeout ? 0.05 : 10)
        }
        if !timeout {
            try await waitUntil { await sessionHasTask(session) }
            call.cancel()
        }
        let start = ContinuousClock.now
        switch await call.result {
        case .success: Issue.record("A hanging request unexpectedly succeeded")
        case .failure(let error):
            if timeout { #expect((error as? URLError)?.code == .timedOut) } else { #expect(error is CancellationError) }
        }
        #expect(start.duration(to: .now) < .seconds(1))
        try await waitUntil { pause.entered }
        await #expect(throws: (any Error).self) {
            try await state.response(using: session, for: request(), timeoutInterval: 0)
        }
        let joined = OSAllocatedUnfairLock(initialState: 0)
        let joins = (0..<3).map { _ in Task {
            await state.waitForLocalTermination()
            joined.withLock { $0 += 1 }
        } }
        // Account shutdown may already be cancelled. It must still join local
        // termination; cancellation cannot manufacture a drain acknowledgement.
        joins[0].cancel()
        try await Task.sleep(for: .milliseconds(30))
        #expect(joined.withLock { $0 } == 0)
        pause.release()
        for join in joins { await join.value }
        #expect(joined.withLock { $0 } == 3)
        await state.waitForLocalTermination() // Late joins are also idempotent.
    }

    @Test func transportRetainsStateAfterCancelledCallerDropsIt() async throws {
        let pause = CompletionPause()
        var state: PinnedNetworkDataTaskState? = .init(completionPause: { pause.wait() })
        weak let weakState = state
        let session = hangingSession()
        defer { pause.release(); session.invalidateAndCancel() }
        let call = Task { [state = state!] in
            try await state.response(using: session, for: request(), timeoutInterval: 0.03)
        }
        _ = await call.result
        try await waitUntil { pause.entered }
        state = nil
        #expect(weakState != nil)
        pause.release()
        // Completion breaks the state/task cycle even when nobody joins it.
        try await waitUntil { weakState == nil }
    }

    @Test(arguments: [false, true])
    func noTaskCanTerminateWithoutCallback(cancelled: Bool) async throws {
        let gate = StartGate()
        let state = PinnedNetworkDataTaskState()
        let session = hangingSession()
        defer { session.invalidateAndCancel() }
        let call = Task {
            await gate.wait()
            return try await state.response(using: session, for: request(), timeoutInterval: cancelled ? 1 : 0)
        }
        if cancelled { call.cancel() }
        await gate.open()
        if case .success = await call.result { Issue.record("Rejected start succeeded") }
        await state.waitForLocalTermination()
        let tasks = await session.allTasks
        #expect(tasks.isEmpty)
    }

    @Test func successAndDuplicateResponseKeepOneTaskLifetime() async throws {
        let mock = ScopedMockTransport(), state = PinnedNetworkDataTaskState()
        let session = mock.makeSession()
        defer { session.invalidateAndCancel() }
        mock.register(path: "/local-termination") { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data([7]))
        }
        let result = try await state.response(using: session, for: request(), timeoutInterval: 1)
        #expect(result.data == Data([7]))
        await state.waitForLocalTermination()
        await #expect(throws: (any Error).self) {
            try await state.response(using: session, for: request(), timeoutInterval: 1)
        }
        await state.waitForLocalTermination()
    }

    @Test(arguments: [false, true])
    func boundedCallerCompletionStillRequiresActualTermination(timeout: Bool) async throws {
        let pause = CompletionPause(), session = hangingSession()
        let collector = PinnedBoundedJSONDataTask(maximumBytes: 8192, completionPause: { pause.wait() })
        defer { pause.release(); session.invalidateAndCancel() }
        let call = Task { try await collector.response(using: session, request: request(), timeout: timeout ? 0.1 : 10) }
        if !timeout {
            try await waitUntil { await sessionHasTask(session) }
            call.cancel()
        }
        if case .success = await call.result { Issue.record("Hanging collection succeeded") }
        try await waitUntil { pause.entered }
        let joined = OSAllocatedUnfairLock(initialState: false)
        let join = Task { await collector.waitForLocalTermination(); joined.withLock { $0 = true } }
        join.cancel()
        try await Task.sleep(for: .milliseconds(30))
        #expect(!joined.withLock { $0 })
        pause.release(); await join.value
        #expect(joined.withLock { $0 })
        await collector.waitForLocalTermination()
    }

    @Test(arguments: [false, true], [InitialPhotoAllocationReply.maximumBytes, InitialPhotoUploadTicket.maximumBytes])
    func joinedBoundedResponseWithholdsCancellationAndTimeoutUntilDrain(timeout: Bool, maximumBytes: Int) async throws {
        let pause = CompletionPause(), session = hangingSession()
        let collector = PinnedBoundedJSONDataTask(maximumBytes: maximumBytes, completionPause: { pause.wait() })
        let returned = OSAllocatedUnfairLock(initialState: false)
        defer { pause.release(); session.invalidateAndCancel() }
        let call = Task {
            defer { returned.withLock { $0 = true } }
            return try await collector.joinedResponse(using: session, request: request(), timeout: timeout ? 0.1 : 10)
        }
        if !timeout {
            try await waitUntil { await sessionHasTask(session) }
            call.cancel()
        }
        try await waitUntil { pause.entered }
        #expect(!returned.withLock { $0 })
        pause.release()
        switch await call.result {
        case .success: Issue.record("Hanging collection succeeded")
        case .failure(let error):
            if timeout { #expect((error as? URLError)?.code == .timedOut) } else { #expect(error is CancellationError) }
        }
        #expect(returned.withLock { $0 })
    }

    @Test func boundedCollectorRemainsAliveUntilCallbackAfterCallerDropsIt() async throws {
        let pause = CompletionPause(), session = hangingSession()
        var collector: PinnedBoundedJSONDataTask? = .init(maximumBytes: 8192, completionPause: { pause.wait() })
        weak let retained = collector
        defer { pause.release(); session.invalidateAndCancel() }
        let call = Task { [collector = collector!] in
            try await collector.response(using: session, request: request(), timeout: 0.1)
        }
        _ = await call.result
        try await waitUntil { pause.entered }
        collector = nil
        #expect(retained != nil)
        pause.release()
        try await waitUntil { retained == nil }
    }

    @Test(arguments: ["cancel", "timeout", "beforeStart"])
    func boundedRejectedStartDrainsWithoutInventingTask(reason: String) async throws {
        let gate = StartGate(), session = hangingSession(), collector = PinnedBoundedJSONDataTask(maximumBytes: 8192)
        defer { session.invalidateAndCancel() }
        let call = Task {
            await gate.wait()
            return try await collector.response(using: session, request: request(), timeout: reason == "timeout" ? 0 : 1,
                beforeStart: { if reason == "beforeStart" { throw URLError(.badURL) } })
        }
        if reason == "cancel" { call.cancel() }
        await gate.open()
        if case .success = await call.result { Issue.record("Rejected start succeeded") }
        await collector.waitForLocalTermination()
        #expect(await session.allTasks.isEmpty)
    }

    @Test func boundedDeadlineIncludesResumeGapAndStillDrains() async throws {
        let mock = ScopedMockTransport(), session = mock.makeSession(), pause = CompletionPause()
        let collector = PinnedBoundedJSONDataTask(maximumBytes: 8192,
            completionPause: { pause.wait() }, beforeResume: { Thread.sleep(forTimeInterval: 0.2) })
        let calls = OSAllocatedUnfairLock(initialState: 0), returned = OSAllocatedUnfairLock(initialState: false)
        defer { pause.release(); session.invalidateAndCancel() }
        mock.register(path: "/local-termination") { request in
            calls.withLock { $0 += 1 }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!, Data())
        }
        let call = Task {
            defer { returned.withLock { $0 = true } }
            return try await collector.joinedResponse(using: session, request: request(), timeout: 0.05)
        }
        try await waitUntil { pause.entered }
        #expect(!returned.withLock { $0 } && calls.withLock { $0 } == 0)
        pause.release()
        if case .success = await call.result { Issue.record("Expired request resumed") }
        #expect(calls.withLock { $0 } == 0)
    }

    @Test(arguments: ["auth", "redirect", "mime", "overflow"])
    func boundedProtocolRejectionCannotAcknowledgeDrain(reason: String) async throws {
        let pause = CompletionPause(), session = hangingSession()
        let collector = PinnedBoundedJSONDataTask(maximumBytes: 8, completionPause: { pause.wait() })
        defer { pause.release(); session.invalidateAndCancel() }
        let call = Task { try await collector.response(using: session, request: request(), timeout: 10) }
        try await waitUntil { await sessionHasTask(session) }
        let task = try #require(await session.allTasks.first as? URLSessionDataTask)
        if reason == "auth" {
            let space = URLProtectionSpace(host: "example.supabase.co", port: 443, protocol: "https", realm: nil,
                authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
            let challenge = URLAuthenticationChallenge(protectionSpace: space, proposedCredential: nil, previousFailureCount: 0,
                failureResponse: nil, error: nil, sender: UploadChallengeSender())
            collector.urlSession(session, task: task, didReceive: challenge) { disposition, credential in
                #expect(disposition == .cancelAuthenticationChallenge && credential == nil)
            }
        } else if reason == "redirect" {
            collector.urlSession(session, task: task,
                willPerformHTTPRedirection: HTTPURLResponse(url: request().url!, statusCode: 302, httpVersion: nil, headerFields: nil)!,
                newRequest: request()) { #expect($0 == nil) }
        } else if reason == "mime" {
            collector.urlSession(session, dataTask: task,
                didReceive: HTTPURLResponse(url: request().url!, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "text/plain"])!) { #expect($0 == .cancel) }
        } else {
            collector.urlSession(session, dataTask: task, didReceive: Data(repeating: 1, count: 9))
        }
        if case .success = await call.result { Issue.record("Rejected protocol succeeded") }
        try await waitUntil { pause.entered }
        let done = OSAllocatedUnfairLock(initialState: false)
        let join = Task { await collector.waitForLocalTermination(); done.withLock { $0 = true } }
        join.cancel()
        try await Task.sleep(for: .milliseconds(30))
        #expect(!done.withLock { $0 })
        pause.release(); await join.value
        #expect(done.withLock { $0 })
    }

    private func request() -> URLRequest {
        URLRequest(url: URL(string: "https://example.supabase.co/local-termination")!)
    }
    private func hangingSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TerminationHangingProtocol.self]
        return URLSession(configuration: configuration)
    }
    private func sessionHasTask(_ session: URLSession) async -> Bool { !(await session.allTasks).isEmpty }
    private func waitUntil(_ predicate: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !(await predicate()) {
            guard ContinuousClock.now < deadline else {
                Issue.record("Termination boundary did not arrive")
                throw URLError(.timedOut)
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private final class CompletionPause: Sendable {
    private let reached = OSAllocatedUnfairLock(initialState: false)
    private let semaphore = DispatchSemaphore(value: 0)
    var entered: Bool { reached.withLock { $0 } }
    func wait() {
        reached.withLock { $0 = true }
        // Bound a failed test without manufacturing a production drain timeout.
        _ = semaphore.wait(timeout: .now() + 5)
    }
    func release() { semaphore.signal() }
}
private actor StartGate {
    private var isOpen = false
    private var waiter: CheckedContinuation<Void, Never>?
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func open() { isOpen = true; waiter?.resume(); waiter = nil }
}
private final class TerminationHangingProtocol: URLProtocol {
    override static func canInit(with _: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
}

@Suite("Pinned photo upload local task termination", .serialized)
struct PinnedPhotoUploadTaskTests {
    private func request() -> URLRequest {
        var request = URLRequest(url: URL(string: "https://example.supabase.co/photo-upload")!)
        request.httpMethod = "PUT"
        return request
    }
    private func file() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1, 2, 3]).write(to: url)
        return url
    }
    /// Drive the actual foreground file task and consume its supplied stream.
    /// Success and halfway cancellation retain a separate observed resource trace.
    @Test(arguments: [false, true])
    @MainActor func maximumOriginalStreamResources(cancelHalfway: Bool) async throws {
        let size = Int(PhotoPreparationPolicy.original)
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: source, options: .withoutOverwriting)
        defer { try? FileManager.default.removeItem(at: source) }
        let expected = try Self.writeSyntheticOriginal(source, size: size)
        let wire = ScopedMockTransport(), session = wire.makeSession()
        defer { session.invalidateAndCancel() }
        let baseline = try PhotoUploadResourceSample(original: source)
        let samples = OSAllocatedUnfairLock(initialState: [String: [Int64]]())
        let takeSample: @Sendable (String) throws -> Void = { phase in
            let sample = try PhotoUploadResourceSample(original: source)
            samples.withLock {
                $0[phase] = [sample.additionalOpenFileBytes(since: baseline), Int64(sample.footprint), sample.lifetimePeak, sample.originalOpen ? 1 : 0]
            }
        }
        let call = OSAllocatedUnfairLock(initialState: Optional<Task<HTTPURLResponse, Error>>.none)
        let received = OSAllocatedUnfairLock(initialState: (count: 0, digest: Data(), calls: 0))
        wire.register(path: "/photo-upload") { outgoing in
            let stream = try #require(outgoing.httpBodyStream)
            stream.open()
            defer { stream.close() }
            var chunk = [UInt8](repeating: 0, count: 65536), hash = SHA256(), total = 0
            var nextSample = size / 4
            try takeSample("streamOpened")
            while true {
                let limit = nextSample > total ? min(chunk.count, nextSample - total) : chunk.count
                let n = stream.read(&chunk, maxLength: limit)
                guard n >= 0, n <= size - total else { throw URLError(.cannotDecodeContentData) }
                if n == 0 { break }
                chunk.withUnsafeBytes { hash.update(bufferPointer: UnsafeRawBufferPointer(rebasing: $0[..<n])) }
                total += n
                if total >= nextSample {
                    try takeSample("streamQuarter" + String(nextSample / (size / 4)))
                    nextSample += size / 4
                    if cancelHalfway && total >= size / 2 {
                        let running = try #require(call.withLock { $0 })
                        running.cancel()
                        break
                    }
                }
            }
            let receivedBytes = total, receivedDigest = Data(hash.finalize())
            received.withLock { $0 = (receivedBytes, receivedDigest, $0.calls + 1) }
            let url = try #require(outgoing.url)
            return (try #require(HTTPURLResponse(url: url, statusCode: 201, httpVersion: nil, headerFields: nil)), Data())
        }
        let transport = PinnedNetworkTransport()
        transport.overridingSession = session
        let task = transport.measuredPhotoUploadTask {
            do { try takeSample("beforeResume") } catch { Issue.record("Could not sample the suspended upload") }
        }
        let request = request()
        let runner = Task { try await task.response(for: request, fromFile: source, timeout: 60) }
        call.withLock { $0 = runner }
        switch await runner.result {
        case .success(let reply): #expect(!cancelHalfway && reply.statusCode == 201)
        case .failure(let error): #expect(cancelHalfway && error is CancellationError)
        }
        await task.waitForLocalTermination()
        #expect(task.acknowledgedOwnedSessionEnd && task.hasPurgedMeasuredTransfer)
        call.withLock { $0 = nil }
        try await waitUntil { received.withLock { $0.calls } > 0 }
        try takeSample("drained")
        let facts = received.withLock { $0 }
        #expect(facts.calls == 1 && facts.count == (cancelHalfway ? size / 2 : size))
        if !cancelHalfway { #expect(facts.digest == expected) }
        #expect(await session.allTasks.isEmpty)
        let measured = samples.withLock { $0 }
        #expect(measured.count == (cancelHalfway ? 5 : 7))
        let json = try JSONEncoder().encode(measured)
        print("PHOTO_UPLOAD_RESOURCE_SAMPLE cancelled=\(cancelHalfway) bytes=\(facts.count) baselineFootprint=\(baseline.footprint) baselinePeak=\(baseline.lifetimePeak) samples=\(String(decoding: json, as: UTF8.self))")
    }

    private static func writeSyntheticOriginal(_ url: URL, size: Int) throws -> Data {
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        let chunkSize = 65536
        var hash = SHA256(), written = 0
        while written < size {
            var chunk = Data(count: min(chunkSize, size - written))
            let status = chunk.withUnsafeMutableBytes { buffer in
                guard let address = buffer.baseAddress else { return errSecParam }
                return SecRandomCopyBytes(kSecRandomDefault, buffer.count, address)
            }
            guard status == errSecSuccess else { throw CocoaError(.fileWriteUnknown) }
            try file.write(contentsOf: chunk)
            hash.update(data: chunk)
            written += chunk.count
        }
        try file.synchronize()
        return Data(hash.finalize())
    }
    private func hangingSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TerminationHangingProtocol.self]
        return URLSession(configuration: config)
    }
    private func waitUntil(_ predicate: () async -> Bool) async throws {
        let end = ContinuousClock.now + .seconds(3)
        while !(await predicate()) {
            guard ContinuousClock.now < end else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test(arguments: [false, true])
    func cancelledOrTimedOutFilePUTStillRequiresCompletion(timeout: Bool) async throws {
        let pause = CompletionPause(), session = hangingSession(), file = try file()
        let state = PinnedPhotoUploadTask(session: session, completionPause: { pause.wait() })
        defer { pause.release(); session.invalidateAndCancel(); try? FileManager.default.removeItem(at: file) }
        let call = Task { try await state.response(for: request(), fromFile: file, timeout: timeout ? 0.2 : 10) }
        try await waitUntil { !(await session.allTasks).isEmpty }
        let tasks = await session.allTasks
        #expect(tasks.count == 1 && tasks.first is URLSessionUploadTask)
        if !timeout { call.cancel() }
        let start = ContinuousClock.now
        switch await call.result {
        case .success: Issue.record("Hanging upload succeeded")
        case .failure(let error):
            if timeout { #expect((error as? URLError)?.code == .timedOut) } else { #expect(error is CancellationError) }
        }
        #expect(start.duration(to: .now) < .seconds(1))
        try await waitUntil { pause.entered }
        await #expect(throws: (any Error).self) {
            try await state.response(for: request(), fromFile: file, timeout: 1)
        }
        let joined = OSAllocatedUnfairLock(initialState: 0)
        let joins = (0..<3).map { _ in Task {
            await state.waitForLocalTermination(); joined.withLock { $0 += 1 }
        } }
        joins[0].cancel()
        try await Task.sleep(for: .milliseconds(30))
        #expect(joined.withLock { $0 } == 0)
        #expect(try Data(contentsOf: file) == Data([1, 2, 3]))
        pause.release()
        for join in joins { await join.value }
        #expect(joined.withLock { $0 } == 3)
        await state.waitForLocalTermination()
    }

    @Test(arguments: ["cancel", "timeout", "ceiling", "remoteFile", "body", "method", "expired"])
    func rejectedStartCreatesNoTask(reason: String) async throws {
        let session = hangingSession()
        let upload = PinnedPhotoUploadTask(session: session), file = try file(), gate = StartGate()
        defer { session.invalidateAndCancel(); try? FileManager.default.removeItem(at: file) }
        var input = request()
        if reason == "body" { input.httpBody = Data([9]) }
        if reason == "method" { input.httpMethod = "POST" }
        let captured = input
        let call = Task {
            await gate.wait()
            return try await upload.response(for: captured,
                fromFile: reason == "remoteFile" ? URL(string: "https://example.invalid/file")! : file,
                timeout: reason == "timeout" ? 0 : reason == "ceiling" ? 301 : 1,
                expiresAtMilliseconds: reason == "expired" ? 0 : nil)
        }
        if reason == "cancel" { call.cancel() }
        await gate.open()
        switch await call.result {
        case .success: Issue.record("Rejected upload started")
        case .failure(let error):
            if reason == "expired" { #expect((error as? URLError)?.code == .timedOut) }
        }
        await upload.waitForLocalTermination()
        #expect(await session.allTasks.isEmpty)
    }

    @Test(arguments: [200, 201, 500])
    func actualUploadReturnsStatusWithoutInferringRemoteClosure(status: Int) async throws {
        let mock = ScopedMockTransport(), session = mock.makeSession(), file = try file()
        let transport = PinnedNetworkTransport(); transport.overridingSession = session
        let upload = transport.photoUploadTask()
        defer { session.invalidateAndCancel(); try? FileManager.default.removeItem(at: file) }
        mock.register(path: "/photo-upload") { request in
            #expect(request.httpMethod == "PUT")
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data([7]))
        }
        let response = try await upload.response(for: request(), fromFile: file, timeout: 1)
        #expect(response.statusCode == status)
        await upload.waitForLocalTermination()
        await #expect(throws: (any Error).self) { try await upload.response(for: request(), fromFile: file, timeout: 1) }
        await upload.waitForLocalTermination()
    }

    @Test(arguments: [false, true])
    func responseOverflowIsRejectedBeforeDrain(advertised: Bool) async throws {
        let mock = ScopedMockTransport(), session = mock.makeSession(), file = try file(), pause = CompletionPause()
        let upload = PinnedPhotoUploadTask(session: session, completionPause: { pause.wait() })
        defer { pause.release(); session.invalidateAndCancel(); try? FileManager.default.removeItem(at: file) }
        mock.register(path: "/photo-upload") { request in
            (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil,
                headerFields: advertised ? ["Content-Length": "4097"] : nil)!, Data(repeating: 1, count: 4097))
        }
        await #expect(throws: (any Error).self) { try await upload.response(for: request(), fromFile: file, timeout: 1) }
        try await waitUntil { pause.entered }
        let joined = OSAllocatedUnfairLock(initialState: false)
        let join = Task { await upload.waitForLocalTermination(); joined.withLock { $0 = true } }
        try await Task.sleep(for: .milliseconds(30))
        #expect(!joined.withLock { $0 })
        pause.release(); await join.value
        #expect(joined.withLock { $0 })
    }

    @Test func redirectCannotResendFileAndStillJoinsCompletion() async throws {
        let session = hangingSession(), file = try file(), pause = CompletionPause()
        let upload = PinnedPhotoUploadTask(session: session, completionPause: { pause.wait() })
        defer { pause.release(); session.invalidateAndCancel(); try? FileManager.default.removeItem(at: file) }
        let call = Task { try await upload.response(for: request(), fromFile: file, timeout: 10) }
        try await waitUntil { !(await session.allTasks).isEmpty }
        let task = try #require(await session.allTasks.first)
        let response = HTTPURLResponse(url: request().url!, statusCode: 307, httpVersion: nil, headerFields: nil)!
        upload.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request()) { redirected in
            #expect(redirected == nil)
        }
        if case .success = await call.result { Issue.record("Redirect accepted") }
        try await waitUntil { pause.entered }
        pause.release(); await upload.waitForLocalTermination()
    }

    @Test(arguments: [NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest,
                      NSURLAuthenticationMethodClientCertificate])
    func nonTLSChallengeRejectsCredentialsButStillWaitsForCompletion(method: String) async throws {
        let session = hangingSession(), file = try file(), pause = CompletionPause()
        let upload = PinnedPhotoUploadTask(session: session, completionPause: { pause.wait() })
        defer { pause.release(); session.invalidateAndCancel(); try? FileManager.default.removeItem(at: file) }
        let call = Task { try await upload.response(for: request(), fromFile: file, timeout: 10) }
        try await waitUntil { !(await session.allTasks).isEmpty }
        let task = try #require(await session.allTasks.first)
        upload.urlSession(session, task: task, didReceive: challenge(method)) { disposition, credential in
            #expect(disposition == .cancelAuthenticationChallenge && credential == nil)
        }
        switch await call.result {
        case .success: Issue.record("Credential challenge accepted")
        case .failure(let error): #expect((error as? URLError)?.code == .userAuthenticationRequired)
        }
        try await waitUntil { pause.entered }
        let done = OSAllocatedUnfairLock(initialState: false)
        let join = Task { await upload.waitForLocalTermination(); done.withLock { $0 = true } }
        join.cancel()
        try await Task.sleep(for: .milliseconds(30)); #expect(!done.withLock { $0 })
        pause.release(); await join.value; #expect(done.withLock { $0 })
    }

    @Test func serverTrustUsesExistingDebugTLSPolicy() async throws {
        let session = hangingSession(), file = try file()
        let state = PinnedPhotoUploadTask(session: session)
        defer { session.invalidateAndCancel(); try? FileManager.default.removeItem(at: file) }
        let call = Task { try await state.response(for: request(), fromFile: file, timeout: 10) }
        try await waitUntil { !(await session.allTasks).isEmpty }
        let task = try #require(await session.allTasks.first)
        state.urlSession(session, task: task, didReceive: challenge(NSURLAuthenticationMethodServerTrust)) { disposition, credential in
            #expect(disposition == .performDefaultHandling && credential == nil)
        }
        call.cancel(); _ = await call.result; await state.waitForLocalTermination()
    }

    private func challenge(_ method: String) -> URLAuthenticationChallenge {
        let space = URLProtectionSpace(host: "example.supabase.co", port: 443, protocol: "https", realm: nil,
            authenticationMethod: method)
        return URLAuthenticationChallenge(protectionSpace: space, proposedCredential: nil, previousFailureCount: 0,
            failureResponse: nil, error: nil, sender: UploadChallengeSender())
    }

    @Test func taskRetainsOwnerUntilCallbackAfterCallerDropsHandle() async throws {
        let session = hangingSession(), file = try file(), pause = CompletionPause()
        var upload: PinnedPhotoUploadTask? = .init(session: session, completionPause: { pause.wait() })
        weak let weakUpload = upload
        defer { pause.release(); session.invalidateAndCancel(); try? FileManager.default.removeItem(at: file) }
        let call = Task { [upload = upload!] in try await upload.response(for: request(), fromFile: file, timeout: 0.03) }
        _ = await call.result
        try await waitUntil { pause.entered }
        upload = nil; #expect(weakUpload != nil)
        pause.release()
        try await waitUntil { weakUpload == nil }
    }
}

private final class UploadChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
}
