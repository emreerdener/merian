import AVFoundation
import Foundation
@testable import Merian
import Testing

@Suite("Video companion audio extraction", .timeLimit(.minutes(1)))
struct CaptureScanVideoAudioExtractorTests {
    @Test(arguments: [1, 2])
    func preservesAACVideoAudioAsCanonicalInferenceWAV(channels: Int) async throws {
        let fixture = try await VideoAudioFixture(channels: channels)
        defer { fixture.remove() }
        let sourceBytes = try Data(contentsOf: fixture.videoURL)

        let lease = try #require(await CaptureScanVideoAudioExtractor.extract(
            videoURL: fixture.videoURL,
            outputDirectory: fixture.outputDirectory
        ))
        let outputURL = lease.fileURL
        #expect(InferenceAudioPreparer.isCanonicalPreparedWAV(at: outputURL))
        #expect(InferenceAudioPreparer.isQueueEligibleInferenceAudioPath(outputURL.path))
        try MerianNetworkClient.validateInlineAudioFilesForInference(fileURLs: [outputURL])

        let audio = try AVAudioFile(forReading: outputURL)
        #expect(abs(Double(audio.length) - 44_100) < 2_048)
        let buffer = try #require(AVAudioPCMBuffer(
            pcmFormat: audio.processingFormat,
            frameCapacity: AVAudioFrameCount(audio.length)
        ))
        try audio.read(into: buffer)
        let samples = try #require(buffer.floatChannelData?[0])
        let peak = (0..<Int(buffer.frameLength)).reduce(Float.zero) {
            max($0, abs(samples[$1]))
        }
        #expect(peak > 0.05, "Extraction must preserve audible samples, not just a valid header")
        #expect(try Data(contentsOf: fixture.videoURL) == sourceBytes)
        #expect(try fixture.outputFiles() == [outputURL])

        let acceptedURL = try await lease.relinquishOwnership()
        #expect(FileManager.default.fileExists(atPath: acceptedURL.path))
    }

    @Test func videoWithoutAudioProducesNoSidecar() async throws {
        let fixture = try await VideoAudioFixture(channels: nil)
        defer { fixture.remove() }
        let lease = await CaptureScanVideoAudioExtractor.extract(
            videoURL: fixture.videoURL,
            outputDirectory: fixture.outputDirectory
        )
        #expect(lease == nil)
        #expect(try fixture.outputFiles().isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.videoURL.path))
    }

    @Test func cancellationAndUnacceptedResultsLeaveNoSidecars() async throws {
        let fixture = try await VideoAudioFixture(channels: 2)
        defer { fixture.remove() }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await CaptureScanVideoAudioExtractor.extract(
                videoURL: fixture.videoURL,
                outputDirectory: fixture.outputDirectory
            )
        }
        #expect(await cancelled.value == nil)
        #expect(try fixture.outputFiles().isEmpty)

        try await extractAndDiscard(fixture)
        #expect(try fixture.outputFiles().isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.videoURL.path))
    }

    @Test func concurrentFixturePreparationAndCancellationReleaseEncoderOwnership() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for channels in [nil, 1, 2, nil, 1, 2] as [Int?] {
                group.addTask {
                    let fixture = try await VideoAudioFixture(channels: channels)
                    defer { fixture.remove() }
                    let asset = AVURLAsset(url: fixture.videoURL)
                    let video = try await asset.loadTracks(withMediaType: .video)
                    let audio = try await asset.loadTracks(withMediaType: .audio)
                    #expect(video.count == 1)
                    #expect(audio.count == (channels == nil ? 0 : 1))
                }
            }
            group.addTask {
                withUnsafeCurrentTask { $0?.cancel() }
                do {
                    let unexpected = try await VideoAudioFixture(channels: 1)
                    unexpected.remove()
                    Issue.record("Cancelled fixture creation must not complete")
                } catch is CancellationError {
                    // Pre-cancelled construction must release any acquired ownership.
                }
            }
            try await group.waitForAll()
        }
        let afterCancellation = try await VideoAudioFixture(channels: 2)
        defer { afterCancellation.remove() }
        #expect(FileManager.default.fileExists(atPath: afterCancellation.videoURL.path))
    }

    private func extractAndDiscard(_ fixture: VideoAudioFixture) async throws {
        let lease = try #require(await CaptureScanVideoAudioExtractor.extract(
            videoURL: fixture.videoURL,
            outputDirectory: fixture.outputDirectory
        ))
        #expect(InferenceAudioPreparer.isCanonicalPreparedWAV(at: lease.fileURL))
    }
}
