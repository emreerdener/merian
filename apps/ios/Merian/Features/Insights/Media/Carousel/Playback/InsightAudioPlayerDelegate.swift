import AVFoundation

final class InsightAudioPlayerDelegate:
    NSObject,
    AVAudioPlayerDelegate,
    @unchecked Sendable {
    var onFinish: (AVAudioPlayer, Bool) -> Void = { _, _ in }
    var onDecodeError: (AVAudioPlayer, (any Error)?) -> Void = { _, _ in }

    func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        onFinish(player, flag)
    }

    func audioPlayerDecodeErrorDidOccur(
        _ player: AVAudioPlayer,
        error: (any Error)?
    ) {
        onDecodeError(player, error)
    }
}
