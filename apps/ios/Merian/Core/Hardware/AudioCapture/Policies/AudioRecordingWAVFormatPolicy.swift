import AVFoundation

enum AudioRecordingWAVFormatPolicy {
    static func makeFormat(
        sampleRate: Double,
        channelCount: AVAudioChannelCount
    ) -> AVAudioFormat? {
        guard sampleRate > 0, channelCount > 0 else { return nil }
        return AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: true
        )
    }
}
