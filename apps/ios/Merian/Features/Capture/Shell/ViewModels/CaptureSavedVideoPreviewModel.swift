import AVFoundation
import Observation

/// Explicit original-clip playback; the player never receives a filesystem capability.
@MainActor @Observable
final class CaptureSavedVideoPreviewModel {
    let player = AVPlayer()
    private(set) var isReady = false
    private(set) var isPlaying = false
    private(set) var isClosed = false
    private(set) var message: String?
    @ObservationIgnored private var source: MemoryVideoAsset?
    @ObservationIgnored private let validate: () -> Bool
    @ObservationIgnored private let session: AudioPlaybackSessionController
    @ObservationIgnored private var command: Task<Void, Never>?
    @ObservationIgnored private var revision = 0

    init(bytes: Data, validate: @escaping () -> Bool, session: AudioPlaybackSessionController? = nil) throws {
        self.validate = validate; self.session = session ?? .init()
        source = try MemoryVideoAsset(bytes: bytes, validate: validate)
        player.automaticallyWaitsToMinimizeStalling = false
    }

    func load() async {
        guard !isClosed, validate(), let source else { close(); return }
        do {
            let playable = try await source.asset.load(.isPlayable)
            guard playable, !Task.isCancelled, !isClosed, validate() else { close(); return }
            player.replaceCurrentItem(with: AVPlayerItem(asset: source.asset))
            isReady = true
        } catch { close() }
    }

    func toggle() {
        guard !isClosed, isReady, validate() else { close(); return }
        if isPlaying || command != nil { pause(); return }
        let expected = revision
        command = Task { [weak self] in
            guard let self else { return }
            defer { if revision == expected { command = nil } }
            guard await session.activate(), !Task.isCancelled, revision == expected, !isClosed, validate() else {
                if revision == expected { close() }
                return
            }
            if let item = player.currentItem, item.duration.isNumeric,
               player.currentTime() >= item.duration {
                // Queue a rewind on this item; no completion callback can resume a retired preview.
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: { _ in })
            }
            player.play(); isPlaying = true
        }
    }

    func pause() {
        revision += 1; command?.cancel(); command = nil
        player.pause(); isPlaying = false; session.deactivate()
    }

    func checkScope() {
        guard !isClosed else { return }
        guard validate(), player.currentItem?.status != .failed else { close(); return }
        if isPlaying, let item = player.currentItem, item.duration.isNumeric,
           player.currentTime() >= item.duration { pause() }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true; isReady = false
        pause(); player.replaceCurrentItem(with: nil)
        source?.close(); source = nil
        message = "The saved video is unavailable. Your request has been kept."
    }
}
