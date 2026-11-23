import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite("Capture invocation lifetime", .serialized, .sharedProcessState(.offlineQueueManager))
struct SharedMediaNativeCaptureScopeTests {
    typealias Store = SharedMediaCaptureArtifactWriterTests.Store

    @Test(arguments: [false, true])
    func escapedEndpointsRejectAfterReturnAndThrow(throwing: Bool) async throws {
        let store = try await Store(), owner = try await store.open()
        try await owner.resumeAppCaptureRoot()
        var escaped: SharedMediaNativeAppCaptureOperations?
        do {
            try await owner.captureRootWorkflow { operations in
                escaped = operations
                if throwing { throw SharedMediaStorageFailure.unavailable }
            }
            #expect(!throwing)
        } catch { #expect(throwing) }
        let old = try #require(escaped)
        await #expect(throws: (any Error).self) { _ = try await old.captureDraftJournalPage(after: nil) }
        // Another operation on the same account must not revive the old borrow.
        try await owner.captureRootWorkflow { operations in
            await #expect(throws: (any Error).self) { _ = try await old.captureDraftJournalPage(after: nil) }
            _ = try await operations.captureDraftJournalPage(after: nil)
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let replacement = try await store.open()
        try await replacement.resumeAppCaptureRoot()
        await #expect(throws: (any Error).self) { _ = try await old.captureDraftJournalPage(after: nil) }
        #expect(await replacement.invalidateAndAwaitForAccountTransition())
    }

    @Test func delayedEndpointCannotEnterAfterCallbackExit() async throws {
        let store = try await Store(), owner = try await store.open(), gate = Gate()
        try await owner.resumeAppCaptureRoot()
        var delayed: Task<Void, Never>?
        try await owner.captureRootWorkflow { operations in
            delayed = Task { @MainActor in
                await gate.pause()
                await #expect(throws: SharedMediaStorageFailure.closed) {
                    _ = try await operations.captureDraftJournalPage(after: nil)
                }
            }
            #expect(await gate.entered())
        }
        await gate.release()
        await delayed?.value
        try await owner.captureRootWorkflow { _ = try await $0.captureDraftJournalPage(after: nil) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["return", "throw", "cancel", "account"])
    func callbackExitJoinsEnteredWriterBeforeReleasingNamespace(exit: String) async throws {
        let store = try await Store(byteCount: 131_072), owner = try await store.open(), gate = Gate()
        try await owner.resumeAppCaptureRoot()
        try owner.configureCaptureArtifactWritingForTesting(pause: { _ in await gate.pause() })
        var write: Task<SharedMediaCaptureArtifactLedger.Snapshot, any Error>?
        var callbackReturning = false, invocationExited = false
        let invocation = Task { @MainActor in
            defer { invocationExited = true; callbackReturning = true }
            try await owner.captureRootWorkflow { operations in
                write = Task { @MainActor in
                    do {
                        let result = try await operations.materializeAppCaptureArtifact(store.input, bytes: store.bytes)
                        await gate.finish(); return result
                    } catch { await gate.finish(); throw error }
                }
                guard await gate.entered() else {
                    _ = try await write?.value
                    Issue.record("Writer did not suspend"); callbackReturning = true; return
                }
                await #expect(throws: SharedMediaStorageFailure.busy) {
                    _ = try await operations.captureDraftJournalPage(after: nil)
                }
                callbackReturning = true
                if exit == "throw" { throw SharedMediaStorageFailure.unavailable }
            }
        }
        while !callbackReturning { await Task.yield() }
        #expect(!invocationExited)
        let initial = try SharedMediaCaptureArtifactLedger.receipt(#require(try store.rows().first))
        let partial = store.directory.appendingPathComponent(initial.request.partialName)
        #expect(initial.phase == .writing)
        #expect(try Data(contentsOf: partial).count == 65_536)
        var drained = false
        let drain: Task<Bool, Never>?
        if exit == "account" {
            drain = Task { @MainActor in
                let result = await owner.invalidateAndAwaitForAccountTransition(); drained = true; return result
            }
        } else { drain = nil; if exit == "cancel" { invocation.cancel() } }
        await Task.yield()
        #expect(!drained && !invocationExited)
        await gate.release()
        await #expect(throws: (any Error).self) { _ = try await write?.value }
        if exit == "return" { try await invocation.value } else {
            await #expect(throws: (any Error).self) { try await invocation.value }
        }
        if let drain { #expect(await drain.value) } else { #expect(await owner.invalidateAndAwaitForAccountTransition()) }
        let saved = try SharedMediaCaptureArtifactLedger.receipt(#require(try store.rows().first))
        #expect(saved.phase == .writing && saved.stage?.partialIdentity == initial.stage?.partialIdentity)
        #expect(try Data(contentsOf: partial).count == 65_536)
        let cold = try await store.open()
        let recovered = try await cold.materializeAppCaptureArtifact(store.input, bytes: store.bytes)
        #expect(recovered.phase == .ready && recovered.stage?.partialIdentity == initial.stage?.partialIdentity)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    private actor Gate {
        var arrived = false, finished = false, released = false
        var arrival: CheckedContinuation<Bool, Never>?, waiting: CheckedContinuation<Void, Never>?
        func pause() async {
            guard !released else { return }
            arrived = true; arrival?.resume(returning: true); arrival = nil
            await withCheckedContinuation { waiting = $0 }
        }
        func entered() async -> Bool {
            if arrived { return true }; if finished { return false }
            return await withCheckedContinuation { arrival = $0 }
        }
        func finish() { finished = true; arrival?.resume(returning: arrived); arrival = nil }
        func release() { released = true; waiting?.resume(); waiting = nil }
    }

    @Test(arguments: ["cancel", "claim", "account"])
    func knownResponseSettlesThroughCancellationOnlyForOriginalClaim(change: String) async throws {
        let store = try await Store(), owner = try await store.open()
        let fixture = SharedMediaCaptureResultWriterTests()
        let plan = try await fixture.prepare(store, owner: owner)
        try await fixture.stage(plan, owner: owner)
        let pending = try #require(try await owner.captureExecutionRecoveryPage().candidates.first)
        let running = try await owner.beginAppCaptureExecution(pending, now: Date())
        let dispatched = try await owner.reserveAppCaptureDispatch(running)
        let mock = ScopedMockTransport(), client = MerianNetworkClient()
        let session = mock.makeSession()
        client.overridingSession = session; client.overridingAuthUserID = plan.ownerID
        defer { client.overridingSession = nil; session.invalidateAndCancel() }
        let completion = try JSONSerialization.jsonObject(with: fixture.response(plan))
        let reply = try JSONSerialization.data(withJSONObject: [
            "version": 1, "phase": "capture-completion", "owner_id": plan.ownerID.uuidString.lowercased(),
            "scan_id": plan.scanID.uuidString.lowercased(), "generation": plan.generation.uuidString.lowercased(),
            "status": "completed", "completion": completion
        ])
        mock.register(path: "/check-scan-status") { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!, reply)
        }
        mock.register(path: "/identify-multimodal") { _ in
            Issue.record("Recovery repeated primary inference")
            throw SharedMediaStorageFailure.closed
        }
        var currentAccount = true, received = false
        let account = InferenceCompletionAccountScope(ownerID: plan.ownerID, isCurrent: { currentAccount }, release: {})
        defer { account.finish() }
        try owner.configureCaptureExecutionForTesting {
            received = true
            if change == "account" { currentAccount = false }
            if change == "claim" {
                let context = ModelContext(store.container); context.autosaveEnabled = false
                let job = try #require(try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: plan.scanID.uuidString.lowercased())))
                let queue = try #require(try context.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
                job.attemptCount += 1; queue.queueAttemptCount = job.attemptCount
                try context.save()
            }
            withUnsafeCurrentTask { $0?.cancel() }
        }
        // The caller remains cancelled; the joined known-answer settlement is
        // independently observable in durable rows after that caller exits.
        await #expect(throws: (any Error).self) {
            _ = try await owner.executeAppCapture(dispatched, network: client, account: account)
        }
        #expect(received)
        let read = ModelContext(store.container); read.autosaveEnabled = false
        #expect(try read.fetchCount(FetchDescriptor<LocalScanRecord>()) == (change == "cancel" ? 1 : 0))
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func repositoryIsTheOnlyProductionInvocationFactory() throws {
        let files = try DatabaseActorTestSupport.swiftSources(below: "apps/ios/Merian")
        let callers = files.filter { $0.contents.contains("SharedMediaNativeAppCaptureOperations.withValidatedFiles(") }
        #expect(callers.map(\.relativePath) == ["Core/Data/SharedMediaStorage/SharedMediaNativeStorageRepository.swift"])
        let repository = try DatabaseActorTestSupport.loadRepositorySource(at:
            "apps/ios/Merian/Core/Data/SharedMediaStorage/SharedMediaNativeStorageRepository.swift")
        #expect(repository.contains("defer { active = false }"))
        #expect(repository.contains("guard active else { throw SharedMediaStorageFailure.closed }"))
    }
}
