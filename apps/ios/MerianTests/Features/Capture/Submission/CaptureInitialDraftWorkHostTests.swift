import Foundation
@testable import Merian
import Testing

@Suite("Capture draft actual-work lifetime", .serialized)
@MainActor
struct CaptureInitialDraftWorkHostTests {
    @Test func retryHandoffCannotAdoptAnotherItemsCompanion() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("producer-item-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([1, 2]).write(to: url)
        let resources = CaptureInitialProducerResources(), item = UUID()
        let file = CaptureScanTemporaryFileLease(fileURL: url)
        try resources.preserveBeforeRetirement(itemID: item) {}
        #expect(throws: (any Error).self) { try resources.retainForRecovery(file, itemID: UUID()) }
        #expect(FileManager.default.fileExists(atPath: url.path))
        try resources.retainForRecovery(file, itemID: item)
        #expect(await resources.discard())
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func failedRetryHandoffPreservesProducerUntilCompleteCopy() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("producer-handoff-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data([1, 2, 3, 4])
        try original.write(to: url)
        let resources = CaptureInitialProducerResources(), host = CaptureInitialDraftWorkHost()
        let file = CaptureScanTemporaryFileLease(fileURL: url)
        _ = try await host.runRetained(requireCurrent: {}, operation: { resources }, cleanup: { await resources.discard() })
        try resources.retain(file)
        var canCopy = false, retry: Data?
        try resources.preserveBeforeRetirement(itemID: UUID()) {
            guard canCopy else { throw SharedMediaStorageFailure.unavailable }
            retry = try await file.readOriginal(maximumBytes: 100)
        }
        #expect(await host.close() == false)
        #expect(retry == nil && FileManager.default.fileExists(atPath: url.path))
        canCopy = true
        #expect(await host.close())
        #expect(retry == original && !FileManager.default.fileExists(atPath: url.path))
    }

    @Test func producerCleanupRetainsReplacementLiability() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("producer-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([1]).write(to: url)
        let resources = CaptureInitialProducerResources(), host = CaptureInitialDraftWorkHost()
        let retained = try await host.runRetained(requireCurrent: {}, operation: { resources }, cleanup: { await resources.discard() })
        try resources.retain(CaptureScanTemporaryFileLease(fileURL: url))
        try Data([2, 3]).write(to: url, options: .atomic)
        #expect(await host.close() == false)
        #expect(!host.isQuiescent)
        #expect(try Data(contentsOf: url) == Data([2, 3]))
        #expect(throws: (any Error).self) { try retained.currentValue() }
        try FileManager.default.removeItem(at: url)
        #expect(await host.close())
        #expect(await retained.release())
    }

    @MainActor private final class Gate {
        var entered = false
        var continuation: CheckedContinuation<Void, Never>?
        func wait() async {
            entered = true
            await withCheckedContinuation { continuation = $0 }
        }
        func release() { continuation?.resume(); continuation = nil }
    }

    @Test func shutdownWaitsForLateSuccessAndDisposableCleanup() async throws {
        let host = CaptureInitialDraftWorkHost(), operation = Gate(), cleanup = Gate()
        var delivered = false, closeFinished = false, discarded: [Int] = []
        let work = Task { @MainActor in
            do {
                _ = try await host.run(requireCurrent: {}, operation: {
                    await operation.wait() // deliberately ignores cancellation
                    return 42
                }, discard: { value in
                    discarded.append(value)
                    await cleanup.wait()
                })
                delivered = true
            } catch {}
        }
        while !operation.entered { await Task.yield() }
        let closing = Task { @MainActor in
            let result = await host.close(); closeFinished = true; return result
        }
        while !host.isClosed { await Task.yield() }
        #expect(!host.isQuiescent && !closeFinished)
        await #expect(throws: (any Error).self) {
            try await host.run(requireCurrent: {}, operation: { Issue.record("Closed host admitted work") })
        }
        operation.release()
        while !cleanup.entered { await Task.yield() }
        #expect(!host.isQuiescent && !closeFinished && discarded == [42])
        cleanup.release()
        #expect(await closing.value)
        await work.value
        #expect(host.isQuiescent && !delivered && discarded == [42])
        #expect(await host.close())
    }

