import AVFoundation
import Foundation
import Testing

@testable import Merian

@Suite("Uncached recording preview boost")
struct AudioPreviewBoostProcessorTests {
    @Test("Preview derivatives preserve original PCM and cannot evict shared playback")
    func previewFilesAreIndependentOfOriginalAndSharedCache() async throws {
        let source = try makeWAV()
        defer { try? FileManager.default.removeItem(at: source) }
        let original = try Data(contentsOf: source)
        let shared = try await AudioBoostProcessor.shared.prepare(source: source.path)
        let first = try await AudioBoostProcessor.prepareLocalPreview(sourceURL: source)
        let second = try await AudioBoostProcessor.prepareLocalPreview(sourceURL: source)
        defer {
            try? FileManager.default.removeItem(at: first.url)
            try? FileManager.default.removeItem(at: second.url)
        }
        #expect(first.url != second.url)
        #expect(first.url != shared.url)
        #expect(second.url != shared.url)
        #expect(first.gainDecibels > 0)
        #expect(try Data(contentsOf: source) == original)
        #expect(try AVAudioFile(forReading: first.url).length == 4_800)
        #expect(try AVAudioFile(forReading: second.url).length == 4_800)
        try FileManager.default.removeItem(at: first.url)
        let cached = try await AudioBoostProcessor.shared.prepare(source: source.path)
        #expect(cached.url == shared.url)
        #expect(try AVAudioFile(forReading: cached.url).length == 4_800)
        await AudioBoostProcessor.shared.invalidate(source: source.path)
    }

    @Test("Already-cancelled preparation preserves the original")
    @MainActor
    func cancelledPreparationPreservesSource() async throws {
        let source = try makeWAV()
        defer { try? FileManager.default.removeItem(at: source) }
        let original = try Data(contentsOf: source)
        let task = Task { try await AudioBoostProcessor.prepareLocalPreview(sourceURL: source) }
        task.cancel()
        do {
            let unexpected = try await task.value
            try? FileManager.default.removeItem(at: unexpected.url)
            Issue.record("Cancelled preview unexpectedly completed")
        } catch is CancellationError {
            #expect(try Data(contentsOf: source) == original)
        }
    }

    private func makeWAV() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("preview-source-\(UUID().uuidString).wav")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800))
        buffer.frameLength = 4_800
        let samples = try #require(buffer.floatChannelData?[0])
        for index in 0..<4_800 {
            samples[index] = 0.01 * sin(Float(index) * 2 * .pi * 1_000 / 48_000)
        }
        try autoreleasepool {
            let file = try AVAudioFile(forWriting: url, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ])
            try file.write(from: buffer)
        }
        return url
    }
}
