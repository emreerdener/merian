import Darwin
import Foundation
import os
import Testing
@testable import Merian

@Suite("Private encoder output ownership")
struct MediaProducerOutputTests {
    @Test func failedSourceCleanupDoesNotRebaselineMutatedDestination() async throws {
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: target) }
        let producer = try MediaProducerOutput(fileExtension: "wav", io: .init(unlink: { fd, name, flags in
            flags == AT_REMOVEDIR ? -1 : unlinkat(fd, name, flags)
        }))
        defer { try? FileManager.default.removeItem(at: producer.outputURL.deletingLastPathComponent()) }
        try Data([1]).write(to: producer.outputURL)
        do {
            _ = try await producer.publish(to: target, suffix: "test.wav", maximumBytes: 1)
            Issue.record("Source cleanup failure accepted")
        } catch {}
        let destination = try #require(FileManager.default.contentsOfDirectory(at: target,
            includingPropertiesForKeys: nil).first)
        let handle = try FileHandle(forWritingTo: destination)
        try handle.write(contentsOf: Data([9, 8])); try handle.close()
        for _ in 0..<2 {
            do { try await producer.discardAfterExit(); Issue.record("Mutated destination was rebased") } catch {}
        }
        #expect(try Data(contentsOf: destination) == Data([9, 8]))
    }

    @Test func directoryUnlinkSyncFailureRetriesWithoutAdoptingReplacement() async throws {
        for replace in [false, true] {
            let failSync = OSAllocatedUnfairLock(initialState: false)
            let producer = try MediaProducerOutput(fileExtension: "wav", io: .init(
                synchronize: { fd in
                    if failSync.withLock({ $0 }) { return -1 }
                    return fsync(fd)
                }, unlink: { fd, name, flags in
                    let result = unlinkat(fd, name, flags)
                    if result == 0 && flags == AT_REMOVEDIR { failSync.withLock { $0 = true } }
                    return result
                }))
            let parent = producer.outputURL.deletingLastPathComponent()
            defer { try? FileManager.default.removeItem(at: parent) }
            do { try await producer.discardAfterExit(); Issue.record("Failed sync ignored") } catch {}
            #expect(!FileManager.default.fileExists(atPath: parent.path))
            failSync.withLock { $0 = false }
            if replace {
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
                do { try await producer.discardAfterExit(); Issue.record("Replacement directory accepted") } catch {}
                #expect(FileManager.default.fileExists(atPath: parent.path))
            } else { try await producer.discardAfterExit() }
        }
    }

    @Test func failedPromotionCleanupSurvivesCallerExitAndRetriesExactReceipt() async throws {
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: target) }
        let owner = FileIOActor(documents: target, temporaryDirectory: target)
        let failSync = OSAllocatedUnfairLock(initialState: true)
        let parent = try await leaveFailedProducer(owner: owner, target: target, failSync: failSync)
        defer { try? FileManager.default.removeItem(at: parent) }
        #expect(await owner.retryProducerCleanup() == false)
        failSync.withLock { $0 = false }
        #expect(await owner.retryProducerCleanup())
        #expect(!FileManager.default.fileExists(atPath: parent.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
    }

    private func leaveFailedProducer(owner: FileIOActor, target: URL,
                                    failSync: OSAllocatedUnfairLock<Bool>) async throws -> URL {
        let producer = try MediaProducerOutput(fileExtension: "wav", io: .init(synchronize: { fd in
            failSync.withLock { $0 } ? -1 : fsync(fd)
        }))
        try Data([1, 2, 3]).write(to: producer.outputURL)
        do {
            _ = try await producer.publish(to: target, suffix: "test.wav", maximumBytes: 3)
            Issue.record("Failed destination sync accepted")
        } catch {}
        #expect(await owner.settleProducerCleanup(owner: producer) { try await producer.discardAfterExit() } == false)
        return producer.outputURL.deletingLastPathComponent()
    }

    @Test func absentOutputBecomesVerifiedFlatFileAndRollbackUsesReceipt() async throws {
        let producer = try MediaProducerOutput(fileExtension: "wav")
        #expect(!FileManager.default.fileExists(atPath: producer.outputURL.path))
        try Data([1]).write(to: producer.outputURL)
        try await producer.pinCreatedOutput()
        let handle = try FileHandle(forWritingTo: producer.outputURL)
        try handle.seekToEnd(); try handle.write(contentsOf: Data([2, 3])); try handle.close()
        let (url, receipt) = try await producer.publish(to: .documentsDirectory, suffix: "test.wav", maximumBytes: 3)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try Data(contentsOf: url) == Data([1, 2, 3]))
        #expect(!FileManager.default.fileExists(atPath: producer.outputURL.deletingLastPathComponent().path))
        let lease = CaptureScanTemporaryFileLease(fileURL: url, retirement: receipt)
        _ = try await lease.relinquishOwnership()
        try await lease.rollbackUnpublishedTransfer()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test(arguments: [false, true])
    func replacementAfterPinNeverInheritsCleanup(symlink: Bool) async throws {
        let producer = try MediaProducerOutput(fileExtension: "mp4")
        let directory = producer.outputURL.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data([1]).write(to: producer.outputURL)
        try await producer.pinCreatedOutput()
        if symlink {
            try FileManager.default.removeItem(at: producer.outputURL)
            try FileManager.default.createSymbolicLink(at: producer.outputURL, withDestinationURL: directory)
        } else { try Data([9]).write(to: producer.outputURL, options: .atomic) }
        for _ in 0..<2 {
            do { try await producer.discardAfterExit(); Issue.record("Replacement was retired") } catch {}
        }
        #expect(FileManager.default.fileExists(atPath: producer.outputURL.path))
    }

    @Test func replacedParentIsHeld() async throws {
        let producer = try MediaProducerOutput(fileExtension: "wav")
        let parent = producer.outputURL.deletingLastPathComponent()
        let moved = parent.appendingPathExtension("moved")
        defer { for url in [parent, moved] { try? FileManager.default.removeItem(at: url) } }
        try Data([1]).write(to: producer.outputURL)
        try await producer.pinCreatedOutput()
        try FileManager.default.moveItem(at: parent, to: moved)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        try Data([9]).write(to: producer.outputURL)
        do { try await producer.discardAfterExit(); Issue.record("Replaced parent was accepted") } catch {}
        #expect(try Data(contentsOf: producer.outputURL) == Data([9]))
        #expect(try Data(contentsOf: moved.appendingPathComponent("output.wav")) == Data([1]))
    }

    @Test func emptyAndOverLimitOutputsAreNotAccepted() async throws {
        for bytes in [Data(), Data([1, 2])] {
            let producer = try MediaProducerOutput(fileExtension: "wav")
            try bytes.write(to: producer.outputURL)
            try await producer.pinCreatedOutput()
            do {
                _ = try await producer.publish(to: .documentsDirectory, suffix: "test.wav", maximumBytes: 1)
                Issue.record("Invalid output accepted")
            } catch {}
            try await producer.discardAfterExit()
            #expect(!FileManager.default.fileExists(atPath: producer.outputURL.path))
        }
    }

    @Test func cancelledLateWriterIsJoinedBeforeRetirement() async throws {
        let producer = try MediaProducerOutput(fileExtension: "wav")
        let gate = ProducerExitGate()
        let worker = Task {
            await gate.wait()
            // A native writer may create output after cancellation was requested.
            try Data([1]).write(to: producer.outputURL)
            try await producer.pinCreatedOutput()
        }
        worker.cancel()
        #expect(!FileManager.default.fileExists(atPath: producer.outputURL.path))
        await gate.release()
        try await worker.value
        try await producer.discardAfterExit()
        try await producer.discardAfterExit()
        #expect(!FileManager.default.fileExists(atPath: producer.outputURL.deletingLastPathComponent().path))
    }

    @Test func rollbackNeverDeletesReplacementAfterTransfer() async throws {
        let producer = try MediaProducerOutput(fileExtension: "wav")
        try Data([1]).write(to: producer.outputURL)
        let (url, receipt) = try await producer.publish(to: .documentsDirectory, suffix: "test.wav", maximumBytes: 1)
        defer { try? FileManager.default.removeItem(at: url) }
        let lease = CaptureScanTemporaryFileLease(fileURL: url, retirement: receipt)
        _ = try await lease.relinquishOwnership()
        try Data([9]).write(to: url, options: .atomic)
        do { try await lease.rollbackUnpublishedTransfer(); Issue.record("Replacement retired") } catch {}
        do { try await lease.rollbackUnpublishedTransfer(); Issue.record("Retry retired replacement") } catch {}
        #expect(try Data(contentsOf: url) == Data([9]))
    }
}

private actor ProducerExitGate {
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}