    @Test func staleAccountDiscardsResultAndOverlappingWorkIsDenied() async throws {
        let host = CaptureInitialDraftWorkHost(), gate = Gate()
        var current = true, cleaned = 0
        let task = Task { @MainActor in
            await #expect(throws: (any Error).self) {
                try await host.run(requireCurrent: {
                    guard current else { throw SharedMediaStorageFailure.closed }
                }, operation: { await gate.wait(); return 1 }, discard: { cleaned += $0 })
            }
        }
        while !gate.entered { await Task.yield() }
        await #expect(throws: (any Error).self) {
            try await host.run(requireCurrent: {}, operation: { Issue.record("Overlapping work admitted") })
        }
        current = false; gate.release(); await task.value
        #expect(cleaned == 1 && host.isQuiescent)
        #expect(await host.close())
    }

    @Test func idlePresentationBlocksDrainUntilCleanupFinishes() async throws {
        let host = CaptureInitialDraftWorkHost(), cleanup = Gate()
        var cleaned = 0, closed = false
        let lease = try await host.runRetained(requireCurrent: {}, operation: { 42 }, cleanup: {
            cleaned += 1; await cleanup.wait(); return true
        })
        #expect(try lease.currentValue() == 42 && !host.isQuiescent)
        let closing = Task { @MainActor in let result = await host.close(); closed = true; return result }
        while !cleanup.entered { await Task.yield() }
        #expect(!closed && !host.isQuiescent)
        #expect(throws: (any Error).self) { try lease.currentValue() }
        let release = Task { @MainActor in await lease.release() }
        cleanup.release()
        #expect(await closing.value)
        #expect(await release.value)
        #expect(await lease.release())
        #expect(cleaned == 1 && host.isQuiescent)
    }

    @Test func failedPartialCleanupRemainsRegisteredForRetry() async throws {
        let host = CaptureInitialDraftWorkHost()
        var allowed = false, cleanups = 0
        await #expect(throws: (any Error).self) {
            try await host.runRetained(requireCurrent: {}, operation: { () -> Int in
                throw SharedMediaStorageFailure.unavailable
            }, cleanup: { cleanups += 1; return allowed })
        }
        #expect(cleanups == 1 && !host.isQuiescent)
        #expect(await host.close() == false)
        #expect(cleanups == 2 && !host.isQuiescent)
        allowed = true
        #expect(await host.close())
        #expect(cleanups == 3 && host.isQuiescent)
    }

    @Test func explicitReleaseInvalidatesValueBeforeCleanupAndAfterFailure() async throws {
        let host = CaptureInitialDraftWorkHost(), cleanup = Gate()
        var allow = false
        let lease = try await host.runRetained(requireCurrent: {}, operation: { 1 }, cleanup: {
            if !allow { await cleanup.wait() }
            return allow
        })
        let release = Task { @MainActor in await lease.release() }
        while !cleanup.entered { await Task.yield() }
        #expect(!host.isClosed && !host.isQuiescent)
        #expect(throws: (any Error).self) { try lease.currentValue() }
        cleanup.release()
        #expect(await release.value == false)
        #expect(throws: (any Error).self) { try lease.currentValue() }
        allow = true
        #expect(await lease.release())
        #expect(host.isQuiescent)
    }

    @Test func oldLeaseCannotReleaseItsSuccessorAndStaleAccountCannotRead() async throws {
        let host = CaptureInitialDraftWorkHost()
        var current = true, cleaned: [Int] = []
        let old = try await host.runRetained(requireCurrent: {}, operation: { 1 }, cleanup: { cleaned.append(1); return true })
        #expect(await old.release())
        let next = try await host.runRetained(requireCurrent: {
            guard current else { throw SharedMediaStorageFailure.closed }
        }, operation: { 2 }, cleanup: { cleaned.append(2); return true })
        #expect(await old.release())
        #expect(try next.currentValue() == 2 && cleaned == [1] && !host.isQuiescent)
        current = false
        #expect(throws: (any Error).self) { try next.currentValue() }
        #expect(await host.close())
        #expect(cleaned == [1, 2])
    }

    @Test func cancelledRetainedWorkCleansBeforeShutdownAcknowledgement() async throws {
        let host = CaptureInitialDraftWorkHost(), operation = Gate(), cleanup = Gate()
        var delivered = false, closeFinished = false
        let work = Task { @MainActor in
            do {
                _ = try await host.runRetained(requireCurrent: {}, operation: { await operation.wait(); return 1 },
                    cleanup: { await cleanup.wait(); return true })
                delivered = true
            } catch {}
        }
        while !operation.entered { await Task.yield() }
        let closing = Task { @MainActor in let result = await host.close(); closeFinished = true; return result }
        while !host.isClosed { await Task.yield() }
        #expect(!host.isQuiescent && !closeFinished)
        operation.release()
        while !cleanup.entered { await Task.yield() }
        #expect(!host.isQuiescent && !closeFinished && !delivered)
        cleanup.release()
        #expect(await closing.value)
        await work.value
        #expect(!delivered && host.isQuiescent)
    }
}
