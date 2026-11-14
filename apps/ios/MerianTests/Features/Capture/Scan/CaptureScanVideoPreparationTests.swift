import CoreGraphics
import Foundation
import Testing

@testable import Merian

@Suite("Concurrent video preparation")
struct CaptureScanVideoPreparationTests {
    @Test func allStagesStartBeforeAnyCompletesAndAcceptedFilesSurvive() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let gate = PreparationGate()
        let task = Task {
            try await CaptureScanVideoMediaPreparer.prepare(
                fixture.request, dependencies: fixture.dependencies(gate: gate)
            )
        }
        let startedTogether = await gate.waitForAllStages()
        await gate.release()
        let result = try await task.value

        #expect(startedTogether)
        #expect(result.sampledFrames.count == 1)
        #expect(result.audioFilePath == fixture.audioURL.lastPathComponent)
        #expect(result.playback.fileURL == fixture.playbackURL)
        #expect(FileManager.default.fileExists(atPath: fixture.audioURL.path))
        #expect(FileManager.default.fileExists(atPath: fixture.playbackURL.path))
    }

    @Test(arguments: [false, true])
    func failureOrCancellationCleansUnacceptedParallelArtifacts(cancel: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let gate = PreparationGate()
        let task = Task {
            try await CaptureScanVideoMediaPreparer.prepare(
                fixture.request,
                dependencies: fixture.dependencies(gate: gate, failFrames: !cancel)
            )
        }
        let startedTogether = await gate.waitForAllStages()
        if cancel { task.cancel() }
        // Workers deliberately return artifacts even after cancellation.
        await gate.release()
        do {
            _ = try await task.value
            Issue.record("Unaccepted preparation unexpectedly succeeded")
        } catch {
            if cancel { #expect(error is CancellationError) }
        }

        #expect(startedTogether)
        #expect(!FileManager.default.fileExists(atPath: fixture.audioURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.playbackURL.path))
        #expect(FileManager.default.fileExists(atPath: fixture.sourceURL.path))
    }

    @Test func failedFramesPreserveBorrowedOriginalPlayback() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let gate = PreparationGate()
        let task = Task {
            try await CaptureScanVideoMediaPreparer.prepare(fixture.request,
                dependencies: fixture.dependencies(gate: gate, failFrames: true, borrowedPlayback: true))
        }
        let started = await gate.waitForAllStages()
        await gate.release()
        do { _ = try await task.value; Issue.record("Frame failure was lost") }
        catch { #expect((error as? CocoaError)?.code == .fileReadCorruptFile) }
        #expect(started)
        #expect(!FileManager.default.fileExists(atPath: fixture.audioURL.path))
        #expect(try Data(contentsOf: fixture.sourceURL) == Data([1]))
    }

    @Test func timeoutDrainsAndDiscardsLateLeaseEvenWhenRetained() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let gate = LateLeaseGate()
        let task = Task {
            try await CaptureScanVideoMediaPreparer.qualifyLeaseTimeout(seconds: 0.1) {
                await withTaskCancellationHandler {
                    await gate.waitForRelease()
                    try? Data([1]).write(to: fixture.audioURL)
                    let lease = CaptureScanTemporaryFileLease(fileURL: fixture.audioURL)
                    await gate.retain(lease)
                    return lease
                } onCancel: { Task { await gate.cancelled() } }
            }
        }
        let cancelled = await gate.waitForCancellation()
        // The producer deliberately ignores cancellation until explicitly drained.
        await gate.release()
        do { _ = try await task.value; Issue.record("Timeout unexpectedly succeeded") }
        catch { #expect((error as NSError).code == -29) }
        #expect(cancelled)
        #expect(!FileManager.default.fileExists(atPath: fixture.audioURL.path))
        #expect(await gate.hasRetainedLease)
    }

}

private struct Fixture: Sendable {
    let root: URL
    let sourceURL: URL
    let audioURL: URL
    let playbackURL: URL
    let frame: PreparedCaptureScanStill

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        sourceURL = root.appendingPathComponent("source.mp4")
        audioURL = root.appendingPathComponent("audio.wav")
        playbackURL = root.appendingPathComponent("playback.mp4")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([1]).write(to: sourceURL)
        let context = try #require(CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        frame = PreparedCaptureScanStill(
            inferenceData: Data([1]), displayData: Data([1]),
            previewCGImage: SendableCGImage(image: try #require(context.makeImage()))
        )
    }

    var request: CaptureScanVideoPreparationRequest {
        .init(videoURL: sourceURL, duration: 5, composingCenter: 0.5, isProActive: true)
    }

    func dependencies(
        gate: PreparationGate, failFrames: Bool = false, borrowedPlayback: Bool = false
    ) -> CaptureScanVideoMediaPreparer.Dependencies {
        .init(
            frames: { _ in
                await gate.arrive("frames")
                if failFrames { throw CocoaError(.fileReadCorruptFile) }
                return [frame]
            },
            audio: { _ in
                await gate.arrive("audio")
                try? Data([1]).write(to: audioURL)
                let lease = CaptureScanTemporaryFileLease(fileURL: audioURL)
                await gate.retain(lease)
                return lease
            },
            playback: { _ in
                await gate.arrive("playback")
                let lease: CaptureScanTemporaryFileLease?
                if borrowedPlayback { lease = nil }
                else {
                    try Data([1]).write(to: playbackURL)
                    let owned = CaptureScanTemporaryFileLease(fileURL: playbackURL)
                    await gate.retain(owned)
                    lease = owned
                }
                return .init(
                    playback: .init(
                        fileURL: borrowedPlayback ? sourceURL : playbackURL, isCompressed: !borrowedPlayback, originalBytes: 2,
                        playbackBytes: 1, preparationDuration: 0
                    ),
                    lease: lease
                )
            }
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private actor PreparationGate {
    // Keep successful child results alive beyond the outer task. Cleanup must
    // be explicit and observable; ARC must not make this regression pass.
    private var retainedLeases: [CaptureScanTemporaryFileLease] = []
    func retain(_ lease: CaptureScanTemporaryFileLease) { retainedLeases.append(lease) }
    private var arrivals: Set<String> = []
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var isReleased = false

    func arrive(_ stage: String) async {
        arrivals.insert(stage)
        guard !isReleased else { return }
        await withCheckedContinuation { continuations.append($0) }
    }

    func waitForAllStages() async -> Bool {
        for _ in 0..<100 where arrivals.count < 3 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return arrivals.count == 3
    }

    func release() {
        isReleased = true
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}

private actor LateLeaseGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    private var sawCancellation = false
    private var lease: CaptureScanTemporaryFileLease?
    var hasRetainedLease: Bool { lease != nil }
    func retain(_ value: CaptureScanTemporaryFileLease) { lease = value }
    func cancelled() { sawCancellation = true }
    func waitForRelease() async {
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
    func waitForCancellation() async -> Bool {
        for _ in 0..<500 where !sawCancellation {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return sawCancellation
    }
}
