import AVFoundation

struct AudioRecordingInputFormat: Equatable, Sendable {
    let sampleRate: Double
    let channelCount: AVAudioChannelCount

    init(sampleRate: Double, channelCount: AVAudioChannelCount) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }

    init(_ format: AVAudioFormat) {
        self.init(
            sampleRate: format.sampleRate,
            channelCount: format.channelCount
        )
    }

    var isUsable: Bool {
        sampleRate > 0 && channelCount > 0
    }
}

struct AudioRecordingColumnEvaluation: Sendable {
    let column: SpectrogramColumn
    let snrLevel: SNRLevel
}
