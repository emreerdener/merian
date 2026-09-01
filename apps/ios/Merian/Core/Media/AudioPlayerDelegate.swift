import AVFoundation

@MainActor
final class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: (ObjectIdentifier, Bool) -> Void = { _, _ in }
    var onDecodeError: (ObjectIdentifier, String?) -> Void = { _, _ in }

    nonisolated
    func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        let playerID = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            self?.onFinish(playerID, flag)
        }
    }

    nonisolated
    func audioPlayerDecodeErrorDidOccur(
        _ player: AVAudioPlayer,
        error: (any Error)?
    ) {
        let playerID = ObjectIdentifier(player)
        let errorDescription = error.map(String.init(describing:))
        Task { @MainActor [weak self] in
            self?.onDecodeError(playerID, errorDescription)
        }
    }
}
