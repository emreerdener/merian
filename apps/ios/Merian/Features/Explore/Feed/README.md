# Explore Feed

The `Feed` directory drives the core social timeline of the application.

## Purpose
This area manages the discovery of community observations. It supports multiple feed variants: the global public feed, a following-only feed, trending observations, and geographically nearby posts. It handles pagination, likes, and comment interactions backed by Supabase RPCs.

## Video Playback

`ExplorePublicMediaView` is the shared media host for feed cards, post detail,
and Community ID media previews. Feed and detail are the only autoplay surfaces:
they start public videos muted, share the persisted mute preference, and keep one
active Explore player at a time. Feed autoplay still respects Low Power Mode;
post detail may autoplay after navigation because the user explicitly opened the
post.

Feed autoplay always re-enters muted. If the user unmutes a feed video and then
opens that post, detail inherits the current mute state. Leaving detail resets
the shared preference to muted before feed playback resumes, preventing audio
from continuing in the background when Explore is reopened or uncovered.

Feed audio and video reserve a 96-point square at the center of the media above
the full-card navigation gesture. A single tap there plays or pauses locally,
even after the 58-point visual control fades; a double tap likes the post. A
single tap outside that center zone still opens post detail, and an outer double
tap still likes. The center zone remains a VoiceOver Play/Pause button. Detail
media keeps its existing local playback controls.

Video recovery is coordinated through `ExploreVideoPlaybackCoordinator` in
`Feed/Models`. `ExploreView` owns one coordinator and injects it into the
Explore environment. Sheet hosts use `.exploreVideoOverlayLifecycle(...)`
instead of ad-hoc `NotificationCenter` events or paired manual pause/resume
calls. The coordinator tracks overlay tokens, nested overlay depth,
`pauseGeneration`, and `resumeGeneration`, so playback resumes only after the
final Explore overlay is gone.

When a covered video resumes, `ExplorePublicMediaView` treats the interruption
as recoverable: it saves the current time, rebuilds the `AVPlayer` and
`AVPlayerLayer`, seeks back, and attempts autoplay if eligible. If playback
cannot restart, the centered play control remains visible so the user can repair
playback without closing and reopening Explore. A hidden unhealthy video tap
repairs/reveals playback before feed navigation; healthy feed taps still open
post detail.

Use `MerianLog.exploreVideo` while diagnosing this path. The media view logs
player ids, surface names, player/layer rebuilds, overlay pauses/resumes,
`timeControlStatus`, watchdog results, visible-control transitions, and tap
recovery.

## Standalone Audio Playback and Boost

`ExplorePublicMediaView` also owns standalone-audio playback. It renders the
saved spectrogram with a moving playhead and elapsed/total timestamp, and it
participates in the same one-active-player and audio-session lifecycle as other
Explore media.

Feed-card and post-detail ellipsis menus expose **Boost audio** only when the
primary media item is standalone audio. `ExploreAudioBoostPreferenceStore`
remembers enabled post IDs locally for 180 days, capped at 500 entries, so each
post has an independent setting. An in-process preference notification keeps
visible feed and detail players synchronized. Preferences are device-only and
are never written to Supabase.

`ExploreAudioBoostProcessor` creates a bounded temporary enhanced WAV using
RMS/peak analysis, at most 18 dB of adaptive gain, gentle low-frequency rumble
reduction, and peak limiting. It never changes or uploads the canonical
recording. Switching modes preserves position and play/pause state; preparation
failure falls back to the original audio. The processor keeps at most eight
temporary enhanced files. Images, videos, mixed-media ordering, and feed
playback are unaffected.

Once the enhanced file is ready and active, the spectrogram shows a small
**Boosted audio** badge in its bottom-left corner. The badge is withheld during
preparation and after fallback to original playback, so it always describes the
audio source the player can actually use.

Saved preferences and cross-surface notifications prepare silently. The
**Boosting audio…** and fallback messages are reserved for a one-shot action
token created when the user explicitly selects **Boost audio** in the currently
visible menu. Completing, failing, or cancelling preparation consumes that
token; silent restoration still shows **Boosted audio** after enhancement succeeds.

Analytics use `ExploreAudioBoostChanged` with an action, surface, and optional
coarse gain band only. Never add post IDs, media URLs, filenames, transcripts,
or captured audio to these events.

## Overlay Ownership

Any new sheet or UIKit share surface launched from Explore feed/detail that can
cover a playing video must participate in the coordinator:

- SwiftUI sheets should derive a stable `isPresented` boolean and apply
  `.exploreVideoOverlayLifecycle(isPresented:reason:)` on the host view.
- UIKit presenters such as `UIActivityViewController` should call
  `beginOverlay(reason:)` before presentation and end the returned token in the
  completion callback.
- Nested sheets are safe as long as each host owns exactly one token for its
  own presented state. Do not send global playback notifications.
