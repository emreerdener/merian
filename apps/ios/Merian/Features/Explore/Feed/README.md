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
