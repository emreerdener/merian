# Explore Feed

The `Feed` directory drives the core social timeline of the application.

## Purpose
This area manages the discovery of community observations. It supports multiple feed variants: the global public feed, a following-only feed, trending observations, and geographically nearby posts. It handles pagination, likes, and comment interactions backed by Supabase RPCs.

## Post-detail reference gallery

An Explore post owns its primary media presentation. Its hero URL, every
resolved media-item URL, and every media-item thumbnail URL are therefore passed
to `ExplorePostDetail.referenceGalleryImages(excluding:)` before
`ExploreReferenceGallery` is constructed. The shared reference-media policy
removes Naturebook URL variants that resolve to the same host/object path while
keeping other scans' Naturebook images and unrelated external references.

The filtered list retains server order and the existing Naturebook, Wikipedia,
and GBIF attribution mapping. When no references survive, post detail omits the
reference gallery and its page indicators entirely. The iOS filtering remains
a client-side defense even though `get_explore_post_detail` also excludes the
backing scan's `image_storage_urls`, allowing backend and app changes to roll out
independently.

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

Explore post detail makes the spectrogram seekable: tapping jumps to a time and
dragging pauses temporarily while the playmarker follows the gesture, then
resumes only when playback was active before the drag. The center playback
control remains independently tappable and VoiceOver can adjust position in
five-second steps. Feed spectrograms intentionally do not seek because their
center and outer regions retain playback, like, and detail-navigation gestures.
`AudioSpectrogramSeekingPolicy` treats non-finite progress, duration, width, and
marker values as a safe zero and clamps finite playmarker offsets into the
available width. Do not calculate frame offsets directly from player time.

Detail zoom layout uses `ExploreDetailZoomLayoutPolicy.resolvedSize(...)` to
accept only finite positive proposed dimensions. It can use one valid dimension
when the other is invalid and returns `nil` when neither is usable, allowing
SwiftUI to choose an unconstrained fallback without an invalid-frame warning.
Any new geometry-dependent detail overlay must use the same finite guards.

User-initiated playback uses Merian's shared `HapticManager`: play and enabling
audio boost receive a medium confirmation, pause and mute changes receive light
feedback, and seeking produces one subtle begin pulse plus one commit selection.
Autoplay, playhead ticks, saved-setting restoration, and cross-surface state
updates never emit haptics. Explicit audio-boost failures use the standard error
feedback and respect the global haptics and expedition-mode preferences.

Feed cards and post detail with standalone primary audio expose a compact,
filled **Boost audio** pill at the bottom-left of the spectrogram, while their
ellipsis menus retain the same action. The pill owns its hit-test region above
feed navigation and detail spectrogram-seeking gestures; the rest of the media
keeps the existing navigation, seeking, and center-playback behavior.
`ExploreAudioBoostPreferenceStore`
remembers enabled post IDs locally for 180 days, capped at 500 entries, so each
post has an independent setting. An in-process preference notification keeps
visible feed and detail players synchronized. Preferences are device-only and
are never written to Supabase.

The shared `AudioBoostProcessor` in `Core/Media` creates a bounded temporary enhanced WAV using
RMS/peak analysis, at most 18 dB of adaptive gain, gentle low-frequency rumble
reduction, and peak limiting. It never changes or uploads the canonical
recording. Switching modes preserves position and play/pause state; preparation
failure falls back to the original audio. The processor keeps at most eight
temporary enhanced files. Images, videos, mixed-media ordering, and feed
playback are unaffected.

Once the enhanced file is ready and active, the feed pill transitions to
**Boosted audio** without its chevron and remains tappable to restore original
audio. Post detail retains its passive **Boosted audio** badge. The boosted
state is withheld during preparation and after fallback to original playback,
so it always describes the audio source the player can actually use.
Direct controls read **Boosting…** while preparing the enhanced source and
**Reverting…** while restoring the original; both transition states disable the
control until the source swap completes.

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
