import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite("Capture artifact durable writer", .serialized)
@MainActor
struct SharedMediaCaptureArtifactWriterTests {
    @MainActor
    struct Store {
        let base: SharedMediaNativeAppBootstrapTests.Store
        let container: ModelContainer, startup: NativeReleaseStartupAdmission
        let input: SharedMediaCaptureArtifactInput
        let bytes: Data
        var directory: URL {
            base.parent.appendingPathComponent(SharedMediaCaptureRootJournal.rootName)
                .appendingPathComponent(SharedMediaCaptureRootJournal.childName)
        }
        init(byteCount: Int = 96) async throws {
            bytes = Data(repeating: 12, count: byteCount)
            let base = try SharedMediaNativeAppBootstrapTests.Store(startupEligible: true)
            self.base = base
            let first = try base.owner()
            _ = try await base.open(first)
            #expect(await first.invalidateAndAwaitForAccountTransition())
            (container, startup) = try base.startup()
            input = .init(id: UUID(), scanID: UUID(), submissionGeneration: UUID(), mediaID: UUID(),
                planSHA256: String(repeating: "b", count: 64), itemIndex: 0, role: .sourceAudio,
                frameIndex: nil, contentType: "audio/wav", byteCount: Int64(byteCount), sha256: SharedMediaAcquisitionEncoding.digest(bytes))
        }
        func open() async throws -> SharedMediaNativeOriginalOwner {
            let discovery = try SharedMediaNativeBootstrapDiscovery.qualification(container: container,
                startup: startup, parent: base.parent, ownerID: base.ownerID)
            let owner = try base.dispatchOwner()
            _ = try await owner.openApp(container: container, discovery: discovery)
            return owner
        }
        func rows() throws -> [SharedMediaOrdinaryArtifactRecord] {
            let context = ModelContext(container); context.autosaveEnabled = false
            return try context.fetch(FetchDescriptor<SharedMediaOrdinaryArtifactRecord>())
        }
    }

