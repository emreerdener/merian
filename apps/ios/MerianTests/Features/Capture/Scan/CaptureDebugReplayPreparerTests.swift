#if DEBUG && targetEnvironment(simulator)
import CoreGraphics
import Foundation
import Testing

@testable import Merian

@Suite("Debug replay preparation")
struct CaptureDebugReplayPreparerTests {
    @Test func comparisonPreservesCompleteWAVThroughRequestSerialization() async throws {
        let fixture = try ReplayFixture()
        defer { fixture.remove() }
        let bytes = makeInferenceTestPCM16WAVData(
            sampleRate: 44_100, frameCount: 4_097,
            sampleAt: { Int16(($0 % 127) * 97 - 6_000) }
        )
        let comparison = fixture.comparison(for: bytes)
        try bytes.write(to: fixture.source(.audio))

        let result = try await fixture.prepare(.audio, comparison: comparison)
        guard case .audio(let url) = result else {
            Issue.record("Expected comparison audio"); return
        }
        let prepared = try Data(contentsOf: url)
        #expect(url != fixture.source(.audio))
        #expect(prepared == bytes, "The frozen assignment binds the entire WAV, not only PCM samples.")
        #expect(InferenceAudioPreparer.isCanonicalPreparedWAV(at: url))
        var request: [String: Any] = [
            "client_scan_id": comparison.scanId,
            "audioBase64s": [prepared.base64EncodedString()]
        ]
        try comparison.addHandle(to: &request)
        #expect((request["audio_comparison"] as? [String: Any])?["slot"] as? Int == comparison.slot)
        #expect(try fixture.workingFiles() == [url.lastPathComponent])
        await result.discard(documentsDirectory: fixture.root)
        #expect(try fixture.workingFiles().isEmpty)
        #expect(try Data(contentsOf: fixture.source(.audio)) == bytes)
    }

