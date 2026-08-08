import AVFoundation
import Combine
import Observation

enum MediaPlaybackLifecycleEvent: Equatable {
    case didReachEnd
    case playbackStalled
    case failedToPlayToEnd
}

/// Owns every observer associated with one `AVPlayer` generation.
///
/// The object intentionally publishes state instead of retaining view callbacks. This keeps
/// SwiftUI state boxes out of NotificationCenter/KVO retain graphs and ensures a callback from
/// a replaced player can never mutate the new player's presentation state.
@MainActor
@Observable
final class MediaPlaybackObservation {
    private(set) var timeControlStatus: AVPlayer.TimeControlStatus = .paused
    private(set) var itemStatus: AVPlayerItem.Status = .unknown
    private(set) var currentTimeSeconds = 0.0
    private(set) var durationSeconds = 0.0
    private(set) var lastEvent: MediaPlaybackLifecycleEvent?
    private(set) var eventSequence: UInt64 = 0

    @ObservationIgnored private weak var observedPlayer: AVPlayer?
    @ObservationIgnored private weak var observedItem: AVPlayerItem?
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var notificationTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var timeControlStatusCancellable: AnyCancellable?
    @ObservationIgnored private var itemStatusCancellable: AnyCancellable?
    @ObservationIgnored private var periodicTimeObserver: Any?

    deinit {
        if let periodicTimeObserver, let observedPlayer {
            observedPlayer.removeTimeObserver(periodicTimeObserver)
        }
        timeControlStatusCancellable?.cancel()
        itemStatusCancellable?.cancel()
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func observe(
        _ player: AVPlayer,
        periodicInterval: CMTime? = nil
    ) {
        detach()

        generation &+= 1
        let observedGeneration = generation
        let item = player.currentItem
        observedPlayer = player
        observedItem = item
        timeControlStatus = player.timeControlStatus
        itemStatus = item?.status ?? .unknown
        updateTime(from: player.currentTime(), item: item)

        if let item {
            notificationTokens = [
                makeNotificationToken(
                    name: .AVPlayerItemDidPlayToEndTime,
                    event: .didReachEnd,
                    player: player,
                    item: item,
                    generation: observedGeneration
                ),
                makeNotificationToken(
                    name: .AVPlayerItemPlaybackStalled,
                    event: .playbackStalled,
                    player: player,
                    item: item,
                    generation: observedGeneration
                ),
                makeNotificationToken(
                    name: .AVPlayerItemFailedToPlayToEndTime,
                    event: .failedToPlayToEnd,
                    player: player,
                    item: item,
                    generation: observedGeneration
                )
            ]

            itemStatusCancellable = item.publisher(for: \.status, options: [.initial, .new])
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak player, weak item] status in
                    MainActor.assumeIsolated {
                        guard let self,
                              self.matches(
                                  player: player,
                                  item: item,
                                  generation: observedGeneration
                              ) else { return }
                        self.itemStatus = status
                        self.updateTime(from: player?.currentTime() ?? .zero, item: item)
                    }
                }
        }

        timeControlStatusCancellable = player.publisher(
            for: \.timeControlStatus,
            options: [.initial, .new]
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self, weak player] status in
            MainActor.assumeIsolated {
                guard let self,
                      self.matches(player: player, generation: observedGeneration) else { return }
                self.timeControlStatus = status
            }
        }

        if let periodicInterval {
            periodicTimeObserver = player.addPeriodicTimeObserver(
                forInterval: periodicInterval,
                queue: .main
            ) { [weak self, weak player, weak item] time in
                MainActor.assumeIsolated {
                    guard let self,
                          self.matches(
                              player: player,
                              item: item,
                              generation: observedGeneration
                          ) else { return }
                    self.updateTime(from: time, item: item)
                }
            }
        }
    }

    func isObserving(_ player: AVPlayer) -> Bool {
        observedPlayer === player
    }

    func detach() {
        // Invalidate callback identity before removing any observer. A callback already queued on
        // the main run loop will therefore be ignored even if it arrives during teardown.
        generation &+= 1

        if let periodicTimeObserver, let observedPlayer {
            observedPlayer.removeTimeObserver(periodicTimeObserver)
        }
        periodicTimeObserver = nil

        timeControlStatusCancellable?.cancel()
        timeControlStatusCancellable = nil
        itemStatusCancellable?.cancel()
        itemStatusCancellable = nil

        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        notificationTokens.removeAll(keepingCapacity: true)

        observedItem = nil
        observedPlayer = nil
        timeControlStatus = .paused
        itemStatus = .unknown
        currentTimeSeconds = 0
        durationSeconds = 0
        lastEvent = nil
    }

    private func makeNotificationToken(
        name: Notification.Name,
        event: MediaPlaybackLifecycleEvent,
        player: AVPlayer,
        item: AVPlayerItem,
        generation: UInt64
    ) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: name,
            object: item,
            queue: .main
        ) { [weak self, weak player, weak item] _ in
            MainActor.assumeIsolated {
                guard let self,
                      self.matches(player: player, item: item, generation: generation) else { return }
                self.lastEvent = event
                self.eventSequence &+= 1
            }
        }
    }

    private func matches(player: AVPlayer?, generation: UInt64) -> Bool {
        guard self.generation == generation, let player else { return false }
        return observedPlayer === player
    }

    private func matches(
        player: AVPlayer?,
        item: AVPlayerItem?,
        generation: UInt64
    ) -> Bool {
        guard matches(player: player, generation: generation), let player, let item else {
            return false
        }
        return observedItem === item && player.currentItem === item
    }

    private func updateTime(from time: CMTime, item: AVPlayerItem?) {
        currentTimeSeconds = time.isNumeric && time.seconds.isFinite
            ? max(0, time.seconds)
            : 0

        guard let duration = item?.duration,
              duration.isNumeric,
              duration.seconds.isFinite,
              duration.seconds > 0 else {
            durationSeconds = 0
            return
        }
        durationSeconds = duration.seconds
    }
}
