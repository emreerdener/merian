import Foundation
import Observation

/// One verified in-memory recording. Playback uses the shared executor and audio-session lease.
@MainActor @Observable
final class CaptureSavedAudioPreviewModel {
    private(set) var isPlaying = false
    private(set) var isReady = false
    private(set) var isClosed = false
    private(set) var message: String?
    private let validate: () -> Bool
    private let session: AudioPlaybackSessionController
    private var player: AudioPlaybackFilePlayer?
    private var command: Task<Void, Never>?
    private var revision = 0

    init(driver: any AudioPlaybackDriver, validate: @escaping () -> Bool,
         session: AudioPlaybackSessionController? = nil) {
        self.validate = validate; self.session = session ?? AudioPlaybackSessionController()
        player = AudioPlaybackFilePlayer(driver: driver)
        player?.onFinish = { [weak self] _, _ in self?.pause() }
        player?.onDecodeError = { [weak self] _, _ in self?.close() }
    }

    func load() async {
        guard !isClosed, validate(), let player else { close(); return }
        do {
            try await player.load()
            guard !Task.isCancelled, !isClosed, validate() else { close(); return }
            isReady = true
        } catch { close() }
    }

    func toggle() {
        guard !isClosed, isReady, validate(), let player else { close(); return }
        if isPlaying || command != nil { pause(); return }
        let expected = revision
        command = Task { [weak self] in
            guard let self else { return }
            defer { if revision == expected { command = nil } }
            guard await session.activate(), !Task.isCancelled, revision == expected, !isClosed, validate() else {
                if revision == expected { pause() }
                return
            }
            let started = await player.play()
            guard !Task.isCancelled, revision == expected, !isClosed, validate() else {
                if revision == expected { close() }
                return
            }
            isPlaying = started
            if !started { message = "This saved audio cannot be played right now."; pause() }
        }
    }

    func pause() {
        revision += 1; command?.cancel(); command = nil
        isPlaying = false
        let stopping = player?.stop()
        session.deactivate(after: stopping)
    }

    func checkScope() {
        if !validate() { close() }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true; isReady = false
        pause(); player = nil
        message = "The saved audio is unavailable. Your request has been kept."
    }
}
