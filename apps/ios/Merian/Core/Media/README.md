# Core Media

The `Media` directory owns reusable, bounded audio/video processing and
player-lifecycle infrastructure. It does not own feature navigation, global UI
feedback, or durable scan state.

## Playback observation lifetime

`MediaPlaybackObservation` is the single owner-scoped bridge for AVPlayer KVO,
AVPlayerItem completion/stall/failure notifications, and periodic time
observation. Explore public media, inline Insight video, and fullscreen Insight
video each retain one observation object for the lifetime of their mounted
surface.

Replacing a player detaches KVO and removes notification and time-observer
tokens from the exact old player/item before registering the replacement. Every
callback carries the current player/item generation, so a callback already
queued for player A cannot mutate player B. `detach()` and `deinit` remove all
tokens; callbacks capture the observation, player, and item weakly.

Do not add ad hoc observer arrays or rely on view disappearance alone to clean
up a player. A new playback surface must retain this owner and explicitly call
`observe(_:)` for replacement and `detach()` when its playback lifetime ends.

## Bounded media helpers

- `AudioBoostProcessor` creates capped temporary enhanced audio without changing
  or uploading the canonical recording.
- `AudioSpectrogramSeekingPolicy` normalizes non-finite seeking inputs and
  clamps display progress before geometry is derived.
- `AudioSpectrogramThumbnailLoader` coalesces and caches bounded spectrogram
  decodes for Scans and Explore. Feature components receive it through their
  owning dependency boundary instead of resolving it directly.

See
[Event and Presentation Routing](../../../../../docs/system-architecture/10-event-and-presentation-routing.md#media-notification-lifetime)
and
[Zero-OOM and Concurrency](../../../../../docs/system-architecture/02-zero-oom-and-concurrency.md).
