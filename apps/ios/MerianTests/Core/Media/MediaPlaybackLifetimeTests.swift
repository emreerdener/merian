import Foundation
@testable import Merian
import Testing

@Suite("Media preview actual-reader lifetime", .serialized)
@MainActor
struct MediaPlaybackLifetimeTests {
    private final class Gate {
        var entered = false
        var waiter: CheckedContinuation<Void, Never>?
        func wait() async { entered = true; await withCheckedContinuation { waiter = $0 } }
        func release() { waiter?.resume(); waiter = nil }
    }

    @Test func retirementWaitsForCancellationIgnoringReaderAndLatePlayer() async throws {
        let lifetime = MediaPlaybackLifetime(), gate = Gate(), finishing = Gate()
        var playerPresent = false, removed = false, closed = false
        try lifetime.configure(stop: { playerPresent = false }, finish: {
            #expect(!playerPresent)
            await finishing.wait()
            removed = true
        })
        let reading = Task { await lifetime.run { await gate.wait(); playerPresent = true } }
        while !gate.entered { await Task.yield() }
        lifetime.seal()
        #expect(lifetime.isClosed && !removed)
        let close = Task { await lifetime.close(); closed = true }
        let concurrentClose = Task { await lifetime.close() }
        await lifetime.run { Issue.record("Closed preview admitted another reader") }
        #expect(throws: (any Error).self) { try lifetime.configure(stop: {}) }
        gate.release()
        while !finishing.entered { await Task.yield() }
        #expect(!removed && !closed && !playerPresent)
        finishing.release()
        await close.value; await concurrentClose.value; await reading.value
        #expect(removed && closed)
    }

    @Test func presentationDisposalJoinsMountedPreviewBeforeAcknowledgement() async throws {
        let resources = CaptureDraftPresentationResources(), lifetime = MediaPlaybackLifetime(), gate = Gate()
        var finished = false
        try lifetime.configure(stop: {})
        try resources.retainPlayback(lifetime)
        let reading = Task { await lifetime.run { await gate.wait() } }
        while !gate.entered { await Task.yield() }
        let discard = Task { let result = await resources.discard(); finished = true; return result }
        while !lifetime.isClosed { await Task.yield() }
        #expect(!finished)
        #expect(throws: (any Error).self) { try resources.retainPlayback(MediaPlaybackLifetime()) }
        gate.release()
        #expect(await discard.value)
        await reading.value
    }

    @Test func presentationWaitsForEditorDecodeAndRejectsLateDelivery() async throws {
        let resources = CaptureDraftPresentationResources(), gate = Gate()
        var finished = false, delivered = false
        let reading = Task {
            do { _ = try await resources.read { await gate.wait(); return 1 }; delivered = true } catch {}
        }
        while !gate.entered { await Task.yield() }
        let discard = Task { let result = await resources.discard(); finished = true; return result }
        // A second read observes the closing fence; it cannot reach its body.
        for _ in 0..<20 { await Task.yield() }
        #expect(!finished)
        await #expect(throws: (any Error).self) { try await resources.read { Issue.record("Closing resources admitted read") } }
        gate.release()
        #expect(await discard.value)
        await reading.value
        #expect(!delivered)
    }

    @Test func sealingBeforeConfigurationPreventsFirstRead() async {
        let lifetime = MediaPlaybackLifetime()
        lifetime.seal()
        #expect(throws: (any Error).self) { try lifetime.configure(stop: {}) }
        await lifetime.run { Issue.record("Unmounted page began loading") }
        await lifetime.close()
    }

    @Test(arguments: [false, true])
    func reusablePresentationJoinsOldAudioAndBoostBeforeReappearing(boost: Bool) async throws {
        let presentation = MediaPlaybackPresentationLifetime(), reader = Gate(), boostReader = Gate(), finish = Gate()
        let first = try await presentation.prepare()
        var oldPlayer = false, newPlayer = false, reopened = false
        try first.configure(stop: { oldPlayer = false }, finish: { await finish.wait() })
        let work = Task { await first.run { await reader.wait(); oldPlayer = true } }
        while !reader.entered { await Task.yield() }
        let boosting = Task {
            if boost { await first.run { await boostReader.wait(); oldPlayer = true } }
        }
        if boost { while !boostReader.entered { await Task.yield() } }
        presentation.retire()
        reader.release()
        if boost { boostReader.release() }
        await work.value
        await boosting.value
        while !finish.entered { await Task.yield() }
        let next = Task {
            let scope = try await presentation.prepare()
            try scope.configure(stop: { newPlayer = false })
            await scope.run { newPlayer = true; reopened = true }
            return scope
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(!reopened && !oldPlayer)
        finish.release()
        let second = try await next.value
        #expect(second !== first && first.isClosed && newPlayer)
        // A late callback on the old scope cannot mutate the new presentation.
        await first.run { newPlayer = false; Issue.record("Retired audio/boost admitted late work: \(boost)") }
        #expect(newPlayer)
        presentation.retire()
        await second.close()
        #expect(!newPlayer)
    }

    @Test func cancelledAppearanceCannotMintReplacementWhileCloseIsBlocked() async throws {
        let presentation = MediaPlaybackPresentationLifetime(), finishing = Gate()
        let original = try await presentation.prepare()
        try original.configure(stop: {}, finish: { await finishing.wait() })
        presentation.retire()
        while !finishing.entered { await Task.yield() }
        let appearing = Task { try await presentation.prepare() }
        appearing.cancel()
        finishing.release()
        await #expect(throws: CancellationError.self) { _ = try await appearing.value }
        #expect(presentation.current === original && original.isClosed)
        let replacement = try await presentation.prepare()
        #expect(replacement !== original && !replacement.isClosed)
        presentation.retire()
        await replacement.close()
    }
}
