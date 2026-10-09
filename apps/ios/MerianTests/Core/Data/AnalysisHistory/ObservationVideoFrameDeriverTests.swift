import AVFoundation
import CryptoKit
import Foundation
import ImageIO
@testable import Merian
import Testing

@Suite(.serialized)
struct ObservationVideoFrameDeriverTests {
    @Test(arguments: [false, true])
    func exactRetainedClipProducesFiveBoundFrames(audio: Bool) async throws {
        let fixture = try await VideoAudioFixture(channels: audio ? 2 : nil)
        defer { fixture.remove() }
        let exporter = try #require(AVAssetExportSession(asset: AVURLAsset(url: fixture.videoURL), presetName: AVAssetExportPresetPassthrough))
        exporter.timeRange = CMTimeRange(start: .zero, duration: CMTime(value: 570, timescale: 600))
        let trimmed = fixture.root.appendingPathComponent("trimmed.mp4")
        try await exporter.export(to: trimmed, as: .mp4)
        let clip = try await ObservationRetainedVideoClipProducer().prepare(source: trimmed, directory: fixture.outputDirectory)
        let sourceBytes = try Data(contentsOf: clip.url)
        let sourceID = UUID()
        let edge = audio ? 1024 : 768
        let output = try await ObservationVideoFrameDeriver().derive(source: clip, sourceMediaID: sourceID,
                                                                   directory: fixture.outputDirectory, cropCenterBasisPoints: 5000, inferenceLongEdge: edge)
        #expect(output.source.mediaID == sourceID)
        #expect(output.source.sha256 == digest(sourceBytes))
        #expect(output.source.byteCount == sourceBytes.count)
        #expect(try Data(contentsOf: clip.url) == sourceBytes)
        #expect(output.frames.count == 5 && output.files.count == 5)
        #expect(Set(output.frames.map(\.artifact.mediaID)).count == 5)
        #expect(output.frames.allSatisfy { $0.sourceMediaID == sourceID })
        #expect(output.frames.map(\.index) == [0, 1, 2, 3, 4])
        let ticks = output.parameters.durationTicks
        #expect((560...590).contains(ticks))
        #expect(output.frames.map(\.requestedTimeTicks) == (0..<5).map { min(max((ticks * (1 + 2 * $0) + 5) / 10, 30), ticks - 30) })
        // Independently query actual sample times from the saved clip. The trim
        // makes requested positions fall between the original 30fps samples.
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: clip.url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        for (frame, file) in zip(output.frames, output.files) {
            let result = try await generator.image(at: CMTime(value: Int64(frame.requestedTimeTicks), timescale: 600))
            let actual = CMTimeConvertScale(result.actualTime, timescale: 600, method: .roundHalfAwayFromZero)
            #expect(frame.actualTimeTicks == Int(actual.value))
            let bytes = try Data(contentsOf: file)
            #expect(bytes.count == frame.artifact.byteCount && digest(bytes) == frame.artifact.sha256)
            let image = try #require(CGImageSourceCreateWithData(bytes as CFData, nil))
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [String: Any])
            let width = try #require(properties[kCGImagePropertyPixelWidth as String] as? Int)
            let height = try #require(properties[kCGImagePropertyPixelHeight as String] as? Int)
            #expect(width == edge && height == edge)
        }
        #expect(output.frames.contains { $0.actualTimeTicks != $0.requestedTimeTicks })
    }

    @Test
    func cancellationRemovesWholeGenerationAndAllowsReuse() async throws {
        let fixture = try await VideoAudioFixture(channels: nil)
        defer { fixture.remove() }
        let clip = try await ObservationRetainedVideoClipProducer().prepare(source: fixture.videoURL, directory: fixture.outputDirectory)
        let checkpoint = VideoFrameCheckpoint()
        let producer = ObservationVideoFrameDeriver { _ in
            if await checkpoint.enterFirst() { try await Task.sleep(for: .seconds(30)) }
        }
        let task = Task { try await producer.derive(source: clip, sourceMediaID: UUID(), directory: fixture.outputDirectory,
                                                   cropCenterBasisPoints: 5000, inferenceLongEdge: 1024) }
        let deadline = ContinuousClock.now + .seconds(10)
        while !(await checkpoint.entered), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(await checkpoint.entered)
        do { _ = try await clip.relinquishOwnership(); Issue.record("In-flight source transferred") } catch ObservationRetainedVideoClipError.busy {} catch { Issue.record("Unexpected in-flight transfer failure") }
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled frame generation succeeded") } catch is CancellationError {} catch {
            Issue.record("Unexpected cancellation failure")
        }
        #expect(try fixture.outputFiles().map(\.lastPathComponent) == [clip.url.deletingLastPathComponent().lastPathComponent])
        #expect(FileManager.default.fileExists(atPath: clip.url.path))
        let result = try await producer.derive(source: clip, sourceMediaID: UUID(), directory: fixture.outputDirectory,
                                              cropCenterBasisPoints: 5000, inferenceLongEdge: 1024)
        #expect(result.frames.count == 5)
    }

    @Test
    func interruptedValidationDropsPartialFrames() async throws {
        let fixture = try await VideoAudioFixture(channels: nil)
        defer { fixture.remove() }
        let clip = try await ObservationRetainedVideoClipProducer().prepare(source: fixture.videoURL, directory: fixture.outputDirectory)
        let producer = ObservationVideoFrameDeriver { _ in throw CancellationError() }
        do {
            _ = try await producer.derive(source: clip, sourceMediaID: UUID(), directory: fixture.outputDirectory,
                                          cropCenterBasisPoints: 5000, inferenceLongEdge: 768)
            Issue.record("Interrupted generation succeeded")
        } catch is CancellationError {} catch { Issue.record("Unexpected interruption failure") }
        #expect(try fixture.outputFiles().count == 1)
        #expect(FileManager.default.fileExists(atPath: clip.url.path))
    }

    @Test
    func sourceTransferIsExclusiveWithDerivationLifetime() async throws {
        let fixture = try await VideoAudioFixture(channels: nil)
        defer { fixture.remove() }
        let clip = try await ObservationRetainedVideoClipProducer().prepare(source: fixture.videoURL, directory: fixture.outputDirectory)
        var output: ObservationVideoFrameDerivation? = try await ObservationVideoFrameDeriver().derive(
            source: clip, sourceMediaID: UUID(), directory: fixture.outputDirectory, cropCenterBasisPoints: 5000, inferenceLongEdge: 768
        )
        #expect(output != nil)
        do { _ = try await clip.relinquishOwnership(); Issue.record("Borrowed source transferred") } catch ObservationRetainedVideoClipError.busy {} catch { Issue.record("Unexpected transfer failure") }
        output = nil
        #expect(try await clip.relinquishOwnership() == clip.url)
        do {
            _ = try await ObservationVideoFrameDeriver().derive(source: clip, sourceMediaID: UUID(), directory: fixture.outputDirectory,
                                                               cropCenterBasisPoints: 5000, inferenceLongEdge: 768)
            Issue.record("Transferred source admitted for derivation")
        } catch ObservationRetainedVideoClipError.busy {} catch { Issue.record("Unexpected admission failure") }
    }

    @Test
    func changedRetainedSourceCannotPublishFrames() async throws {
        let fixture = try await VideoAudioFixture(channels: nil)
        defer { fixture.remove() }
        let clip = try await ObservationRetainedVideoClipProducer().prepare(source: fixture.videoURL, directory: fixture.outputDirectory)
        let producer = ObservationVideoFrameDeriver { index in
            if index == 4 {
                let handle = try FileHandle(forWritingTo: clip.url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data([0]))
            }
        }
        do {
            _ = try await producer.derive(source: clip, sourceMediaID: UUID(), directory: fixture.outputDirectory,
                                          cropCenterBasisPoints: 5000, inferenceLongEdge: 768)
            Issue.record("Changed source incorrectly accepted")
        } catch ObservationVideoFrameError.sourceChanged {} catch { Issue.record("Unexpected source-mutation failure") }
        #expect(try fixture.outputFiles().count == 1)
    }

    @Test
    func droppedGenerationRemovesDirectoryAndKeepsSource() async throws {
        let fixture = try await VideoAudioFixture(channels: nil)
        defer { fixture.remove() }
        let clip = try await ObservationRetainedVideoClipProducer().prepare(source: fixture.videoURL, directory: fixture.outputDirectory)
        let directory = try await makeUnacceptedFrames(clip, directory: fixture.outputDirectory)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(FileManager.default.fileExists(atPath: clip.url.path))
    }

    private func makeUnacceptedFrames(_ clip: ObservationRetainedVideoClip, directory: URL) async throws -> URL {
        let output = try await ObservationVideoFrameDeriver().derive(source: clip, sourceMediaID: UUID(), directory: directory,
                                                                   cropCenterBasisPoints: 5000, inferenceLongEdge: 768)
        return try #require(output.files.first).deletingLastPathComponent()
    }

    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

private actor VideoFrameCheckpoint {
    private(set) var entered = false
    func enterFirst() -> Bool {
        guard !entered else { return false }
        entered = true
        return true
    }
}