    @Test func comparisonRejectsChangedSourceAndCleansCopy() async throws {
        let fixture = try ReplayFixture()
        defer { fixture.remove() }
        let original = makeInferenceTestPCM16WAVData(sampleRate: 44_100)
        var changed = original
        changed[changed.count - 1] ^= 1
        try changed.write(to: fixture.source(.audio))

        await #expect(throws: CaptureDebugReplayError.self) {
            try await fixture.prepare(.audio, comparison: fixture.comparison(for: original))
        }
        #expect(try fixture.workingFiles().isEmpty)
        #expect(try Data(contentsOf: fixture.source(.audio)) == changed)
    }

    @Test func comparisonRejectsMatchingButNonCanonicalAudio() async throws {
        let fixture = try ReplayFixture()
        defer { fixture.remove() }
        let bytes = makeInferenceTestPCM16WAVData(sampleRate: 48_000)
        try bytes.write(to: fixture.source(.audio))

        await #expect(throws: CaptureDebugReplayError.self) {
            try await fixture.prepare(.audio, comparison: fixture.comparison(for: bytes))
        }
        #expect(try fixture.workingFiles().isEmpty)
    }

    @Test func comparisonCancellationDiscardsOnlyOwnedCopy() async throws {
        let fixture = try ReplayFixture()
        defer { fixture.remove() }
        let bytes = makeInferenceTestPCM16WAVData(sampleRate: 44_100)
        try bytes.write(to: fixture.source(.audio))
        var dependencies = CaptureDebugReplayPreparer.Dependencies.live
        dependencies.metadata = { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return .init(duration: 1, hasAudio: true, hasVideo: false)
        }
        let cancellationDependencies = dependencies
        let task = Task {
            try await fixture.prepare(
                .audio, comparison: fixture.comparison(for: bytes),
                dependencies: cancellationDependencies
            )
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try fixture.workingFiles().isEmpty)
        #expect(try Data(contentsOf: fixture.source(.audio)) == bytes)
    }

    @Test func audioUsesCanonicalPreparationAndPreservesInbox() async throws {
        let fixture = try ReplayFixture()
        defer { fixture.remove() }
        let bytes = makeInferenceTestPCM16WAVData(frameCount: 48_000)
        try bytes.write(to: fixture.source(.audio))

        let result = try await fixture.prepare(.audio)
        guard case .audio(let url) = result else {
            Issue.record("Expected prepared audio"); return
        }
        #expect(url != fixture.source(.audio))
        #expect(InferenceAudioPreparer.isCanonicalPreparedWAV(at: url))
        #expect(try Data(contentsOf: fixture.source(.audio)) == bytes)
        #expect(try fixture.workingFiles() == [url.lastPathComponent])
        await result.discard(documentsDirectory: fixture.root)
        #expect(try fixture.workingFiles().isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.source(.audio).path))
    }

    @Test func rejectsAudioLongerThanRecorderLimitWithoutLeavingCopies() async throws {
        let fixture = try ReplayFixture()
        defer { fixture.remove() }
        try makeInferenceTestPCM16WAVData(frameCount: 48_000 * 16).write(to: fixture.source(.audio))
        await #expect(throws: CaptureDebugReplayError.self) { try await fixture.prepare(.audio) }
        #expect(try fixture.workingFiles().isEmpty)
    }

    @Test(arguments: [false, true])
    func rejectsOversizedOrLinkedSource(link: Bool) async throws {
        let fixture = try ReplayFixture()
        defer { fixture.remove() }
        if link {
            let outside = fixture.root.appendingPathComponent("linked.wav")
            try makeInferenceTestPCM16WAVData().write(to: outside)
            try FileManager.default.createSymbolicLink(at: fixture.source(.audio), withDestinationURL: outside)
        } else {
            try Data(repeating: 0, count: CaptureDebugReplayKind.audio.maximumBytes + 1)
                .write(to: fixture.source(.audio))
        }
        await #expect(throws: CaptureDebugReplayError.self) { try await fixture.prepare(.audio) }
        #expect(try fixture.workingFiles().allSatisfy { $0 == "linked.wav" })
    }

    @Test(arguments: [4, 5])
    func rejectsIncompleteFramesOrMissingCompanionAudio(frameCount: Int) async throws {
        let fixture = try ReplayFixture()
        defer { fixture.remove() }
        let dependencies = fixture.videoDependencies(
            frameCount: frameCount, includeAudio: frameCount == 4
        )
        await #expect(throws: CaptureDebugReplayError.self) {
            try await fixture.prepare(.video, dependencies: dependencies)
        }
        #expect(try fixture.workingFiles().isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.source(.video).path))
    }

    @Test func rejectsLinkedInboxDirectory() async throws {
        let fixture = try ReplayFixture()
        defer { fixture.remove() }
        let inbox = fixture.root.appendingPathComponent("IdentificationReplay")
        let movedInbox = fixture.root.appendingPathComponent("moved-inbox")
        try makeInferenceTestPCM16WAVData().write(to: fixture.source(.audio))
        try FileManager.default.moveItem(at: inbox, to: movedInbox)
        try FileManager.default.createSymbolicLink(at: inbox, withDestinationURL: movedInbox)
        await #expect(throws: CaptureDebugReplayError.self) { try await fixture.prepare(.audio) }
        #expect(try fixture.workingFiles() == ["moved-inbox"])
        #expect(FileManager.default.fileExists(atPath: movedInbox.appendingPathComponent("audio.wav").path))
    }

    @Test(arguments: [false, true])
    func videoPreservesFiveFramesAudioAndPlaybackOwnership(fallback: Bool) async throws {
        let fixture = try ReplayFixture()
        defer { fixture.remove() }
        let result = try await fixture.prepare(
            .video, dependencies: fixture.videoDependencies(fallback: fallback)
        )
        guard case .video(let video) = result else {
            Issue.record("Expected prepared video"); return
        }
        #expect(video.sampledFrames.count == 5)
        #expect(video.audioFilePath == "companion.wav")
        #expect(video.playback.fileURL != fixture.source(.video))
        #expect(try fixture.workingFiles().count == 2)
        await result.discard(documentsDirectory: fixture.root)
        #expect(try fixture.workingFiles().isEmpty)
        #expect(try Data(contentsOf: fixture.source(.video)) == Data([1]))
    }

    @Test func cancellationAfterVideoReturnsCleansEveryOwnedFile() async throws {
        let fixture = try ReplayFixture()
        defer { fixture.remove() }
        var dependencies = fixture.videoDependencies()
        let prepareVideo = dependencies.video
        dependencies.video = { request in
            let video = try await prepareVideo(request)
            withUnsafeCurrentTask { $0?.cancel() }
            return video
        }
        let cancellationDependencies = dependencies
        let task = Task { try await fixture.prepare(.video, dependencies: cancellationDependencies) }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try fixture.workingFiles().isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.source(.video).path))
    }

    @Test(arguments: [0.0, 5.1, Double.infinity, Double.nan])
    func rejectsInvalidVideoDuration(duration: Double) async throws {
        let fixture = try ReplayFixture()
        defer { fixture.remove() }
        var dependencies = fixture.videoDependencies()
        dependencies.metadata = { _ in .init(duration: duration, hasAudio: true, hasVideo: true) }
        await #expect(throws: CaptureDebugReplayError.self) {
            try await fixture.prepare(.video, dependencies: dependencies)
        }
        #expect(try fixture.workingFiles().isEmpty)
    }
}

