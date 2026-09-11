# Core Media

The `Media` directory owns reusable, bounded audio/video processing and
player-lifecycle infrastructure. It does not own feature navigation, global UI
feedback, or durable scan state.

## Playback dependency boundary

`MediaPlaybackDependencies` is the initializer-injected adapter for unmuted
`AVPlayer` audio-session admission, source acquisition, boost preparation,
telemetry, and haptic feedback. Core components use typed
`MediaPlaybackFeedbackEvent` values and a neutral `media` namespace. Insight's
feature-owned adapter supplies the legacy `media.insight` namespace and Insight
boost telemetry without teaching Core views about their host feature.

`AudioPlaybackSessionController` owns one token-aware playback-ducking lease for
a mounted media surface. It coalesces concurrent activation, detects and
reacquires a lease replaced by another audio owner, fences teardown during lease
validation, drains a cancelled activation before replacement, and releases only
the exact lease it acquired. It remains inactive while a surface is merely
mounted. A late activation or cleanup therefore cannot deactivate a newer
recording or playback owner. Callers explicitly invalidate pending controller
activation when their UI-owned play task is cancelled; cancellation that reaches
the coordinator before execution performs no process-wide mutation, while a
non-cooperative late lease is released. `AudioPlayerDelegate` is a main-actor
owner whose nonisolated AVFoundation callbacks transfer only player identity,
completion state, and error text back to UI state. Do not add unchecked
sendability to AVFoundation delegate or player state.

`AudioPlaybackCarouselPage` acquires no process-wide lease merely by appearing.
It awaits the controller immediately before every audible start, including
play-button, seek-resume, and fallback-player paths. This validation reacquires
a lease replaced by recording, speech, or another player while the page remained
mounted. Background and disappearance advance the player generation before
teardown, so a suspended activation cannot start a stale player afterward.
`MediaPlaybackDependencies` deliberately does not import AVFoundation or expose
the former synchronous `AVAudioPlayer` session-mutation effect. Its existing
async `activatePlaybackAudio` closure remains the narrow admission seam for
unmuted `AVPlayer` video; the live closure delegates to the token-aware
coordinator rather than configuring `AVAudioSession` itself. Feature adapters
otherwise remain limited to source, boost, telemetry, and feedback policy.

Deterministic lease-lifecycle coverage lives in
`MerianTests/Core/Media/AudioPlaybackSessionControllerTests.swift`; keep those
tests with the reusable owner rather than folding them into the Core Hardware
coordinator suite. The same suite prevents Explore Shared media from regaining a
direct `AVAudioSession.sharedInstance()` mutation, requires shared audio paths
to validate the exact lease before every audible start, and keeps generic
playback dependencies free of direct audio-session mutation.

Before release, use a signed physical device to verify that merely mounting an
Insight or Explore audio page does not interrupt active recording or dictation.
Exercise first play, seek-resume, owner replacement followed by resume,
background/disappearance during activation, headphone and route changes, and
return to recording or speech. Simulator lease tests are deterministic evidence
for ownership but do not validate the process-wide `AVAudioSession` handoff.

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
- `AudioSpectrogramRenderer` owns the shared perceptual palette, bounded RGBA
  raster construction, and live-horizon versus fit-to-data layout used by
  Capture Record, Insight playback, and saved thumbnails. The renderer has no
  feature lifecycle or interaction state; the shared SwiftUI surface lives in
  `Core/UI/Components/AudioSpectrogramView.swift`.
- `AudioSpectrogramThumbnailLoader` coalesces and caches bounded spectrogram
  decodes for Scans and Explore. Feature components receive it through their
  owning dependency boundary instead of resolving it directly.
- `SendableCGImage` is the domain-neutral immutable image wrapper used when
  Capture and Insights transfer bounded `CGImage` results across structured
  concurrency boundaries without introducing UIKit image ownership.
- `ImageCropProcessor` owns domain-neutral square-crop geometry and bounded
  WebP/JPEG encoding for Capture media preparation, Capture's interactive crop,
  and Profile avatar preparation. Feature views do not own its ImageIO work.

## Media export

`MediaExportService` is the cross-feature boundary used by Insight and Scans.
Callers construct Sendable `MediaSaveRequest`, `DiscoveryShareRequest`, or
`BatchDiscoveryShareRequest` values before suspension. The service accepts
absolute, file-URL, and Documents-relative local media and permits remote media
only from the exact HTTPS `media.merian.app` host. Its ephemeral, cookie-free
session refuses a cross-host redirect before following it and revalidates the
final response URL before consuming a download, so manually constructed requests
and redirects cannot bypass the source boundary. Remote share previews remain
file-backed through ImageIO rather than buffering the full response as `Data`.
Single shares use a 2,048 px maximum dimension; batch shares use 1,024 px and
the Scans selection cap remains 20, bounding the retained activity payload.
PhotoKit saves and batch work stay sequential and cancellation-aware in one
private actor-owned pipeline.

The service returns `MediaSharePayload` values containing immutable
`SendableCGImage` and text items. UIKit conversion and share-sheet presentation
occur on the main actor at the feature dependency edge. Features own
presentation-session and operation-generation fencing; Core owns no navigation,
toast, or sheet state.

See
[Event and Presentation Routing](../../../../../docs/system-architecture/10-event-and-presentation-routing.md#media-notification-lifetime)
and
[Zero-OOM and Concurrency](../../../../../docs/system-architecture/02-zero-oom-and-concurrency.md).
