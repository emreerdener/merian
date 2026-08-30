import AVFoundation
import Testing

@testable import Merian

@Suite("SpectrogramActor")
struct SpectrogramActorTests {
    @Test("Every FFT window in a buffer produces a column")
    func processColumnsUsesEveryFFTWindowInBuffer() async throws {
        let format = try #require(
            AVAudioFormat(
                standardFormatWithSampleRate: 48_000,
                channels: 1
            )
        )
        let buffer = try #require(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(
                    SpectrogramActor.fftSize * 2
                )
            )
        )
        buffer.frameLength = AVAudioFrameCount(
            SpectrogramActor.fftSize * 2
        )

        let channel = try #require(buffer.floatChannelData?[0])
        for sampleIndex in 0..<(SpectrogramActor.fftSize * 2) {
            let phase = 2 * Float.pi * 1_200 * Float(sampleIndex) / 48_000
            channel[sampleIndex] = sinf(phase) * 0.5
        }

        let actor = SpectrogramActor()
        let columns = await actor.processColumns(buffer: buffer)

        #expect(columns.count == 2)
        #expect(SpectrogramActor.outputBinCount == 128)
        #expect(
            columns.allSatisfy {
                $0.magnitudes.count == SpectrogramActor.outputBinCount
            }
        )
        #expect(columns.contains { ($0.magnitudes.max() ?? 0) > 0 })
    }
}