    @Test func writesExactBytesAndReplaysAfterColdOpenWithoutNewOwnership() async throws {
        let store = try await Store(), owner = try await store.open(), controls = try store.base.controls()
        let first = try await owner.materializeAppCaptureArtifact(store.input, bytes: store.bytes)
        #expect(first.phase == .ready)
        #expect(first.stage?.phase == .complete)
        #expect(try Data(contentsOf: store.directory.appendingPathComponent(first.request.finalName)) == store.bytes)
        #expect(try await owner.materializeAppCaptureArtifact(store.input, bytes: store.bytes) == first)
        #expect(!owner.isReadyForAppDispatch)
        await #expect(throws: (any Error).self) { _ = try await owner.inspectApp() }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await store.open()
        #expect(try await cold.materializeAppCaptureArtifact(store.input, bytes: store.bytes) == first)
        #expect(try store.rows().count == 1)
        #expect(try store.base.controls() == controls)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: SharedMediaCaptureArtifactWriteBoundary.allCases)
    func interruptionsRetainOwnershipAndOnlyRecordedInodesResume(_ boundary: SharedMediaCaptureArtifactWriteBoundary) async throws {
        let store = try await Store(), owner = try await store.open()
        var reached = false
        try owner.configureCaptureArtifactWritingForTesting { point in
            if point == boundary { reached = true; throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) { _ = try await owner.materializeAppCaptureArtifact(store.input, bytes: store.bytes) }
        #expect(reached)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await store.open()
        if boundary == .afterPartialCreation {
            // A crash before recording an inode cannot silently adopt it.
            await #expect(throws: (any Error).self) { _ = try await cold.materializeAppCaptureArtifact(store.input, bytes: store.bytes) }
            #expect(try store.rows().first?.phaseRaw == "reserved")
            let partial = store.directory.appendingPathComponent(store.input.id.uuidString.lowercased() + ".partial")
            #expect(try Data(contentsOf: partial).isEmpty)
        } else {
            let value = try await cold.materializeAppCaptureArtifact(store.input, bytes: store.bytes)
            #expect(value.phase == .ready)
            #expect(try store.rows().count == 1)
            #expect(try Data(contentsOf: store.directory.appendingPathComponent(value.request.finalName)) == store.bytes)
        }
        #expect(!cold.isReadyForAppDispatch)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func wrongBytesAndUnequalReplayCannotReplaceSavedEvidence() async throws {
        let store = try await Store(), owner = try await store.open()
        await #expect(throws: (any Error).self) {
            _ = try await owner.materializeAppCaptureArtifact(store.input, bytes: Data(repeating: 13, count: 96))
        }
        #expect(try store.rows().isEmpty)
        let value = try await owner.materializeAppCaptureArtifact(store.input, bytes: store.bytes)
        let changed = SharedMediaCaptureArtifactInput(id: store.input.id, scanID: store.input.scanID,
            submissionGeneration: store.input.submissionGeneration, mediaID: store.input.mediaID,
            planSHA256: String(repeating: "c", count: 64), itemIndex: 0, role: .sourceAudio,
            frameIndex: nil, contentType: "audio/wav", byteCount: 96, sha256: store.input.sha256)
        await #expect(throws: (any Error).self) { _ = try await owner.materializeAppCaptureArtifact(changed, bytes: store.bytes) }
        #expect(try await owner.materializeAppCaptureArtifact(store.input, bytes: store.bytes) == value)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [false, true])
    func cancellationAndAccountDrainJoinTheActualWriter(_ accountDrain: Bool) async throws {
        let store = try await Store(byteCount: 131_072), owner = try await store.open(), gate = Gate()
        try owner.configureCaptureArtifactWritingForTesting(pause: { _ in await gate.pause() })
        let write = Task { @MainActor in
            do {
                let result = try await owner.materializeAppCaptureArtifact(store.input, bytes: store.bytes)
                await gate.finish(); return result
            } catch { await gate.finish(); throw error }
        }
        guard await gate.entered() else { _ = try await write.value; Issue.record("Writer did not suspend"); return }
        let held = try #require(try store.rows().first)
        let initial = try SharedMediaCaptureArtifactLedger.receipt(held)
        #expect(initial.phase == .writing)
        let partial = store.directory.appendingPathComponent(initial.request.partialName)
        #expect(try Data(contentsOf: partial).count == 65_536)
        var drained = false
        let drain: Task<Bool, Never>?
        if accountDrain {
            drain = Task { @MainActor in
                let result = await owner.invalidateAndAwaitForAccountTransition(); drained = true; return result
            }
        } else { drain = nil; write.cancel() }
        await Task.yield()
        #expect(!drained)
        await gate.release()
        await #expect(throws: (any Error).self) { _ = try await write.value }
        if let drain { #expect(await drain.value) } else { #expect(await owner.invalidateAndAwaitForAccountTransition()) }
        let saved = try SharedMediaCaptureArtifactLedger.receipt(#require(try store.rows().first))
        #expect(saved.phase == .writing && saved.stage?.partialIdentity == initial.stage?.partialIdentity)
        #expect(try Data(contentsOf: partial).count == 65_536)
        let cold = try await store.open()
        let recovered = try await cold.materializeAppCaptureArtifact(store.input, bytes: store.bytes)
        #expect(recovered.phase == .ready && recovered.stage?.partialIdentity == initial.stage?.partialIdentity)
        #expect(try Data(contentsOf: store.directory.appendingPathComponent(recovered.request.finalName)) == store.bytes)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func anotherMediaIDCannotDuplicateTheSamePlanRole() async throws {
        let store = try await Store(), owner = try await store.open()
        let first = try await owner.materializeAppCaptureArtifact(store.input, bytes: store.bytes)
        let duplicate = SharedMediaCaptureArtifactInput(id: UUID(), scanID: store.input.scanID,
            submissionGeneration: store.input.submissionGeneration, mediaID: UUID(), planSHA256: store.input.planSHA256,
            itemIndex: 0, role: .sourceAudio, frameIndex: nil, contentType: "audio/wav", byteCount: 96, sha256: store.input.sha256)
        await #expect(throws: (any Error).self) { _ = try await owner.materializeAppCaptureArtifact(duplicate, bytes: store.bytes) }
        #expect(try store.rows().count == 1)
        #expect(try await owner.materializeAppCaptureArtifact(store.input, bytes: store.bytes) == first)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
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
}