private struct ReplayFixture: Sendable {
    let root: URL
    let frame: PreparedCaptureScanStill

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("IdentificationReplay"), withIntermediateDirectories: true
        )
        let context = try #require(CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        frame = PreparedCaptureScanStill(
            inferenceData: Data([1]), displayData: Data([2]),
            previewCGImage: SendableCGImage(image: try #require(context.makeImage()))
        )
        try Data([1]).write(to: source(.video))
    }

    func source(_ kind: CaptureDebugReplayKind) -> URL {
        root.appendingPathComponent("IdentificationReplay").appendingPathComponent(kind.filename)
    }

    func workingFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0 != "IdentificationReplay" }.sorted()
    }

    func prepare(
        _ kind: CaptureDebugReplayKind,
        comparison: DebugAudioComparisonAssignment? = nil,
        dependencies: CaptureDebugReplayPreparer.Dependencies = .live
    ) async throws -> PreparedCaptureDebugReplay {
        try await CaptureDebugReplayPreparer.prepare(
            kind, composingCenter: 0.5, isProActive: true,
            comparison: comparison,
            documentsDirectory: root, dependencies: dependencies
        )
    }

    func comparison(for bytes: Data) -> DebugAudioComparisonAssignment {
        let placeholder = String(repeating: "0", count: 64)
        return DebugAudioComparisonAssignment(
            slot: 1, caseId: "synthetic", arm: "synthetic",
            sourceWavSha256: DebugAudioComparisonAssignment.digest(bytes), sourceByteLength: bytes.count,
            processedWavSha256: placeholder, providerRequestSha256: placeholder,
            policySha256: placeholder, confidenceSha256: placeholder,
            scanId: "00000000-0000-4000-8000-000000000001"
        )
    }

    func videoDependencies(
        frameCount: Int = 5, includeAudio: Bool = true, fallback: Bool = false
    ) -> CaptureDebugReplayPreparer.Dependencies {
        .init(
            metadata: { _ in .init(duration: 5, hasAudio: true, hasVideo: true) },
            video: { request in
                #expect(request.videoURL != source(.video))
                #expect(request.duration == 5)
                #expect(request.composingCenter == 0.5)
                #expect(request.isProActive)
                let playback = fallback ? request.videoURL : root.appendingPathComponent("playback.mp4")
                try Data([2]).write(to: playback)
                if includeAudio {
                    try makeInferenceTestPCM16WAVData().write(to: root.appendingPathComponent("companion.wav"))
                }
                return PreparedCaptureScanVideo(
                    sampledFrames: Array(repeating: frame, count: frameCount),
                    audioFilePath: includeAudio ? "companion.wav" : nil,
                    playback: .init(fileURL: playback, isCompressed: !fallback,
                                    originalBytes: 1, playbackBytes: 1, preparationDuration: 0)
                )
            }
        )
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
#endif
