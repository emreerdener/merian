import AVFoundation
import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import Merian

@Suite("Concurrent video preparation")
struct CaptureScanVideoPreparationTests {
    @Test(arguments: [false, true])
    func canonicalSquareFramesAndPlaybackUseTheSameOrientation(rotated: Bool) async throws {
        let transform = rotated ? CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 160, ty: 0) : .identity
        let fixture = try await VideoAudioFixture(channels: nil, width: 96, height: 160, transform: transform)
        defer { fixture.remove() }
        let asset = AVURLAsset(url: fixture.videoURL)
        let composition = try await CaptureScanVideoMediaPreparer.canonicalSquareComposition(asset: asset, composingCenter: 0.75)
        #expect(composition.renderSize == CGSize(width: 96, height: 96))
        let instruction = try #require(composition.instructions.first as? AVVideoCompositionInstruction)
        let layer = try #require(instruction.layerInstructions.first)
        var start = CGAffineTransform.identity, end = CGAffineTransform.identity
        var timeRange = CMTimeRange.zero
        #expect(layer.getTransformRamp(for: .zero, start: &start, end: &end, timeRange: &timeRange))
        // Expected coordinates are in upright source pixels, before encoding.
        // Portrait crop is y=64; rotated landscape is x=32 after orientation.
        let expected = rotated ? CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 128, ty: 0)
            : CGAffineTransform(translationX: 0, y: -64)
        #expect(start == expected)
        let result = try await CaptureScanVideoMediaPreparer.prepare(.init(videoURL: fixture.videoURL,
            duration: 1, composingCenter: 0.75, isProActive: true))
        defer {
            try? FileManager.default.removeItem(at: result.playback.fileURL)
            if let audio = result.audioFilePath { try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent(audio)) }
        }
        #expect(result.playback.fileURL != fixture.videoURL)
        let prepared = AVURLAsset(url: result.playback.fileURL)
        let track = try #require(try await prepared.loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 96, height: 96))
        #expect(result.sampledFrames.count == 5)
        #expect(result.sampledFrames.allSatisfy { $0.previewCGImage.image.width == 96 && $0.previewCGImage.image.height == 96 })
        #expect(FileManager.default.fileExists(atPath: fixture.videoURL.path))
    }

    @Test(arguments: [0, 1, 2, 3])
    func editedFramingMapsViewportCenterToTheSelectedSourcePixels(turns: Int) async throws {
        let fixture = try await VideoAudioFixture(channels: nil, width: 96, height: 160)
        defer { fixture.remove() }
        let framing = CaptureVideoFraming(scale: 2, offset: .init(width: 25, height: -25),
            displaySize: 200, quarterTurns: turns)
        let composition = try await CaptureScanVideoMediaPreparer.canonicalSquareComposition(
            asset: AVURLAsset(url: fixture.videoURL), composingCenter: 0.75, framing: framing)
        #expect(composition.renderSize == CGSize(width: 48, height: 48))
        let instruction = try #require(composition.instructions.first as? AVVideoCompositionInstruction)
        let layer = try #require(instruction.layerInstructions.first)
        var start = CGAffineTransform.identity, end = CGAffineTransform.identity
        var timeRange = CMTimeRange.zero
        #expect(layer.getTransformRamp(for: .zero, start: &start, end: &end, timeRange: &timeRange))
        // At 2x zoom, each 25-point translation selects six source pixels.
        // These four expected centers are hand-derived in unrotated source space.
        let centers = [CGPoint(x: 42, y: 86), CGPoint(x: 54, y: 86),
                       CGPoint(x: 54, y: 74), CGPoint(x: 42, y: 74)]
        let mapped = centers[turns].applying(start)
        #expect(abs(mapped.x - 24) < 0.001 && abs(mapped.y - 24) < 0.001)
    }

    @MainActor
    @Test(arguments: [96, 160], [0, 1])
    func editedPlaybackAndInferenceMatchTheVisibleCrop(width: Int, turns: Int) async throws {
        try await checkVisibleCrop(width: width, turns: turns, preferredRotation: false)
    }

    @MainActor
    @Test(arguments: [1, 3])
    func preferredTrackOrientationAndInteractiveRotationMatchPixels(turns: Int) async throws {
        try await checkVisibleCrop(width: 96, turns: turns, preferredRotation: true)
    }

    @MainActor
    private func checkVisibleCrop(width: Int, turns: Int, preferredRotation: Bool) async throws {
        let transform = preferredRotation ? CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 160, ty: 0) : .identity
        let fixture = try await VideoAudioFixture(channels: nil, width: width,
            height: width == 96 ? 160 : 96, transform: transform, coordinatePattern: true)
        defer { fixture.remove() }
        let video = StagedVideo(filePath: fixture.videoURL.path, sampledImages: [])
        let editor = try await CaptureVideoEditorState.load(video: video)
        editor.crop.resize(to: 200)
        for _ in 0..<turns { editor.crop.rotate(clockwise: true) }
        editor.crop.magnify(2, ended: true)
        editor.crop.drag(.init(width: 25, height: -25), ended: true)
        let displayed = try #require(UIImage(data: await editor.crop.generateCrop()))
        // UIImage display honors EXIF orientation; cgImage alone discards it.
        // Render the same upright image the review UI shows before comparing pixels.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true
        let visible = try #require(UIGraphicsImageRenderer(size: displayed.size, format: format).image { _ in
            displayed.draw(in: CGRect(origin: .zero, size: displayed.size))
        }.cgImage)
        let result = try await CaptureScanVideoMediaPreparer.prepare(.init(videoURL: fixture.videoURL,
            duration: 1, composingCenter: 0.5, isProActive: true, framing: editor.framing))
        defer { try? FileManager.default.removeItem(at: result.playback.fileURL) }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: result.playback.fileURL))
        generator.appliesPreferredTrackTransform = true
        let playback = try await generator.image(at: .zero).image
        let reference = try colorSamples(visible)
        for actual in [playback] + result.sampledFrames.map(\.previewCGImage.image) {
            let samples = try colorSamples(actual)
            let differences = zip(reference, samples).map { abs(Int($0) - Int($1)) }
            // Lossy H.264/JPEG encoding may shift colors slightly. A wrong crop,
            // rotation or orientation in this coordinate gradient shifts far more.
            let mean = Double(differences.reduce(0, +)) / Double(differences.count)
            #expect(mean < 8, "rotation=\(turns), preferred=\(preferredRotation), mean RGB difference=\(mean)")
        }
    }

    private func colorSamples(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 12 * 12 * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: 12, height: 12,
                bitsPerComponent: 8, bytesPerRow: 48, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: 12, height: 12))
        }
        return bytes.enumerated().filter { $0.offset % 4 < 3 }.map(\.element)
    }

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
        do { _ = try await task.value; Issue.record("Frame failure was lost") } catch { #expect((error as? CocoaError)?.code == .fileReadCorruptFile) }
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
        do { _ = try await task.value; Issue.record("Timeout unexpectedly succeeded") } catch { #expect((error as NSError).code == -29) }
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
        // Existing-file leases deliberately accept only flat temporary-root files.
        audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-audio.wav")
        playbackURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-playback.mp4")
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
                if borrowedPlayback { lease = nil } else {
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
        for url in [root, audioURL, playbackURL] { try? FileManager.default.removeItem(at: url) }
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
